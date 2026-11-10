import 'package:cloud_music/lyrics/lyrics_controller.dart';
import 'package:cloud_music/library_filter/filter_store.dart';
import 'package:cloud_music/library_filter/library_filter.dart';
import 'package:cloud_music/models.dart';
import 'package:cloud_music/music_controller.dart';
import 'package:cloud_music/ui/lyrics_panel.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';

import 'controller_test.dart' show FakeGateway;
import 'lyrics_test.dart' show FakeLyricsPlatform;

class _Store implements FilterStore {
  @override
  Future<String?> read() async => null;
  @override
  Future<void> write(String value) async {}
}

void main() {
  for (final source in ['web', 'apple', 'android', 'googleDrive']) {
    testWidgets('$source clock advances, seeks and resumes lyric following', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      LibrarySnapshot snapshot(int milliseconds, {bool playing = true}) =>
          LibrarySnapshot.fromMap({
            'sourceKind': source,
            'sourceIdentity': 'test-source',
            'currentTrackId': 'fictional',
            'isPlaying': playing,
            'positionMs': milliseconds,
            'durationMs': 90000,
            'tracks': [
              {
                'id': 'fictional',
                'title': 'Fictional Clock',
                'artist': 'Test Ensemble',
                'durationMs': 90000,
              },
            ],
          });
      final platform = FakeLyricsPlatform();
      final lyrics = LyricsController(platform: platform);
      final gateway = FakeGateway()..initial = snapshot(0);
      final music = MusicController(
        gateway: gateway,
        lyrics: lyrics,
        libraryFilter: LibraryFilter(store: _Store()),
      );
      addTearDown(music.dispose);
      await music.initialize();
      await lyrics.initialize();
      await lyrics.importText(
        List.generate(25, (i) {
          final time = i * 3;
          return '[${(time ~/ 60).toString().padLeft(2, '0')}:'
              '${(time % 60).toString().padLeft(2, '0')}.50]'
              '原创测试纸船 $i';
        }).join('\n'),
      );
      await tester.pumpWidget(
        CupertinoApp(
          home: CupertinoPageScaffold(
            child: AnimatedBuilder(
              animation: music,
              builder: (context, _) => LyricsPanel(
                controller: lyrics,
                position: music.snapshot.position,
                immersive: true,
                onSeek: music.seek,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final scroll = find.byKey(const Key('lyrics-synced-scroll'));
      final follow = find.byKey(const Key('lyrics-follow'));
      Finder line(int index) => find.byKey(Key('lyrics-line-$index'));
      void expectActive(int index, {bool centered = true}) {
        final text = tester.widget<CupertinoButton>(line(index)).child as Text;
        expect(text.style!.color, CupertinoColors.white);
        if (centered) {
          final viewport = tester.getRect(scroll);
          final row = tester.getRect(line(index));
          expect(
            (row.top - viewport.top) / (viewport.height - row.height),
            closeTo(.45, .04),
          );
        }
      }

      // Advancing the audio event must both highlight AND move the viewport.
      gateway.events.add(snapshot(15500));
      await tester.pumpAndSettle();
      expectActive(5);
      gateway.events.add(snapshot(54500));
      await tester.pumpAndSettle();
      expectActive(18);
      gateway.events.add(snapshot(9500, playing: false));
      await tester.pumpAndSettle();
      expectActive(3);
      await tester.pump(const Duration(seconds: 5));
      expectActive(3); // A paused clock must not invent progress.

      await tester.drag(scroll, const Offset(0, -100));
      await tester.pumpAndSettle();
      expect(follow, findsOneWidget);
      final before = tester.getRect(line(3)).top;
      gateway.events.add(snapshot(30500));
      await tester.pumpAndSettle();
      expectActive(10, centered: false);
      expect(tester.getRect(line(3)).top, closeTo(before, .1));
      await tester.tap(follow);
      await tester.pumpAndSettle();
      expectActive(10);
      expect(follow, findsNothing);
      await tester.tap(line(10));
      await tester.pumpAndSettle();
      expect(gateway.calls.last.$1, 'seek');
      expect(gateway.calls.last.$2, {'positionMs': 30500});
      expect(platform.queries, isEmpty);
      expect(tester.takeException(), isNull);
    });
  }
}
