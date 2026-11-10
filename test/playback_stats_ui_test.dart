import 'dart:async';

import 'package:cloud_music/library_filter/library_filter.dart';
import 'package:cloud_music/lyrics/lyrics_controller.dart';
import 'package:cloud_music/models.dart';
import 'package:cloud_music/music_controller.dart';
import 'package:cloud_music/playback_stats/playback_stats.dart';
import 'package:cloud_music/playback_stats/playback_stats_store.dart';
import 'package:cloud_music/ui/cupertino_settings.dart';
import 'package:cloud_music/ui/music_app.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';

import 'controller_test.dart' show FakeGateway;
import 'cupertino_test_helpers.dart';
import 'library_filter_test.dart' show MemoryFilterStore;
import 'lyrics_test.dart' show FakeLyricsPlatform;
import 'playback_stats_test.dart' show MemoryPlaybackStatsStore;

class FolderStatsStore extends MemoryPlaybackStatsStore
    implements PlaybackStatsFolderStore {
  FolderStatsStore() {
    location = 'local';
  }

  @override
  bool get canPickFolder => true;
  Completer<bool>? selection;
  bool selected = true, failPick = false;
  int picks = 0;

  @override
  Future<bool> pickFolder() async {
    picks++;
    if (failPick) throw StateError('Folder unavailable');
    final picked = selection == null ? selected : await selection!.future;
    if (picked) location = 'folder';
    return picked;
  }
}

Future<MusicController> mountStatsOptions(
  WidgetTester tester,
  PlaybackStatsStore store, {
  String source = 'apple',
  Size size = const Size(390, 844),
  double scale = 1,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  tester.platformDispatcher.textScaleFactorTestValue = scale;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
  final controller = MusicController(
    gateway: FakeGateway()
      ..initial = LibrarySnapshot(sourceKind: source, folderName: 'Music'),
    libraryFilter: LibraryFilter(store: MemoryFilterStore()),
    lyrics: LyricsController(platform: FakeLyricsPlatform()),
    playbackStats: PlaybackStats(store: store),
  );
  addTearDown(controller.dispose);
  await controller.initialize();
  await controller.playbackStats.initialize();
  await tester.pumpWidget(MusicApp(controller: controller));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const Key('library-options')));
  await tester.pumpAndSettle();
  return controller;
}

void main() {
  testWidgets('Personal iCloud folder action fits compact large-text options', (
    tester,
  ) async {
    final store = FolderStatsStore();
    await mountStatsOptions(
      tester,
      store,
      size: const Size(320, 640),
      scale: 1.8,
    );
    final picker = find.byKey(const Key('pick-playback-stats-folder'));
    await tester.ensureVisible(picker);
    await tester.pumpAndSettle();
    await tester.tap(picker);
    await tester.pumpAndSettle();
    expect(find.text('更换统计保存文件夹'), findsOneWidget);
    await tester.ensureVisible(
      find.byKey(const Key('playback-stats-folder-help')),
    );
    await tester.pumpAndSettle();
    expectNoMaterialWidgets();
    expect(tester.takeException(), isNull);
  });
  testWidgets(
    'Personal folder selection updates storage without closing options',
    (tester) async {
      final store = FolderStatsStore()..selection = Completer<bool>();
      final controller = await mountStatsOptions(tester, store);
      expect(find.text('播放统计暂存本机，可选择个人 iCloud Drive 文件夹。'), findsOneWidget);
      expect(find.textContaining('应用 iCloud 容器'), findsNothing);
      final picker = find.byKey(const Key('pick-playback-stats-folder'));
      await tester.ensureVisible(picker);
      await tester.pumpAndSettle();
      await tester.tap(picker);
      await tester.pump();
      expect(store.picks, 1);
      expect(controller.playbackStats.choosingFolder, isTrue);
      expect(tester.widget<SettingsTile>(picker).enabled, isFalse);
      expect(find.text('正在选择保存文件夹…'), findsOneWidget);
      expect(cupertinoPopup, findsOneWidget);
      store.selection!.complete(true);
      await tester.pumpAndSettle();
      expect(controller.playbackStats.choosingFolder, isFalse);
      expect(find.text('播放统计保存在你选择的文件夹。'), findsOneWidget);
      expect(find.text('更换统计保存文件夹'), findsOneWidget);
      expect(cupertinoPopup, findsOneWidget);
      expectNoMaterialWidgets();
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Folder cancellation retains local storage for a Drive music source',
    (tester) async {
      final store = FolderStatsStore()..selected = false;
      await mountStatsOptions(tester, store, source: 'googleDrive');
      final picker = find.byKey(const Key('pick-playback-stats-folder'));
      await tester.ensureVisible(picker);
      await tester.pumpAndSettle();
      await tester.tap(picker);
      await tester.pumpAndSettle();
      expect(store.picks, 1);
      expect(find.text('选择个人 iCloud 文件夹'), findsOneWidget);
      expect(find.text('播放统计暂存本机，可选择个人 iCloud Drive 文件夹。'), findsOneWidget);
      expect(find.byKey(const Key('playback-stats-notice')), findsNothing);
      expect(cupertinoPopup, findsOneWidget);
    },
  );

  testWidgets('Folder selection errors remain visible and allow retry', (
    tester,
  ) async {
    final store = FolderStatsStore()..failPick = true;
    await mountStatsOptions(tester, store);
    final picker = find.byKey(const Key('pick-playback-stats-folder'));
    await tester.ensureVisible(picker);
    await tester.pumpAndSettle();
    await tester.tap(picker);
    await tester.pumpAndSettle();
    expect(find.text('无法连接统计保存文件夹，请重新选择可写入的文件夹。'), findsOneWidget);
    expect(tester.widget<SettingsTile>(picker).enabled, isTrue);
    expect(cupertinoPopup, findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'Browser statistics show their storage without an Apple folder action',
    (tester) async {
      final store = MemoryPlaybackStatsStore()..location = 'browser';
      await mountStatsOptions(tester, store, source: 'web');
      expect(find.text('播放统计保存在当前浏览器。'), findsOneWidget);
      expect(find.byKey(const Key('pick-playback-stats-folder')), findsNothing);
      expect(find.byKey(const Key('playback-stats-folder-help')), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
}
