// Optional local visual QA. Update metadata and download traffic are fakes.
// CLOUD_MUSIC_CAPTURE_DIR=/tmp/cloud-music-update-qa flutter test test/update_visual_capture_test.dart
import 'dart:io';
import 'dart:ui' as ui;

import 'package:cloud_music/lyrics/lyrics_controller.dart';
import 'package:cloud_music/models.dart';
import 'package:cloud_music/ui/music_app.dart';
import 'package:cloud_music/updates/update_backend.dart';
import 'package:cloud_music/updates/update_controller.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'lyrics_test.dart' show FakeLyricsPlatform;
import 'ui_music_app_test.dart' show FakeController;
import 'update_controller_test.dart'
    show ControlledUpdateBackend, updateTestRelease;

void main() {
  final destination = Platform.environment['CLOUD_MUSIC_CAPTURE_DIR'];
  for (final configuration in [
    (
      name: 'phone',
      size: const Size(390, 844),
      scale: 1.0,
      platform: 'android',
    ),
    (
      name: 'narrow-large-text',
      size: const Size(320, 640),
      scale: 2.0,
      platform: 'android',
    ),
    (name: 'mac', size: const Size(1280, 800), scale: 1.0, platform: 'macos'),
  ]) {
    testWidgets('Capture updates ${configuration.name}', (tester) async {
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
                    .then(ByteData.sublistView),
              ))
              .load();
        }
        await (FontLoader('packages/cupertino_icons/CupertinoIcons')..addFont(
              File(
                '${Platform.environment['PUB_CACHE']}/hosted/pub.dev/cupertino_icons-1.0.9/assets/CupertinoIcons.ttf',
              ).readAsBytes().then(ByteData.sublistView),
            ))
            .load();
      });
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = configuration.size;
      tester.platformDispatcher.textScaleFactorTestValue = configuration.scale;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      final fixture = updateTestRelease();
      final backend = ControlledUpdateBackend(platform: configuration.platform)
        ..next = UpdateRelease(
          version: fixture.version,
          build: fixture.build,
          notes: fixture.notes,
          releasePage: fixture.releasePage,
          asset: UpdateAsset(
            name: fixture.asset!.name,
            url: fixture.asset!.url,
            size: 32 * 1024 * 1024,
            sha256: fixture.asset!.sha256,
          ),
        );
      final updates = UpdateController(backend);
      final music = FakeController(
        const LibrarySnapshot(),
        lyrics: LyricsController(platform: FakeLyricsPlatform()),
      );
      await updates.check();
      final transfer = updates.download();
      if (configuration.platform != 'macos') {
        backend.progressCallbacks.single(12 * 1024 * 1024, 32 * 1024 * 1024);
      }
      final boundary = GlobalKey();
      await tester.pumpWidget(
        RepaintBoundary(
          key: boundary,
          child: Stack(
            textDirection: TextDirection.ltr,
            children: [
              MusicApp(controller: music, updates: updates),
              Positioned(
                top: 2,
                right: 4,
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
                        color: CupertinoColors.white,
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
      await tester.pumpAndSettle();
      Future<void> capture(String state) async {
        expect(tester.takeException(), isNull);
        final render =
            boundary.currentContext!.findRenderObject()
                as RenderRepaintBoundary;
        render.markNeedsPaint();
        await tester.pump();
        await tester.runAsync(() async {
          final image = await render.toImage(pixelRatio: 1.5);
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          await Directory(destination!).create(recursive: true);
          await File('$destination/update-${configuration.name}-$state.png')
              .writeAsBytes(bytes!.buffer.asUint8List());
          image.dispose();
        });
      }

      await capture('banner');
      await tester.tap(find.byKey(const Key('update-banner')));
      await tester.pumpAndSettle();
      await capture('download-top');
      if (configuration.platform == 'macos') {
        await transfer;
        await capture('browser-download');
      } else {
        await tester.ensureVisible(find.byKey(const Key('update-progress')));
        await tester.pumpAndSettle();
        await capture('download-progress');
        backend.downloads.single.complete();
        await transfer;
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.byKey(const Key('install-update')));
        await tester.pumpAndSettle();
        await capture('ready');
        await tester.tap(find.byKey(const Key('install-update')));
        await tester.pumpAndSettle();
        await capture('confirmation');
        await tester.tap(find.text('稍后'));
        await tester.pumpAndSettle();
        expect(backend.installCalls, 0);
      }
      await tester.pumpWidget(const SizedBox());
      music.dispose();
      updates.dispose();
      await tester.pump();
    }, skip: destination == null);
  }
}
