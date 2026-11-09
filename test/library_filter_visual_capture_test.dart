// Opt-in rendered visual fixtures; never bundled with the application.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:cloud_music/library_filter/library_filter.dart';
import 'package:cloud_music/lyrics/lyrics_controller.dart';
import 'package:cloud_music/models.dart';
import 'package:cloud_music/music_controller.dart';
import 'package:cloud_music/ui/music_app.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'controller_test.dart' show FakeGateway;
import 'library_filter_test.dart' show MemoryFilterStore;
import 'lyrics_test.dart' show FakeLyricsPlatform;

void main() {
  final destination = Platform.environment['CLOUD_MUSIC_CAPTURE_DIR'];
  testWidgets('Capture short audio filter on phone, landscape and desktop', (
    tester,
  ) async {
    await tester.runAsync(() async {
      for (final family in [
        'Roboto',
        'PingFang SC',
        '.SF Pro Text',
        '.SF Pro Display',
        'CupertinoSystemText',
        'CupertinoSystemDisplay',
      ]) {
        await (FontLoader(family)..addFont(
              File('/usr/share/fonts/opentype/noto/NotoSansCJK-Regular.ttc')
                  .readAsBytes()
                  .then((b) => ByteData.sublistView(b)),
            ))
            .load();
      }
      await (FontLoader('packages/cupertino_icons/CupertinoIcons')..addFont(
            File(
              '${Platform.environment['PUB_CACHE']}/hosted/pub.dev/cupertino_icons-1.0.9/assets/CupertinoIcons.ttf',
            ).readAsBytes().then((b) => ByteData.sublistView(b)),
          ))
          .load();
    });
    final c = MusicController(
      gateway: FakeGateway()
        ..initial = const LibrarySnapshot(
          folderName: '我的音乐 · 视觉测试',
          sourceKind: 'apple',
          tracks: [
            Track(
              id: 'clip',
              title: '提示音（12 秒）',
              duration: Duration(seconds: 12),
            ),
            Track(
              id: 'edge',
              title: '清晨序曲',
              artist: '林间',
              album: '沿途',
              duration: Duration(seconds: 30),
              availability: TrackAvailability.ready,
            ),
            Track(
              id: 'long',
              title: '城市夜航',
              artist: '夜色',
              album: '沿途',
              duration: Duration(minutes: 4),
              availability: TrackAvailability.ready,
            ),
            Track(
              id: 'cloud',
              title: '远方的来信',
              artist: '留声机',
              availability: TrackAvailability.cloud,
            ),
          ],
        ),
      libraryFilter: LibraryFilter(store: MemoryFilterStore()),
      lyrics: LyricsController(platform: FakeLyricsPlatform()),
    );
    await c.initialize();
    addTearDown(c.dispose);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    final boundary = GlobalKey();
    Future<void> capture(String name) async {
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      final render =
          boundary.currentContext!.findRenderObject() as RenderRepaintBoundary;
      render.markNeedsPaint();
      await tester.pump();
      await tester.runAsync(() async {
        final image = await render.toImage(pixelRatio: 1.5);
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        await Directory(destination!).create(recursive: true);
        await File('$destination/$name.png')
            .writeAsBytes(bytes!.buffer.asUint8List());
        image.dispose();
      });
    }

    tester.view.physicalSize = const Size(390, 844);
    await tester.pumpWidget(
      RepaintBoundary(
        key: boundary,
        child: MusicApp(controller: c),
      ),
    );
    await capture('filter-phone-library');
    await tester.tap(find.byKey(const Key('library-options')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('library-filter')));
    await capture('filter-phone-settings');
    await tester.tap(find.text('取消'));
    tester.view.physicalSize = const Size(1280, 900);
    await capture('filter-desktop-library');
    await tester.tap(find.byKey(const Key('library-options')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('library-filter')));
    tester.view.physicalSize = const Size(844, 390);
    tester.platformDispatcher.textScaleFactorTestValue = 1.8;
    await capture('filter-landscape-large-settings');
  }, skip: destination == null);
}
