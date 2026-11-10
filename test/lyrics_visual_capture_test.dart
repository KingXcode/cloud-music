// Offline visual QA with invented lyrics. Does not contact LRCLIB.
// CLOUD_MUSIC_CAPTURE_DIR=/tmp/lyrics-qa flutter test test/lyrics_visual_capture_test.dart
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:cloud_music/lyrics/lyrics_controller.dart';
import 'package:cloud_music/lyrics/lyrics_platform.dart';
import 'package:cloud_music/models.dart';
import 'package:cloud_music/ui/lyrics_panel.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

class _VisualPlatform implements LyricsPlatform {
  @override
  Future<LyricsHttpResponse> get(Uri uri) async => LyricsHttpResponse(
    200,
    jsonEncode([
      {
        'id': 9101,
        'trackName': '紙船觀測站',
        'artistName': '虛構樂隊',
        'albumName': '測試星圖',
        'duration': 189,
        'syncedLyrics':
            '[00:01.50]紙船數著遠方的星\n'
            '[00:08.00]藍色三角停在窗邊\n'
            '[00:16.50]我們用紙畫一座燈塔\n'
            '[00:24.00]讓虛構的風穿過花園',
      },
      {
        'id': 9102,
        'trackName': '紙船觀測站 (Live)',
        'artistName': '虛構樂隊',
        'albumName': '紙上音樂會',
        'duration': 221,
        'plainLyrics': '紙船數著遠方的星\n藍色三角停在窗邊',
      },
    ]),
  );
  @override
  Future<String?> readCache() async => null;
  @override
  Future<void> writeCache(String value) async {}
  @override
  Future<String?> importFile() async => null;
  @override
  void dispose() {}
}

void main() {
  final destination = Platform.environment['CLOUD_MUSIC_CAPTURE_DIR'];
  testWidgets('capture lyric search, results, preview, and accessible layout', (
    tester,
  ) async {
    await tester.runAsync(() async {
      for (final family in [
        'Roboto',
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
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final boundary = GlobalKey();
    final controller = LyricsController(platform: _VisualPlatform());
    addTearDown(controller.dispose);
    await controller.initialize();
    controller.selectTrack(
      const Track(
        id: 'fictional-qa',
        title: '纸船观测站',
        artist: '虚构乐队',
        album: '测试星图',
        duration: Duration(seconds: 189),
      ),
    );
    Future<void> mount(Size size, double scale, {bool dark = false}) async {
      await tester.binding.setSurfaceSize(size);
      await tester.pumpWidget(
        RepaintBoundary(
          key: boundary,
          child: CupertinoApp(
            debugShowCheckedModeBanner: false,
            theme: CupertinoThemeData(
              primaryColor: const Color(0xFFD63C60),
              brightness: dark ? Brightness.dark : Brightness.light,
            ),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: TextScaler.linear(scale)),
              child: child!,
            ),
            home: CupertinoPageScaffold(
              backgroundColor: const Color(0xFF352932),
              child: SafeArea(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: LyricsPanel(
                    controller: controller,
                    position: Duration.zero,
                    immersive: true,
                    onSeek: (_) {},
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    Future<void> tap(String key) async {
      final finder = find.byKey(Key(key));
      await tester.ensureVisible(finder);
      await tester.tap(finder);
      await tester.pumpAndSettle();
    }

    Future<void> capture(String name) async {
      expect(tester.takeException(), isNull);
      (boundary.currentContext!.findRenderObject() as RenderRepaintBoundary)
          .markNeedsPaint();
      await tester.pump();
      await tester.runAsync(() async {
        final image =
            await (boundary.currentContext!.findRenderObject()
                    as RenderRepaintBoundary)
                .toImage(pixelRatio: 1.5);
        final data = await image.toByteData(format: ui.ImageByteFormat.png);
        await Directory(destination!).create(recursive: true);
        await File('$destination/$name.png')
            .writeAsBytes(data!.buffer.asUint8List());
        image.dispose();
      });
    }

    await mount(const Size(390, 844), 1);
    await tap('lyrics-options');
    await capture('lyrics-management-mobile');
    await tap('lyrics-search');
    await capture('lyrics-search-mobile');
    await tap('lyrics-consent-confirm');
    await capture('lyrics-results-mobile');
    await tap('lyrics-candidate-9101');
    await capture('lyrics-preview-mobile');
    await tap('lyrics-preview-cancel');
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    await mount(const Size(390, 844), 1, dark: true);
    await tap('lyrics-options');
    await tap('lyrics-search');
    await capture('lyrics-search-dark');
    await tap('lyrics-consent-cancel');
    await tester.ensureVisible(find.byKey(const Key('lyrics-candidate-9101')));
    await capture('lyrics-results-dark');
    await tap('lyrics-candidate-9101');
    await capture('lyrics-preview-dark');
    await tap('lyrics-preview-cancel');
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    await mount(const Size(1024, 768), 1);
    await tap('lyrics-options');
    await capture('lyrics-results-desktop');
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    await mount(const Size(320, 1000), 1.8);
    await tap('lyrics-options');
    await tap('lyrics-candidate-9101');
    await capture('lyrics-preview-large-text');
    await tap('lyrics-preview-save');
    expect(tester.takeException(), isNull);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    await controller.importText(
      List.generate(
        12,
        (i) => '[00:${i.toString().padLeft(2, '0')}]纸船载着想象前往远方 $i',
      ).join('\n'),
    );
    await mount(const Size(390, 844), 1);
    await capture('lyrics-font-default-mobile');
    await tap('lyrics-font-size');
    await capture('lyrics-font-settings-mobile');
    await controller.setFontSize(14);
    await tester.pumpAndSettle();
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    await capture('lyrics-font-small-mobile');
    await controller.setFontSize(36);
    await mount(const Size(320, 700), 1.8);
    await tap('lyrics-font-size');
    await capture('lyrics-font-settings-accessibility');
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    await mount(const Size(844, 390), 1);
    await capture('lyrics-font-landscape');
    await controller.setFontSize(22);
    await mount(const Size(1440, 900), 1);
    await capture('lyrics-font-desktop');
    await controller.importText('虚构纸船停在窗边\n让想象的微风吹向远方\n每一行测试都只属于这里');
    await mount(const Size(390, 844), 1);
    await capture('lyrics-font-plain-mobile');
  }, skip: destination == null);
}
