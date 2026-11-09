import 'dart:async';
import 'dart:convert';

import 'package:cloud_music/lyrics/lyrics_controller.dart';
import 'package:cloud_music/lyrics/lyrics_matching.dart';
import 'package:cloud_music/lyrics/lyrics_models.dart';
import 'package:cloud_music/lyrics/lyrics_platform.dart';
import 'package:cloud_music/models.dart';
import 'package:flutter_test/flutter_test.dart';

const song = Track(
  id: 'one.mp3',
  title: 'Night Light',
  artist: 'The Singer',
  duration: Duration(seconds: 180),
);
const nextSong = Track(
  id: 'two.mp3',
  title: 'Morning Light',
  artist: 'The Singer',
  duration: Duration(seconds: 200),
);

Map<String, dynamic> row({
  String title = 'Night Light',
  String artist = 'The Singer',
  String album = '',
  num duration = 180,
  String lyrics = '[00:01]First line',
}) => {
  'id': 1,
  'trackName': title,
  'artistName': artist,
  'albumName': album,
  'duration': duration,
  'syncedLyrics': lyrics,
};
LyricsHttpResponse response(List<Map<String, dynamic>> rows) =>
    LyricsHttpResponse(200, jsonEncode(rows));

class AutomaticPlatform implements LyricsPlatform {
  String? cache;
  final queries = <Uri>[];
  final writes = <String>[];
  Future<LyricsHttpResponse> Function(Uri)? handler;
  bool disposed = false;
  @override
  Future<LyricsHttpResponse> get(Uri uri) async {
    queries.add(uri);
    return handler == null ? response([row()]) : handler!(uri);
  }

  @override
  Future<String?> readCache() async => cache;
  @override
  Future<void> writeCache(String value) async {
    cache = value;
    writes.add(value);
  }

  @override
  Future<String?> importFile() async => null;
  @override
  void dispose() {
    disposed = true;
  }
}

Future<void> settleAutomatic(WidgetTester tester) async {
  await tester.pump(const Duration(milliseconds: 701));
  // Bounded fallback queries are deliberately spaced by 250ms.
  for (var stage = 0; stage < 4; stage++) {
    await tester.pump(const Duration(milliseconds: 251));
  }
  await tester.pump();
}

void main() {
  group('Conservative automatic matching', () {
    LyricsCandidate candidate(Map<String, dynamic> value) =>
        LyricsCandidate.fromJson(value);
    test('normalizes width, punctuation, spacing, case and feat spelling', () {
      final match = candidate(row(title: 'ＮＩＧＨＴ—ＬＩＧＨＴ', artist: 'the singer'));
      expect(confidentLyricsMatch(song, [match]), same(match));
      expect(
        normalizeLyricsIdentity('A featuring B'),
        normalizeLyricsIdentity('A ft. B'),
      );
    });
    for (final entry in <String, Map<String, dynamic>>{
      'wrong artist': row(artist: 'Another Singer'),
      'live version': row(title: 'Night Light (Live)'),
      'remix version': row(title: 'Night Light - Remix'),
      'album-only live version': row(album: 'Live in the Test Garden'),
      'album-only karaoke version': row(album: '伴奏版'),
      'instrumental title version': row(title: 'Night Light (Instrumental)'),
      'long duration difference': row(duration: 184),
      'unknown candidate duration': row(duration: 0),
    }.entries) {
      test('rejects ${entry.key}', () {
        expect(confidentLyricsMatch(song, [candidate(entry.value)]), isNull);
      });
    }
    test('duration tolerance is inclusive at three seconds', () {
      expect(
        confidentLyricsMatch(song, [candidate(row(duration: 183))]),
        isNotNull,
      );
      expect(
        confidentLyricsMatch(song, [candidate(row(duration: 183.001))]),
        isNull,
      );
    });
    test('missing artist or duration cannot auto-select', () {
      expect(
        confidentLyricsMatch(song.copyWith(artist: ''), [candidate(row())]),
        isNull,
      );
      expect(
        confidentLyricsMatch(song.copyWith(duration: Duration.zero), [
          candidate(row()),
        ]),
        isNull,
      );
    });
    test('distinct lyrics stay ambiguous, identical duplicates are safe', () {
      final first = candidate(row());
      expect(
        confidentLyricsMatch(song, [
          first,
          candidate(row(lyrics: '[00:02]Different')),
        ]),
        isNull,
      );
      expect(
        confidentLyricsMatch(song, [first, candidate(row())]),
        same(first),
      );
    });
    test('matching album disambiguates otherwise valid versions', () {
      final wanted = candidate(row(album: 'Original'));
      final other = candidate(
        row(album: 'Compilation', lyrics: '[00:02]Other'),
      );
      expect(
        confidentLyricsMatch(song.copyWith(album: 'Original'), [other, wanted]),
        same(wanted),
      );
    });
  });

  group('Automatic controller', () {
    late AutomaticPlatform platform;
    late LyricsController controller;
    void automaticTest(String name, Future<void> Function(WidgetTester) body) {
      testWidgets(name, (tester) async {
        platform = AutomaticPlatform();
        controller = LyricsController(platform: platform);
        try {
          await body(tester);
        } finally {
          if (!platform.disposed) controller.dispose();
        }
      });
    }

    automaticTest('off by default makes no request, including track updates', (
      tester,
    ) async {
      controller.selectTrack(song);
      await controller.initialize();
      for (var i = 0; i < 5; i++) {
        controller.selectTrack(song);
        await settleAutomatic(tester);
      }
      expect(controller.automaticEnabled, false);
      expect(platform.queries, isEmpty);
    });

    automaticTest(
      'enabling searches current track after debounce and persists consent',
      (tester) async {
        controller.selectTrack(song);
        await controller.setAutomaticSearch(true);
        await tester.pump(const Duration(milliseconds: 699));
        expect(platform.queries, isEmpty);
        await tester.pump(const Duration(milliseconds: 2));
        expect(platform.queries, hasLength(1));
        expect(controller.document?.text, contains('First line'));
        expect(jsonDecode(platform.cache!)['automaticSearch'], true);
        expect(controller.busy, false);
      },
    );

    automaticTest('quick switching searches only final track', (tester) async {
      platform.handler = (uri) async =>
          response([row(title: 'Morning Light', duration: 200)]);
      controller.selectTrack(song);
      await controller.setAutomaticSearch(true);
      await tester.pump(const Duration(milliseconds: 300));
      controller.selectTrack(nextSong);
      await settleAutomatic(tester);
      expect(
        platform.queries.single.queryParameters['track_name'],
        'Morning Light',
      );
      expect(controller.document, isNotNull);
    });

    automaticTest('same-track time updates do not create duplicate traffic', (
      tester,
    ) async {
      platform.handler = (_) async => response([]);
      controller.selectTrack(song);
      await controller.setAutomaticSearch(true);
      await settleAutomatic(tester);
      for (var i = 0; i < 10; i++) {
        controller.selectTrack(song);
        await settleAutomatic(tester);
      }
      expect(platform.queries, hasLength(1));
      expect(controller.notice, contains('没有找到'));
    });

    automaticTest(
      'late duration selects already fetched results without another request',
      (tester) async {
        controller.selectTrack(song.copyWith(duration: Duration.zero));
        await controller.setAutomaticSearch(true);
        await settleAutomatic(tester);
        expect(controller.document, isNull);
        expect(controller.candidates, hasLength(1));
        controller.selectTrack(song);
        await settleAutomatic(tester);
        expect(controller.document, isNotNull);
        expect(platform.queries, hasLength(1));
      },
    );

    automaticTest(
      'missing artist searches title only but requires manual choice',
      (tester) async {
        controller.selectTrack(song.copyWith(artist: ''));
        await controller.setAutomaticSearch(true);
        await settleAutomatic(tester);
        expect(
          platform.queries.single.queryParameters.containsKey('artist_name'),
          false,
        );
        expect(controller.document, isNull);
        expect(controller.candidates, hasLength(1));
        await controller.choose(controller.candidates.single);
        expect(controller.document, isNotNull);
      },
    );

    automaticTest('empty album-filtered results retry once without album', (
      tester,
    ) async {
      platform.handler = (uri) async => response(
        uri.queryParameters.containsKey('album_name') ? [] : [row()],
      );
      controller.selectTrack(song.copyWith(album: 'Wrong Compilation'));
      await controller.setAutomaticSearch(true);
      await settleAutomatic(tester);
      expect(platform.queries, hasLength(2));
      expect(
        platform.queries.first.queryParameters['album_name'],
        'Wrong Compilation',
      );
      expect(
        platform.queries.last.queryParameters.containsKey('album_name'),
        false,
      );
      expect(controller.document, isNotNull);
    });

    automaticTest(
      'setting and cached lyric restore offline across metadata updates',
      (tester) async {
        controller.selectTrack(
          song,
          source: 'local',
          sourceIdentity: 'drive-a',
        );
        await controller.setAutomaticSearch(true);
        await settleAutomatic(tester);
        final saved = platform.cache;
        controller.dispose();
        platform = AutomaticPlatform()..cache = saved;
        controller = LyricsController(platform: platform);
        controller.selectTrack(
          song.copyWith(title: 'Night-Light', album: 'New album'),
          source: 'local',
          sourceIdentity: 'drive-a',
        );
        await controller.initialize();
        await settleAutomatic(tester);
        expect(controller.automaticEnabled, true);
        expect(controller.document, isNotNull);
        expect(platform.queries, isEmpty);
        controller.selectTrack(
          song,
          source: 'local',
          sourceIdentity: 'different-drive',
        );
        expect(controller.document, isNull);
        await settleAutomatic(tester);
        expect(platform.queries, hasLength(1));
      },
    );

    for (final correction in <String, Track>{
      'title': song.copyWith(title: 'Another Song'),
      'artist': song.copyWith(artist: 'Another Singer'),
      'version': song.copyWith(title: 'Night Light (Live)'),
      'duration': song.copyWith(duration: const Duration(seconds: 190)),
    }.entries) {
      automaticTest(
        'late contradictory ${correction.key} invalidates automatic cache',
        (tester) async {
          controller.selectTrack(song);
          await controller.setAutomaticSearch(true);
          await settleAutomatic(tester);
          expect(controller.document, isNotNull);
          controller.selectTrack(correction.value);
          expect(controller.document, isNull);
          await settleAutomatic(tester);
          expect(controller.document, isNull);
        },
      );

      automaticTest(
        'persisted automatic provenance rejects changed ${correction.key} after reload',
        (tester) async {
          controller.selectTrack(song);
          await controller.setAutomaticSearch(true);
          await settleAutomatic(tester);
          expect(controller.document, isNotNull);
          final saved = platform.cache;
          controller.dispose();
          platform = AutomaticPlatform()..cache = saved;
          controller = LyricsController(platform: platform);
          controller.selectTrack(correction.value);
          await controller.initialize();
          expect(controller.document, isNull);
          await settleAutomatic(tester);
          expect(controller.document, isNull);
        },
      );
    }

    automaticTest(
      'equivalent punctuation preserves automatic lyrics without another request',
      (tester) async {
        controller.selectTrack(song);
        await controller.setAutomaticSearch(true);
        await settleAutomatic(tester);
        final original = controller.document;
        expect(original, isNotNull);
        controller.selectTrack(
          song.copyWith(title: 'Night-Light', artist: 'THE SINGER'),
        );
        expect(controller.document, same(original));
        await settleAutomatic(tester);
        expect(platform.queries, hasLength(1));
      },
    );

    for (final manualAction in ['import', 'choose']) {
      automaticTest(
        'manual $manualAction replaces automatic provenance and survives corrected metadata and reload',
        (tester) async {
          controller.selectTrack(song);
          await controller.setAutomaticSearch(true);
          await settleAutomatic(tester);
          expect(controller.document, isNotNull);
          if (manualAction == 'import') {
            await controller.importText('[00:01]Manually imported');
          } else {
            await controller.search(
              title: song.title,
              artist: song.artist,
              album: '',
            );
            await controller.choose(controller.candidates.single);
          }
          final manualText = controller.document!.text;
          final corrected = song.copyWith(
            title: 'Corrected title',
            artist: 'Corrected artist',
            duration: const Duration(seconds: 220),
          );
          controller.selectTrack(corrected);
          expect(controller.document?.text, manualText);
          final saved = platform.cache;
          controller.dispose();
          platform = AutomaticPlatform()..cache = saved;
          controller = LyricsController(platform: platform);
          controller.selectTrack(corrected);
          await controller.initialize();
          await settleAutomatic(tester);
          expect(controller.document?.text, manualText);
          expect(platform.queries, isEmpty);
        },
      );
    }

    automaticTest(
      'legacy cache keys migrate without opting in to automatic requests',
      (tester) async {
        final key = jsonEncode([
          'local',
          '',
          'folder',
          song.id,
          song.title,
          song.artist,
          '',
        ]);
        platform.cache = jsonEncode({
          'version': 1,
          'entries': {
            key: LyricsDocument.parse('[00:01]Legacy lyric').toJson(),
          },
        });
        controller.selectTrack(
          song.copyWith(title: 'New tag'),
          source: 'local',
          folder: 'folder',
        );
        await controller.initialize();
        await settleAutomatic(tester);
        expect(controller.document?.text, contains('Legacy lyric'));
        expect(controller.automaticEnabled, false);
        expect(platform.queries, isEmpty);
      },
    );

    for (final action in ['cancel', 'disable', 'dispose', 'switch']) {
      automaticTest('$action ignores an old in-flight response', (
        tester,
      ) async {
        final pending = Completer<LyricsHttpResponse>();
        platform.handler = (_) => pending.future;
        controller.selectTrack(song);
        await controller.setAutomaticSearch(true);
        await settleAutomatic(tester);
        expect(controller.searchingAutomatically, true);
        switch (action) {
          case 'cancel':
            controller.cancelSearch();
          case 'disable':
            await controller.setAutomaticSearch(false);
          case 'dispose':
            controller.dispose();
          case 'switch':
            controller.selectTrack(nextSong);
        }
        pending.complete(response([row()]));
        await tester.pump();
        expect(controller.document, isNull);
        expect(controller.candidates, isEmpty);
        if (action == 'switch') {
          platform.handler = (_) async =>
              response([row(title: 'Morning Light', duration: 200)]);
          await settleAutomatic(tester);
          expect(controller.document, isNotNull);
          expect(platform.queries, hasLength(2));
        } else {
          await settleAutomatic(tester);
          expect(platform.queries, hasLength(1));
        }
      });
    }

    automaticTest(
      'disabling before debounce prevents all traffic and persists off',
      (tester) async {
        controller.selectTrack(song);
        await controller.setAutomaticSearch(true);
        await controller.setAutomaticSearch(false);
        await settleAutomatic(tester);
        expect(platform.queries, isEmpty);
        expect(jsonDecode(platform.cache!)['automaticSearch'], false);
      },
    );

    automaticTest(
      'ambiguous documents remain visible without an automatic selection',
      (tester) async {
        platform.handler = (_) async =>
            response([row(), row(lyrics: '[00:03]Other text')]);
        controller.selectTrack(song);
        await controller.setAutomaticSearch(true);
        await settleAutomatic(tester);
        expect(controller.document, isNull);
        expect(controller.candidates, hasLength(2));
        expect(controller.notice, contains('不能可靠确认'));
      },
    );

    automaticTest(
      '429 backoff prevents traffic across songs, then permits manual retry',
      (tester) async {
        var now = DateTime.utc(2026, 11, 8);
        controller.dispose();
        platform = AutomaticPlatform();
        controller = LyricsController(platform: platform, now: () => now);
        platform.handler = (_) async =>
            const LyricsHttpResponse(429, '', retryAfter: '30');
        controller.selectTrack(song);
        await controller.setAutomaticSearch(true);
        await settleAutomatic(tester);
        expect(controller.retryAfter, const Duration(seconds: 31));
        expect(controller.error, isNotNull);
        controller.selectTrack(nextSong);
        await settleAutomatic(tester);
        expect(platform.queries, hasLength(1));
        now = now.add(const Duration(seconds: 32));
        platform.handler = (_) async =>
            response([row(title: 'Morning Light', duration: 200)]);
        await controller.search(
          title: nextSong.title,
          artist: nextSong.artist,
          album: '',
        );
        expect(platform.queries, hasLength(2));
        expect(controller.candidates, hasLength(1));
        expect(
          controller.document,
          isNull,
          reason: 'Manual searches still require a choice',
        );
      },
    );

    automaticTest(
      'network failures settle cleanly without repeatedly requesting',
      (tester) async {
        platform.handler = (_) async => throw StateError('network unavailable');
        controller.selectTrack(song);
        await controller.setAutomaticSearch(true);
        await settleAutomatic(tester);
        expect(controller.error, isNotNull);
        expect(controller.busy, false);
        controller.selectTrack(song);
        await settleAutomatic(tester);
        expect(platform.queries, hasLength(1));
      },
    );
  });
}
