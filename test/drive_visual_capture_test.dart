import 'package:cloud_music/library_filter/library_filter.dart';

import 'library_filter_test.dart' show MemoryFilterStore;

// Optional local visual QA. All authorization and HTTP responses are fakes.
// CLOUD_MUSIC_CAPTURE_DIR=/tmp/cloud-music-drive-qa flutter test test/drive_visual_capture_test.dart
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/cupertino.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:cloud_music/drive/drive_gateway.dart';
import 'package:cloud_music/gateway/source_music_gateway.dart';
import 'package:cloud_music/lyrics/lyrics_controller.dart';
import 'package:cloud_music/music_controller.dart';
import 'package:cloud_music/ui/music_app.dart';

import 'drive_gateway_test.dart'
    show FakeDrivePlatform, FakeLocalGateway, apiClient;
import 'lyrics_test.dart' show FakeLyricsPlatform;

void main() {
  final destination = Platform.environment['CLOUD_MUSIC_CAPTURE_DIR'];
  for (final entry in {
    'phone': const Size(390, 844),
    'wide': const Size(1280, 800),
    'landscape': const Size(844, 390),
  }.entries) {
    for (final connected in [false, true]) {
      testWidgets('Capture Drive ${entry.key}, connected=$connected', (
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

        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = entry.value;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final platform = FakeDrivePlatform()..enabled = connected;
        final drive = DriveGateway(platform: platform, client: apiClient());
        final c = MusicController(
          libraryFilter: LibraryFilter(store: MemoryFilterStore()),
          gateway: SourceMusicGateway(local: FakeLocalGateway(), drive: drive),
          lyrics: LyricsController(platform: FakeLyricsPlatform()),
        );
        await c.initialize();
        if (connected) await drive.connect();
        final boundary = GlobalKey();
        await tester.pumpWidget(
          RepaintBoundary(
            key: boundary,
            child: Stack(
              textDirection: TextDirection.ltr,
              children: [
                MusicApp(controller: c),
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
        await tester.tap(find.byKey(const Key('library-options')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('music-sources')));
        await tester.pumpAndSettle();
        await tester.scrollUntilVisible(
          find.text('Google Drive'),
          120,
          scrollable: find
              .descendant(
                of: find.byKey(const Key('music-sources-scroll')),
                matching: find.byType(Scrollable),
              )
              .first,
        );
        await tester.pumpAndSettle();
        await tester.ensureVisible(
          find.ancestor(
            of: find.text('Google Drive'),
            matching: find.byType(CupertinoListTile),
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text('Google Drive'));
        await tester.pumpAndSettle();
        Future<void> capture(String suffix) async {
          expect(tester.takeException(), isNull);
          final render =
              boundary.currentContext!.findRenderObject()
                  as RenderRepaintBoundary;
          render.markNeedsPaint();
          await tester.pump();
          await tester.runAsync(() async {
            final image = await render.toImage(pixelRatio: 1.5);
            final bytes = await image.toByteData(
              format: ui.ImageByteFormat.png,
            );
            await Directory(destination!).create(recursive: true);
            await File(
              '$destination/${entry.key}-${connected ? 'connected' : 'unconfigured'}-$suffix.png',
            ).writeAsBytes(bytes!.buffer.asUint8List());
            image.dispose();
          });
        }

        await capture('top');
        final scrollable = find
            .descendant(
              of: find.byKey(const Key('music-sources-scroll')),
              matching: find.byType(Scrollable),
            )
            .first;
        final target = connected
            ? find.text('Artist - Two.mp3')
            : find.byKey(const Key('drive-connect'));
        await tester.scrollUntilVisible(target, 160, scrollable: scrollable);
        await tester.pumpAndSettle();
        await capture('bottom');
        if (!connected) {
          expect(
            tester
                .widget<CupertinoButton>(
                  find.descendant(
                    of: find.byKey(const Key('drive-connect')),
                    matching: find.byType(CupertinoButton),
                  ),
                )
                .onPressed,
            isNull,
          );
          expect(platform.interactiveCount, 0);
        }
        await tester.tap(find.byTooltip('关闭音乐来源'));
        await tester.pumpAndSettle();
        expect(find.byTooltip('关闭音乐来源'), findsNothing);
        expect(tester.takeException(), isNull);
        await tester.tap(find.byKey(const Key('library-options')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('music-sources')));
        await tester.pumpAndSettle();
        await tester.binding.handlePopRoute();
        await tester.pumpAndSettle();
        expect(find.byTooltip('关闭音乐来源'), findsNothing);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
        c.dispose();
        await tester.pump();
      }, skip: destination == null);
    }
  }
}
