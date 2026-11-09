import 'dart:async';
import 'dart:convert';

import 'package:cloud_music/lyrics/lyrics_controller.dart';
import 'package:cloud_music/lyrics/lyrics_matching.dart';
import 'package:cloud_music/lyrics/lyrics_models.dart';
import 'package:cloud_music/lyrics/lyrics_platform.dart';
import 'package:flutter_test/flutter_test.dart';

import 'lyrics_automatic_test.dart' show AutomaticPlatform, song, row, response;

void main() {
  late AutomaticPlatform platform;
  late LyricsController controller;
  setUp(() {
    platform = AutomaticPlatform();
    controller = LyricsController(platform: platform)..selectTrack(song);
  });
  tearDown(() => controller.dispose());

  test('manual search drops restrictive album and reports stages', () async {
    final stages = <String?>[];
    controller.addListener(() => stages.add(controller.searchStage));
    platform.handler = (uri) async =>
        response(uri.queryParameters.containsKey('album_name') ? [] : [row()]);
    await controller.search(
      title: song.title,
      artist: song.artist,
      album: 'Wrong',
    );
    expect(platform.queries, hasLength(2));
    expect(controller.candidates, hasLength(1));
    expect(stages, contains('正在忽略专辑标签重试…'));
    expect(controller.searchStage, isNull);
    expect(controller.document, isNull);
  });

  test('manual artist is optional, title-only fallback is explicit', () async {
    platform.handler = (uri) async =>
        response(uri.queryParameters.containsKey('artist_name') ? [] : [row()]);
    await controller.search(title: song.title, artist: 'Bad tag', album: '');
    expect(platform.queries, hasLength(2));
    expect(controller.notice, contains('仅按歌名'));
    expect(controller.document, isNull);
    platform.queries.clear();
    await controller.search(title: song.title, artist: '', album: '');
    expect(platform.queries, hasLength(1));
    expect(controller.candidates, hasLength(1));
  });

  test('unrelated nonempty result does not prevent album fallback', () async {
    platform.handler = (uri) async => response([
      uri.queryParameters.containsKey('album_name')
          ? {...row(title: 'Wrong'), 'id': 2}
          : row(),
    ]);
    await controller.search(
      title: song.title,
      artist: song.artist,
      album: 'Wrong',
    );
    expect(platform.queries, hasLength(2));
    expect(controller.candidates.first.title, song.title);
  });

  test('script variants are bounded and deduplicated', () async {
    platform.handler = (_) async => response([]);
    await controller.search(title: '愛樂', artist: '樂隊', album: '專輯');
    expect(platform.queries.length, lessThanOrEqualTo(5));
    expect(
      platform.queries.map((q) => q.toString()).toSet().length,
      platform.queries.length,
    );
    expect(
      platform.queries.any((q) => q.queryParameters['track_name'] == '爱乐'),
      isTrue,
    );
  });

  test('cancelling pending search stops all fallback requests', () async {
    final pending = Completer<LyricsHttpResponse>();
    platform.handler = (_) => pending.future;
    final task = controller.search(title: '愛樂', artist: '樂隊', album: '專輯');
    controller.cancelSearch();
    pending.complete(response([]));
    await task;
    expect(platform.queries, hasLength(1));
    expect(controller.candidates, isEmpty);
  });

  test('synchronous cancellation on a stage stops request', () async {
    controller.addListener(() {
      if (controller.searchStage == '正在忽略专辑标签重试…') controller.cancelSearch();
    });
    platform.handler = (_) async => response([]);
    await controller.search(
      title: song.title,
      artist: song.artist,
      album: 'Wrong',
    );
    expect(platform.queries, hasLength(1));
  });

  test(
    'cancelling during fallback spacing prevents the next request',
    () async {
      final stageReady = Completer<void>();
      controller.addListener(() {
        if (controller.searchStage == '正在忽略专辑标签重试…' &&
            !stageReady.isCompleted) {
          stageReady.complete();
        }
      });
      platform.handler = (_) async => response([]);
      final task = controller.search(
        title: song.title,
        artist: song.artist,
        album: 'Wrong',
      );
      await stageReady.future;
      controller.cancelSearch();
      await task;
      expect(platform.queries, hasLength(1));
    },
  );

  for (final code in [429, 503]) {
    test('$code during fallback stops search and respects cooldown', () async {
      platform.handler = (_) async => platform.queries.length == 1
          ? response([])
          : LyricsHttpResponse(code, '', retryAfter: '120');
      await controller.search(title: '愛樂', artist: '樂隊', album: '專輯');
      expect(platform.queries, hasLength(2));
      expect(controller.retryAfter, isNotNull);
      await controller.search(title: '愛樂', artist: '樂隊', album: '');
      expect(platform.queries, hasLength(2));
    });
  }

  for (final failure in <Object>[
    StateError('Network unavailable'),
    TimeoutException('Timed out'),
    const LyricsHttpResponse(429, '', retryAfter: '120'),
  ]) {
    test('partial candidates survive fallback failure: $failure', () async {
      platform.handler = (_) async {
        if (platform.queries.length == 1) {
          return response([row(title: 'Possible alternate')]);
        }
        if (failure is LyricsHttpResponse) return failure;
        throw failure;
      };
      await controller.search(
        title: song.title,
        artist: song.artist,
        album: 'Wrong',
      );
      expect(platform.queries, hasLength(2));
      expect(controller.candidates, hasLength(1));
      expect(controller.notice, contains('部分搜索未完成'));
      expect(controller.error, isNotNull);
      expect(controller.document, isNull);
      expect(controller.busy, isFalse);
      await controller.choose(controller.candidates.single);
      expect(controller.document, isNotNull);
    });
  }

  test(
    'display preference persists while cached original remains intact',
    () async {
      await controller.importText('[00:01]愛樂\n[00:02]聽見');
      expect(controller.preferSimplified, isTrue);
      expect(controller.document!.lines.first.text, '爱乐');
      expect(controller.document, same(controller.document));
      expect(controller.originalDocument!.lines.first.text, '愛樂');
      expect(
        controller.document!.lines.first.time,
        controller.originalDocument!.lines.first.time,
      );
      await controller.setPreferSimplified(false);
      expect(controller.document, same(controller.originalDocument));
      final cache = jsonDecode(platform.cache!) as Map<String, dynamic>;
      expect(cache['preferSimplified'], isFalse);
      expect((cache['entries'] as Map).values.single['text'], contains('愛樂'));
      final restored = LyricsController(platform: platform)..selectTrack(song);
      await restored.initialize();
      expect(restored.preferSimplified, isFalse);
      expect(restored.document!.text, contains('愛樂'));
      restored.dispose();
    },
  );

  test('script normalization preserves traditional version flags', () {
    final traditional = LyricsCandidate.fromJson(
      row(title: '愛樂', artist: '樂隊'),
    );
    final track = song.copyWith(title: '爱乐', artist: '乐队');
    expect(confidentLyricsMatch(track, [traditional]), same(traditional));
    final live = LyricsCandidate.fromJson(
      row(title: '愛樂', artist: '樂隊', album: '現場演唱會'),
    );
    expect(confidentLyricsMatch(track, [live]), isNull);
  });

  test('synced wins only with identical text and unambiguous timeline', () {
    final plain = LyricsCandidate.fromJson({
      ...row(lyrics: ''),
      'plainLyrics': 'First line',
      'id': 2,
    });
    final synced = LyricsCandidate.fromJson(row());
    expect(confidentLyricsMatch(song, [plain, synced]), same(synced));
    final conflict = LyricsCandidate.fromJson({
      ...row(lyrics: '[00:02]First line'),
      'id': 3,
    });
    expect(confidentLyricsMatch(song, [plain, synced, conflict]), isNull);
    final wrong = LyricsCandidate.fromJson({...row(artist: 'Other'), 'id': 4});
    expect(rankLyricsCandidates(song, [wrong, plain]).first, same(plain));
  });
}
