import 'package:cloud_music/models.dart';
import 'package:cloud_music/ui/music_app.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';

import 'ui_music_app_test.dart' show FakeController;

void main() {
  test('Bridge preserves honest web availability states', () {
    for (final value in ['unloaded', 'accessRequired', 'loading', 'unknown']) {
      final track = Track.fromMap({
        'id': 'a',
        'title': 'Song',
        'status': value,
      });
      expect(track.availability.name, value);
    }
  });

  testWidgets('Partial library remains visible and playable during scanning', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final controller = FakeController(
      const LibrarySnapshot(
        sourceKind: 'web',
        folderName: 'Music',
        isScanning: true,
        tracks: [
          Track(
            id: 'a',
            title: 'First song',
            availability: TrackAvailability.unloaded,
          ),
          Track(
            id: 'b',
            title: 'Cached song',
            availability: TrackAvailability.accessRequired,
          ),
        ],
      ),
    );
    addTearDown(controller.dispose);
    addTearDown(controller.lyrics.dispose);
    await tester.pumpWidget(MusicApp(controller: controller));
    await tester.pump();
    expect(find.text('正在列出歌曲 · 已显示 2 首'), findsOneWidget);
    expect(find.text('未读取 · 播放时加载'), findsNothing);
    expect(find.text('需重新授权或选择'), findsNothing);
    expect(
      tester
          .widget<Opacity>(find.byKey(const Key('track-availability-a')))
          .opacity,
      1,
    );
    expect(
      tester
          .widget<Opacity>(find.byKey(const Key('track-availability-b')))
          .opacity,
      .45,
    );
    expect(find.byKey(const Key('source-loading-help')), findsNothing);
    expect(find.text('未下载 · 播放时下载'), findsNothing);
    await tester.tap(find.text('First song'));
    expect(controller.playedId, 'a');
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'Empty scanning source is not presented as an empty music folder',
    (tester) async {
      final controller = FakeController(
        const LibrarySnapshot(
          sourceKind: 'apple',
          folderName: 'iCloud Music',
          isScanning: true,
        ),
      );
      addTearDown(controller.dispose);
      addTearDown(controller.lyrics.dispose);
      await tester.pumpWidget(MusicApp(controller: controller));
      await tester.pump();
      expect(find.text('正在读取目录'), findsOneWidget);
      expect(find.text('这里还没有音乐'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
  for (final size in [const Size(320, 640), const Size(844, 390)]) {
    testWidgets('Web limitation hint fits $size at large text', (tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      tester.platformDispatcher.textScaleFactorTestValue = 1.8;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      final controller = FakeController(
        const LibrarySnapshot(
          sourceKind: 'web',
          selectionMode: 'files',
          folderName: '已选音乐文件',
          tracks: [
            Track(
              id: 'a',
              title: '歌曲',
              availability: TrackAvailability.unloaded,
            ),
          ],
        ),
      );
      addTearDown(controller.dispose);
      addTearDown(controller.lyrics.dispose);
      await tester.pumpWidget(MusicApp(controller: controller));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('library-options')));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(const Key('source-loading-help')));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('网页无法判断 iCloud 下载状态').hitTestable(),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });
  }
}
