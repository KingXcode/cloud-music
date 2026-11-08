// 按需执行的本地视觉检查，测试数据不会包含在正式应用中。
// CLOUD_MUSIC_CAPTURE_DIR=/tmp/cloud-music-qa flutter test test/ui_visual_capture_test.dart
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:cloud_music/models.dart';
import 'package:cloud_music/lyrics/lyrics_controller.dart';

import 'lyrics_test.dart' show FakeLyricsPlatform;

import 'package:cloud_music/ui/music_app.dart';

import 'ui_music_app_test.dart' show FakeController;

void main() {
  final destination = Platform.environment['CLOUD_MUSIC_CAPTURE_DIR'];
  testWidgets('Capture test-only library and player at real device sizes', (
    tester,
  ) async {
    await tester.runAsync(() async {
      for (final family in ['Roboto', 'PingFang SC']) {
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
      await (FontLoader('MaterialIcons')..addFont(
            File(
              '${Platform.environment['FLUTTER_ROOT']}/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
            ).readAsBytes().then((b) => ByteData.sublistView(b)),
          ))
          .load();
    });
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final boundary = GlobalKey();
    final c = FakeController(
      const LibrarySnapshot(),
      lyrics: LyricsController(platform: FakeLyricsPlatform()),
    );
    Future<void> capture(String name) async {
      await tester.pump(const Duration(seconds: 1));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      (boundary.currentContext!.findRenderObject() as RenderRepaintBoundary)
          .markNeedsPaint();
      await tester.pump();
      await tester.runAsync(() async {
        final image =
            await (boundary.currentContext!.findRenderObject()
                    as RenderRepaintBoundary)
                .toImage(pixelRatio: 1.5);
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
        child: Stack(
          textDirection: TextDirection.ltr,
          children: [
            MusicApp(controller: c),
            Positioned(
              right: 4,
              top: 2,
              child: IgnorePointer(
                child: Container(
                  color: const Color(0xEE4B361C),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 5,
                    vertical: 2,
                  ),
                  child: const Text(
                    'VISUAL QA · TEST FIXTURE',
                    textDirection: TextDirection.ltr,
                    style: TextStyle(
                      fontFamily: 'Roboto',
                      fontSize: 8,
                      color: Colors.white,
                      decoration: TextDecoration.none,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
    await capture('phone-empty');
    c.snapshot = const LibrarySnapshot(
      folderName: '测试音乐文件夹',
      tracks: [
        Track(
          id: 'a',
          title: '山间的风',
          artist: '林间',
          album: '沿途的风景',
          availability: TrackAvailability.ready,
          duration: Duration(minutes: 4, seconds: 26),
        ),
        Track(
          id: 'b',
          title: '城市夜航',
          artist: '夜色',
          availability: TrackAvailability.cloud,
          duration: Duration(minutes: 3, seconds: 42),
        ),
        Track(
          id: 'c',
          title: '远方的来信',
          artist: '留声机',
          availability: TrackAvailability.offline,
        ),
        Track(
          id: 'd',
          title: '旧唱片',
          artist: '佚名',
          availability: TrackAvailability.missing,
        ),
        Track(
          id: 'e',
          title: '未支持的音频格式',
          artist: '测试文件',
          availability: TrackAvailability.unsupported,
        ),
      ],
      currentTrackId: 'a',
      isPlaying: true,
      position: Duration(minutes: 1, seconds: 12),
      duration: Duration(minutes: 4, seconds: 26),
      volume: .65,
    );
    c.lyrics.selectTrack(c.snapshot.currentTrack);
    await c.lyrics.importText(
      '[00:01]测试歌词 · 只用于界面验证\n[00:30]风穿过安静的窗台\n[01:12]把这一刻留给音乐\n[01:25]下一段旋律正在路上',
    );
    c.notifyListeners();
    await capture('phone-library');
    await tester.tap(find.text('山间的风').last);
    await capture('phone-player');
    await tester.tap(find.byTooltip('查看歌词'));
    await tester.pumpAndSettle();
    await capture('phone-lyrics');
    await tester.tap(find.byTooltip('待播清单'));
    await capture('phone-queue');
    await tester.tap(find.byTooltip('返回资料库'));
    await tester.pumpAndSettle();
    tester.view.physicalSize = const Size(1440, 900);
    await capture('desktop-library');
    await tester.tap(find.byKey(const Key('open-player')));
    await capture('desktop-player');
    await tester.tap(find.byTooltip('返回资料库'));
    await tester.pumpAndSettle();
    tester.view.physicalSize = const Size(844, 390);
    await capture('head-unit-library');
    await tester.tap(find.text('山间的风').last);
    await capture('head-unit-player');
  }, skip: destination == null);
}
