// Opt-in UI fixtures; never bundled with the application.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:cloud_music/models.dart';
import 'package:cloud_music/ui/music_app.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'ui_music_app_test.dart' show FakeController;

void main() {
  final destination = Platform.environment['CLOUD_MUSIC_CAPTURE_DIR'];
  testWidgets('Capture song availability, counts and sorting', (tester) async {
    await tester.runAsync(() async {
      final font = [
        '/System/Library/Fonts/STHeiti Light.ttc',
        '/usr/share/fonts/opentype/noto/NotoSansCJK-Regular.ttc',
      ].map(File.new).firstWhere((file) => file.existsSync());
      for (final family in [
        'Roboto',
        'PingFang SC',
        '.SF Pro Text',
        '.SF Pro Display',
        'CupertinoSystemText',
        'CupertinoSystemDisplay',
      ]) {
        await (FontLoader(
          family,
        )..addFont(font.readAsBytes().then(ByteData.sublistView))).load();
      }
      final pubCache =
          Platform.environment['PUB_CACHE'] ??
          '${Platform.environment['HOME']}/.pub-cache';
      await (FontLoader('packages/cupertino_icons/CupertinoIcons')..addFont(
            File(
              '$pubCache/hosted/pub.dev/cupertino_icons-1.0.9/assets/CupertinoIcons.ttf',
            ).readAsBytes().then(ByteData.sublistView),
          ))
          .load();
    });
    final controller = FakeController(
      const LibrarySnapshot(
        sourceKind: 'apple',
        folderName: '音乐 · 视觉测试',
        tracks: [
          Track(
            id: 'a',
            title: '山间的风',
            artist: '林间',
            duration: Duration(minutes: 3),
            availability: TrackAvailability.ready,
          ),
          Track(
            id: 'b',
            title: '城市夜航',
            artist: '夜色',
            duration: Duration(minutes: 4, seconds: 12),
            availability: TrackAvailability.cloud,
          ),
          Track(
            id: 'c',
            title: '远方的来信',
            artist: '留声机',
            duration: Duration(minutes: 3, seconds: 42),
            availability: TrackAvailability.offline,
          ),
          Track(
            id: 'd',
            title: '旧唱片',
            artist: '佚名',
            duration: Duration(minutes: 2, seconds: 54),
            availability: TrackAvailability.missing,
          ),
        ],
      ),
    )..playCounts.addAll({'a': 12, 'b': 3, 'c': 1});
    addTearDown(controller.dispose);
    addTearDown(controller.lyrics.dispose);
    addTearDown(controller.playbackStats.dispose);
    final boundary = GlobalKey();
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
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

    tester.view.physicalSize = const Size(1280, 900);
    await tester.pumpWidget(
      RepaintBoundary(
        key: boundary,
        child: MusicApp(controller: controller),
      ),
    );
    await capture('sort-desktop-library');
    tester.view.physicalSize = const Size(390, 844);
    await capture('sort-phone-library');
    await tester.tap(find.byKey(const Key('library-sort')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('sort-playCount')));
    await capture('sort-phone-settings');
    tester.view.physicalSize = const Size(320, 640);
    tester.platformDispatcher.textScaleFactorTestValue = 1.8;
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const Key('apply-library-sort')));
    await capture('sort-compact-large-text');
  }, skip: destination == null);
}
