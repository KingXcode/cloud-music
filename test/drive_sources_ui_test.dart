import 'package:cloud_music/library_filter/library_filter.dart';

import 'library_filter_test.dart' show MemoryFilterStore;

import 'package:cloud_music/drive/drive_gateway.dart';
import 'package:cloud_music/gateway/source_music_gateway.dart';
import 'package:cloud_music/lyrics/lyrics_controller.dart';
import 'package:cloud_music/music_controller.dart';
import 'package:cloud_music/ui/music_app.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'drive_gateway_test.dart'
    show FakeDrivePlatform, FakeLocalGateway, apiClient;
import 'lyrics_test.dart' show FakeLyricsPlatform;

void main() {
  for (final size in [
    const Size(320, 640),
    const Size(844, 390),
    const Size(1280, 800),
  ]) {
    testWidgets('来源面板在 $size 下可关闭、未配置不冒充可登录', (tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final platform = FakeDrivePlatform()..enabled = false;
      final drive = DriveGateway(platform: platform, client: apiClient());
      final c = MusicController(
        libraryFilter: LibraryFilter(store: MemoryFilterStore()),
        gateway: SourceMusicGateway(local: FakeLocalGateway(), drive: drive),
        lyrics: LyricsController(platform: FakeLyricsPlatform()),
      );
      await c.initialize();
      await tester.pumpWidget(MusicApp(controller: c));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('music-sources')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Google Drive'));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('尚未配置，暂时不能直接登录'),
        160,
        scrollable: find
            .descendant(
              of: find.byKey(const Key('music-sources-scroll')),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      expect(find.text('尚未配置，暂时不能直接登录'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.byKey(const Key('drive-connect')),
        160,
        scrollable: find
            .descendant(
              of: find.byKey(const Key('music-sources-scroll')),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      final button = tester.widget<FilledButton>(
        find.byKey(const Key('drive-connect')),
      );
      expect(button.onPressed, isNull);
      expect(platform.interactiveCount, 0);
      expect(tester.takeException(), isNull);
      await tester.tap(find.byTooltip('关闭音乐来源'));
      await tester.pumpAndSettle();
      expect(find.byTooltip('关闭音乐来源'), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      c.dispose();
      await tester.pump();
    });
  }

  testWidgets('连接后选择文件夹，关闭面板不撤销现有授权', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final platform = FakeDrivePlatform();
    final drive = DriveGateway(platform: platform, client: apiClient());
    final c = MusicController(
      libraryFilter: LibraryFilter(store: MemoryFilterStore()),
      gateway: SourceMusicGateway(local: FakeLocalGateway(), drive: drive),
      lyrics: LyricsController(platform: FakeLyricsPlatform()),
    );
    await c.initialize();
    await tester.pumpWidget(MusicApp(controller: c));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('music-sources')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Google Drive'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const Key('drive-connect')));
    await tester.tap(find.byKey(const Key('drive-connect')));
    await tester.pumpAndSettle();
    expect(drive.connected, isTrue);
    await tester.ensureVisible(find.byKey(const Key('drive-use-folder')));
    await tester.tap(find.byKey(const Key('drive-use-folder')));
    await tester.pumpAndSettle();
    expect(c.usingDrive, isTrue);
    expect(c.snapshot.tracks, hasLength(2));
    expect(find.byTooltip('关闭音乐来源'), findsNothing);
    expect(platform.authorized, isTrue);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    c.dispose();
    await tester.pump();
  });
}
