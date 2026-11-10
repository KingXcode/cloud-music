import 'package:cloud_music/drive/drive_gateway.dart';
import 'package:flutter/cupertino.dart' hide RepeatMode;
import 'package:flutter_test/flutter_test.dart';

import 'cupertino_test_helpers.dart';

import 'package:cloud_music/models.dart';
import 'package:cloud_music/lyrics/lyrics_controller.dart';
import 'package:cloud_music/music_controller.dart';
import 'package:cloud_music/ui/music_app.dart';
import 'package:cloud_music/library_filter/library_filter.dart';
import 'package:cloud_music/playback_stats/playback_stats.dart';

class FakeController extends ChangeNotifier implements MusicController {
  FakeController(this.snapshot, {LyricsController? lyrics})
    : lyrics = lyrics ?? LyricsController();
  @override
  final LyricsController lyrics;
  @override
  final LibraryFilter libraryFilter = LibraryFilter();
  @override
  final PlaybackStats playbackStats = PlaybackStats();
  @override
  LibrarySnapshot snapshot;
  @override
  String? error;
  @override
  bool initialized = true;
  @override
  bool get isBusy =>
      snapshot.isLoading || snapshot.isScanning || isLocalImportScanning;
  String? playedId;
  final playCounts = <String, int>{};
  @override
  int playCount(Track track) => playCounts[track.id] ?? 0;
  @override
  bool get canPickFiles => snapshot.canPickFiles;
  @override
  bool get canScanDevice => snapshot.canScanDevice;
  @override
  bool get selectsFiles => snapshot.selectsFiles;
  @override
  DriveGateway? get drive => null;
  @override
  bool usingDrive = false;
  @override
  bool isLocalImportScanning = false;
  @override
  String? localImportMessage;
  int localImportCancelled = 0;
  @override
  Future<void> cancelLocalImport() async {
    localImportCancelled++;
    isLocalImportScanning = false;
    notifyListeners();
  }

  int pickedFiles = 0;
  int scans = 0;
  @override
  Future<void> pickFiles() async {
    pickedFiles++;
  }

  @override
  Future<void> scanDevice() async {
    scans++;
  }

  int picked = 0;
  int cancelled = 0;
  Duration? sought;
  @override
  Future<void> initialize() async {}
  @override
  Future<void> pickFolder() async {
    picked++;
  }

  @override
  Future<void> refresh() async {}
  @override
  Future<void> play(Track track) async {
    playedId = track.id;
  }

  @override
  Future<void> togglePlayback() async {}
  @override
  Future<void> pause() async {}
  @override
  Future<void> next() async {}
  @override
  Future<void> previous() async {}
  @override
  Future<void> seek(Duration value) async {
    sought = value;
  }

  @override
  Future<void> setShuffle(bool value) async {}
  @override
  Future<void> setRepeat(RepeatMode value) async {}
  @override
  Future<void> setVolume(double value) async {}
  @override
  Future<void> cancelLoading() async {
    cancelled++;
  }

  @override
  void clearError() {
    error = null;
    notifyListeners();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  const tracks = [
    Track(
      id: 'exact-a',
      title: '山间的风',
      artist: '林间',
      availability: TrackAvailability.ready,
      duration: Duration(minutes: 3),
    ),
    Track(
      id: 'exact-b',
      title: '城市夜航',
      artist: '夜色',
      availability: TrackAvailability.cloud,
    ),
    Track(id: 'exact-c', title: '远方', availability: TrackAvailability.offline),
    Track(id: 'exact-d', title: '旧唱片', availability: TrackAvailability.missing),
    Track(
      id: 'exact-e',
      title: '未支持音频',
      availability: TrackAvailability.unsupported,
    ),
  ];
  for (final size in [
    const Size(320, 640),
    const Size(390, 844),
    const Size(844, 390),
    const Size(1024, 768),
    const Size(1440, 900),
  ]) {
    testWidgets(
      'Empty and populated library fit ${size.width}x${size.height}',
      (tester) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final c = FakeController(const LibrarySnapshot());
        await tester.pumpWidget(MusicApp(controller: c));
        await tester.pumpAndSettle();
        expectNoMaterialWidgets();
        expect(find.text('你的音乐，不必搬家'), findsOneWidget);
        expect(tester.takeException(), isNull);
        c.snapshot = const LibrarySnapshot(
          folderName: '我的音乐',
          tracks: tracks,
          currentTrackId: 'exact-a',
          duration: Duration(minutes: 3),
        );
        c.notifyListeners();
        await tester.pumpAndSettle();
        expectNoMaterialWidgets();
        expect(tester.takeException(), isNull);
        await tester.tap(find.text('搜索').first);
        await tester.pumpAndSettle();
        expectNoMaterialWidgets();
        await tester.tap(find.byType(CupertinoTextField));
        await tester.enterText(find.byType(CupertinoTextField), '夜色');
        await tester.pumpAndSettle();
        expectNoMaterialWidgets();
        await tester.scrollUntilVisible(
          find.text('城市夜航'),
          120,
          scrollable: find
              .descendant(
                of: find.byKey(const Key('library-scroll')),
                matching: find.byType(Scrollable),
              )
              .first,
        );
        await tester.ensureVisible(find.text('城市夜航'));
        await tester.pumpAndSettle();
        expectNoMaterialWidgets();
        expect(find.text('城市夜航'), findsOneWidget);
        await tester.tap(find.text('城市夜航'));
        expect(c.playedId, 'exact-b');
        await tester.ensureVisible(
          find.descendant(
            of: find.byKey(const Key('library-search')),
            matching: find.byType(CupertinoButton),
          ),
        );
        await tester.pumpAndSettle();
        expectNoMaterialWidgets();
        await tester.tap(
          find.descendant(
            of: find.byKey(const Key('library-search')),
            matching: find.byType(CupertinoButton),
          ),
        );
        await tester.pumpAndSettle();
        expectNoMaterialWidgets();
        await tester.tap(find.text('山间的风').last);
        await tester.pumpAndSettle();
        expectNoMaterialWidgets();
        // 迷你播放器打开真实路由，返回后恢复音乐库。
        expect(find.byTooltip('返回资料库'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.tap(find.byTooltip('查看歌词'));
        await tester.pumpAndSettle();
        expectNoMaterialWidgets();
        expect(find.text('歌词').last.hitTestable(), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.tap(find.byTooltip('返回资料库'));
        await tester.pumpAndSettle();
        expectNoMaterialWidgets();
        expect(find.byKey(const Key('library-search')), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }
  testWidgets('Folder action and recoverable error are accessible', (
    tester,
  ) async {
    final c = FakeController(const LibrarySnapshot())..error = '文件夹权限需要重新授权';
    await tester.pumpWidget(MusicApp(controller: c));
    await tester.pumpAndSettle();
    expectNoMaterialWidgets();
    await tester.ensureVisible(find.text('选择音乐文件夹'));
    await tester.pumpAndSettle();
    expectNoMaterialWidgets();
    await tester.tap(find.text('选择音乐文件夹'));
    expect(c.picked, 1);
    await tester.tap(find.byTooltip('关闭提示'));
    await tester.pumpAndSettle();
    expectNoMaterialWidgets();
    expect(find.text('文件夹权限需要重新授权'), findsNothing);
    expect(tester.takeException(), isNull);
  });
  testWidgets('Large text library and player remain usable', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    tester.platformDispatcher.textScaleFactorTestValue = 1.8;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    final c = FakeController(
      const LibrarySnapshot(
        folderName: '我的音乐',
        tracks: tracks,
        currentTrackId: 'exact-a',
        duration: Duration(minutes: 3),
      ),
    );
    await tester.pumpWidget(MusicApp(controller: c));
    await tester.pumpAndSettle();
    expectNoMaterialWidgets();
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('山间的风').last);
    await tester.pumpAndSettle();
    expectNoMaterialWidgets();
    expect(find.byTooltip('返回资料库'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets(
    'Unavailable rows are grey and normal rows have no status label',
    (tester) async {
      tester.view.physicalSize = const Size(1100, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final c = FakeController(
        const LibrarySnapshot(
          folderName: '我的音乐',
          tracks: tracks,
          isLoading: true,
        ),
      );
      await tester.pumpWidget(MusicApp(controller: c));
      await tester.pump();
      expect(find.text('内容可用'), findsNothing);
      expect(find.text('未下载 · 播放时下载'), findsNothing);
      expect(find.text('暂时不可用'), findsNothing);
      expect(find.text('文件已移走'), findsNothing);
      expect(find.text('格式不支持'), findsNothing);
      for (final track in tracks) {
        final row = tester.widget<Opacity>(
          find.byKey(Key('track-availability-${track.id}')),
        );
        expect(
          row.opacity,
          track.id == 'exact-a' || track.id == 'exact-b' ? 1 : .45,
        );
      }
      await tester.tap(find.text('远方'));
      expect(c.playedId, 'exact-c');
      await tester.tap(find.byTooltip('取消加载'));
      expect(c.cancelled, 1);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('List sorting supports counts, ascending order and search', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1100, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final c = FakeController(
      const LibrarySnapshot(folderName: '我的音乐', tracks: tracks),
    )..playCounts.addAll({'exact-a': 2, 'exact-b': 9});
    await tester.pumpWidget(MusicApp(controller: c));
    await tester.pumpAndSettle();
    expect(find.text('2 次播放'), findsOneWidget);
    expect(find.text('9 次播放'), findsOneWidget);
    await tester.tap(find.byKey(const Key('library-sort')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('sort-playCount')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('apply-library-sort')));
    await tester.pumpAndSettle();
    expect(
      tester.getTopLeft(find.text('城市夜航')).dy,
      lessThan(tester.getTopLeft(find.text('山间的风')).dy),
    );
    await tester.tap(find.byKey(const Key('library-sort')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('从少到多'));
    await tester.tap(find.byKey(const Key('apply-library-sort')));
    await tester.pumpAndSettle();
    expect(
      tester.getTopLeft(find.text('远方')).dy,
      lessThan(tester.getTopLeft(find.text('山间的风')).dy),
    );
    await tester.tap(find.text('搜索').first);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('library-sort')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets('Sort controls fit compact screens with large text', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 1.8;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    final c = FakeController(
      const LibrarySnapshot(folderName: '我的音乐', tracks: tracks),
    )..playCounts['exact-a'] = 12;
    await tester.pumpWidget(MusicApp(controller: c));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('library-sort')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('sort-playCount')));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const Key('apply-library-sort')));
    await tester.pumpAndSettle();
    expect(find.text('从多到少'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.tap(find.byKey(const Key('apply-library-sort')));
    await tester.pumpAndSettle();
    expect(find.text('12 次播放'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets('Provider messages remain visible in the full player', (
    tester,
  ) async {
    final c = FakeController(
      const LibrarySnapshot(
        folderName: '我的音乐',
        tracks: tracks,
        currentTrackId: 'exact-a',
      ),
    );
    await tester.pumpWidget(MusicApp(controller: c));
    await tester.pumpAndSettle();
    expectNoMaterialWidgets();
    await tester.tap(find.text('山间的风').last);
    await tester.pumpAndSettle();
    expectNoMaterialWidgets();
    c.snapshot = const LibrarySnapshot(
      folderName: '我的音乐',
      tracks: tracks,
      currentTrackId: 'exact-a',
      message: '文件提供方无法下载，请检查网络',
    );
    c.notifyListeners();
    await tester.pumpAndSettle();
    expectNoMaterialWidgets();
    expect(find.text('文件提供方无法下载，请检查网络'), findsOneWidget);
    c.snapshot = const LibrarySnapshot(
      folderName: '我的音乐',
      tracks: tracks,
      currentTrackId: 'exact-a',
      isLoading: true,
      message: '正在等待 iCloud 下载',
    );
    c.notifyListeners();
    await tester.pump();
    expect(find.text('正在等待 iCloud 下载'), findsOneWidget);
    await tester.tap(find.byTooltip('取消加载'));
    expect(c.cancelled, 1);
    expect(tester.takeException(), isNull);
  });
  testWidgets('iPhone file selection label stays usable on a compact screen', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final snapshot = LibrarySnapshot.fromMap({
      'sourceKind': 'web',
      'selectionMode': 'files',
    });
    expect(snapshot.selectsFiles, isTrue);
    final c = FakeController(snapshot);
    await tester.pumpWidget(MusicApp(controller: c));
    await tester.pumpAndSettle();
    expectNoMaterialWidgets();
    expect(find.text('选择音乐文件（可多选）'), findsOneWidget);
    expect(find.text('选择音乐文件夹'), findsNothing);
    expect(find.byTooltip('选择或更换音乐文件'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.ensureVisible(find.text('选择音乐文件（可多选）'));
    await tester.tap(find.text('选择音乐文件（可多选）'));
    await tester.pumpAndSettle();
    expectNoMaterialWidgets();
    await tester.tap(find.text('选择音乐文件（可多选）'));
    expect(c.picked, 2);
    expect(tester.takeException(), isNull);
  });
}
