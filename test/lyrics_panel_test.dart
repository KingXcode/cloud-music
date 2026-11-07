import 'dart:async';
import 'dart:convert';

import 'package:cloud_music/lyrics/lyrics_controller.dart';
import 'package:cloud_music/lyrics/lyrics_platform.dart';
import 'package:cloud_music/models.dart';
import 'package:cloud_music/ui/lyrics_panel.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// Original fictional test text, not excerpts from published lyrics.
const _track = Track(
  id: 'fictional-1',
  title: 'Paper Observatory',
  artist: 'Imaginary Test Ensemble',
  album: 'Unit Test Constellations',
  duration: Duration(seconds: 90),
);

class _Platform implements LyricsPlatform {
  final requests = <Uri>[];
  final writes = <String>[];
  String? imported;
  Completer<LyricsHttpResponse>? pending;
  LyricsHttpResponse response = LyricsHttpResponse(
    200,
    jsonEncode([
      {
        'id': 701,
        'trackName': _track.title,
        'artistName': _track.artist,
        'albumName': _track.album,
        'duration': 95,
        'syncedLyrics':
            '[00:01.00]A paper moon counts blue triangles\n'
            '[00:05.00]Our cardboard telescope folds the dawn',
      },
    ]),
  );

  @override
  Future<LyricsHttpResponse> get(Uri uri) {
    requests.add(uri);
    return pending?.future ?? Future.value(response);
  }

  @override
  Future<String?> readCache() async => null;
  @override
  Future<void> writeCache(String value) async => writes.add(value);
  @override
  Future<String?> importFile() async => imported;
  @override
  void dispose() {}
}

Finder _key(String value) => find.byKey(Key(value));

Future<void> _tap(WidgetTester tester, String key) async {
  await tester.ensureVisible(_key(key));
  await tester.tap(_key(key));
  await tester.pumpAndSettle();
}

Future<LyricsController> _mount(
  WidgetTester tester,
  _Platform platform, {
  Duration position = Duration.zero,
  ValueChanged<Duration>? onSeek,
  double textScale = 1,
}) async {
  final controller = LyricsController(platform: platform);
  await controller.initialize();
  controller.selectTrack(_track);
  addTearDown(controller.dispose);
  await tester.pumpWidget(
    MaterialApp(
      theme: ThemeData.dark(useMaterial3: true),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
      home: Scaffold(
        body: SingleChildScrollView(
          child: LyricsPanel(
            controller: controller,
            position: position,
            onSeek: onSeek ?? (_) {},
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return controller;
}

Future<void> _consentedSearch(WidgetTester tester) async {
  await _tap(tester, 'lyrics-search');
  await _tap(tester, 'lyrics-consent-confirm');
}

void main() {
  testWidgets('opening, editing, cancelling and Back never send a request', (
    tester,
  ) async {
    final platform = _Platform();
    await _mount(tester, platform);
    expect(platform.requests, isEmpty);
    await _tap(tester, 'lyrics-search');
    await tester.enterText(
      _key('lyrics-query-title'),
      'Edited fictional title',
    );
    await tester.enterText(
      _key('lyrics-query-artist'),
      'Edited fictional artist',
    );
    await tester.enterText(_key('lyrics-query-album'), '');
    await tester.pump();
    expect(platform.requests, isEmpty);
    await _tap(tester, 'lyrics-consent-cancel');
    expect(platform.requests, isEmpty);
    await _tap(tester, 'lyrics-search');
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(_key('lyrics-consent-dialog'), findsNothing);
    expect(platform.requests, isEmpty);
    expect(platform.writes, isEmpty);
  });

  testWidgets('each search needs consent and sends only edited metadata once', (
    tester,
  ) async {
    final platform = _Platform();
    await _mount(tester, platform);
    await _tap(tester, 'lyrics-search');
    await tester.enterText(_key('lyrics-query-title'), '  New test song  ');
    await tester.enterText(_key('lyrics-query-artist'), 'New test singer');
    await tester.enterText(_key('lyrics-query-album'), '');
    await _tap(tester, 'lyrics-consent-confirm');
    expect(platform.requests, hasLength(1));
    expect(platform.requests.single.host, 'lrclib.net');
    expect(platform.requests.single.queryParameters, {
      'track_name': 'New test song',
      'artist_name': 'New test singer',
    });
    expect(platform.writes, isEmpty);
    await _tap(tester, 'lyrics-search');
    expect(platform.requests, hasLength(1));
    await _tap(tester, 'lyrics-consent-cancel');
    expect(platform.requests, hasLength(1));
  });

  testWidgets(
    'results never auto-save; choosing shows active lyrics and tap seeks',
    (tester) async {
      final platform = _Platform();
      Duration? sought;
      final controller = await _mount(
        tester,
        platform,
        position: const Duration(seconds: 2),
        onSeek: (value) => sought = value,
      );
      await _consentedSearch(tester);
      expect(platform.writes, isEmpty);
      expect(controller.document, isNull);
      expect(_key('lyrics-candidate-701'), findsOneWidget);
      expect(find.textContaining('时长与当前歌曲相差超过 2 秒'), findsOneWidget);
      await _tap(tester, 'lyrics-candidate-701');
      expect(platform.writes, hasLength(1));
      expect(controller.document?.isSynced, isTrue);
      expect(_key('lyrics-candidates'), findsNothing);
      final first = tester.widget<TextButton>(_key('lyrics-line-0'));
      expect((first.child! as Text).style?.fontWeight, FontWeight.w700);
      await _tap(tester, 'lyrics-line-1');
      expect(sought, const Duration(seconds: 5));
      expect(platform.requests, hasLength(1));
    },
  );

  testWidgets(
    'plain imported lyrics and instrumental selection render without timed lines',
    (tester) async {
      final platform = _Platform()
        ..imported = 'Fictional unmetered clouds\nA folded test horizon';
      final controller = await _mount(tester, platform);
      await _tap(tester, 'lyrics-import');
      expect(_key('lyrics-plain'), findsOneWidget);
      expect(_key('lyrics-line-0'), findsNothing);
      expect(platform.requests, isEmpty);
      platform.response = LyricsHttpResponse(
        200,
        jsonEncode([
          {
            'id': 702,
            'trackName': 'Silent test prism',
            'artistName': 'Test artist',
            'duration': 90,
            'instrumental': true,
          },
        ]),
      );
      await _consentedSearch(tester);
      // Existing imported lyrics survive searching until the user chooses.
      expect(_key('lyrics-plain'), findsOneWidget);
      await _tap(tester, 'lyrics-candidate-702');
      expect(controller.document?.instrumental, isTrue);
      expect(find.text('纯音乐 · 无歌词'), findsOneWidget);
      expect(_key('lyrics-plain'), findsNothing);
      expect(_key('lyrics-line-0'), findsNothing);
    },
  );

  testWidgets(
    'consent for a previous selection is discarded, including changed source',
    (tester) async {
      final platform = _Platform();
      final controller = await _mount(tester, platform);
      await _tap(tester, 'lyrics-search');
      controller.selectTrack(_track.copyWith(title: 'Different test song'));
      await tester.pump();
      await _tap(tester, 'lyrics-consent-confirm');
      expect(platform.requests, isEmpty);
      await _tap(tester, 'lyrics-search');
      controller.selectTrack(controller.track, source: 'other-folder');
      await tester.pump();
      await _tap(tester, 'lyrics-consent-confirm');
      expect(platform.requests, isEmpty);
    },
  );

  testWidgets(
    'cancelled in-flight response cannot show candidates or overwrite lyrics',
    (tester) async {
      final platform = _Platform()..pending = Completer<LyricsHttpResponse>();
      final controller = await _mount(tester, platform);
      await controller.importText('The test garden keeps its own clock');
      await tester.pumpAndSettle();
      await _tap(tester, 'lyrics-search');
      await tester.ensureVisible(_key('lyrics-consent-confirm'));
      await tester.tap(_key('lyrics-consent-confirm'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(platform.requests, hasLength(1));
      expect(controller.busy, isTrue);
      await _tap(tester, 'lyrics-cancel-search');
      platform.pending!.complete(platform.response);
      await tester.pumpAndSettle();
      expect(controller.candidates, isEmpty);
      expect(controller.document?.text, 'The test garden keeps its own clock');
      expect(platform.writes, hasLength(1));
    },
  );

  testWidgets(
    '320px at 1.8 text scale supports consent, results and paste without overflow',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(320, 1000));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final platform = _Platform();
      await _mount(tester, platform, textScale: 1.8);
      expect(tester.takeException(), isNull);
      await _consentedSearch(tester);
      expect(tester.takeException(), isNull);
      await _tap(tester, 'lyrics-candidate-701');
      expect(tester.takeException(), isNull);
      await _tap(tester, 'lyrics-paste');
      await tester.enterText(
        _key('lyrics-paste-input'),
        'A tiny fictional lyric',
      );
      await tester.pump();
      await _tap(tester, 'lyrics-paste-confirm');
      expect(_key('lyrics-plain'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
