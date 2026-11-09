import 'package:cloud_music/models.dart';
import 'package:cloud_music/ui/music_app.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';

import 'cupertino_test_helpers.dart';

import 'ui_music_app_test.dart' show FakeController;

const android = LibrarySnapshot(
  sourceKind: 'android',
  canScanDevice: true,
  canPickFiles: true,
);
Future<FakeController> mount(
  WidgetTester tester,
  LibrarySnapshot snapshot, {
  double scale = 1,
}) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  tester.platformDispatcher.textScaleFactorTestValue = scale;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
  final c = FakeController(snapshot);
  addTearDown(c.dispose);
  addTearDown(c.lyrics.dispose);
  await tester.pumpWidget(MusicApp(controller: c));
  await tester.pumpAndSettle();
  expectNoMaterialWidgets();
  return c;
}

Future<void> tap(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  expectNoMaterialWidgets();
  await tester.tap(finder);
  await tester.pumpAndSettle();
  expectNoMaterialWidgets();
  expect(tester.takeException(), isNull);
}

Finder get add => find.descendant(
  of: find.byTooltip('选择或更换音乐文件夹'),
  matching: find.byType(CupertinoButton),
);

void main() {
  for (final capability in [
    const LibrarySnapshot(canScanDevice: true),
    const LibrarySnapshot(canPickFiles: true),
    android,
  ]) {
    testWidgets(
      'Header chooser reflects scan ${capability.canScanDevice} files ${capability.canPickFiles}',
      (tester) async {
        await mount(tester, capability, scale: 1.8);
        await tap(tester, add);
        expect(cupertinoPopup, findsOneWidget);
        expect(find.byKey(const Key('import-folder')), findsOneWidget);
        expect(
          find.byKey(const Key('import-files')),
          capability.canPickFiles ? findsOneWidget : findsNothing,
        );
        expect(
          find.byKey(const Key('import-scan-device')),
          capability.canScanDevice ? findsOneWidget : findsNothing,
        );
        await tap(tester, find.byTooltip('关闭添加音乐'));
        expect(cupertinoPopup, findsNothing);
      },
    );
  }
  testWidgets(
    'Repeated add creates one chooser; cancel has no import side effects',
    (tester) async {
      final c = await mount(tester, android);
      final open = tester.widget<CupertinoButton>(add).onPressed!;
      open();
      open();
      await tester.pumpAndSettle();
      expectNoMaterialWidgets();
      expect(cupertinoPopup, findsOneWidget);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expectNoMaterialWidgets();
      expect(cupertinoPopup, findsNothing);
      expect([c.picked, c.pickedFiles, c.scans], [0, 0, 0]);
      await tap(tester, add);
      await tap(tester, find.byTooltip('关闭添加音乐'));
      expect(cupertinoPopup, findsNothing);
    },
  );
  testWidgets(
    'Folder, multiple files and scan chooser invoke distinct actions',
    (tester) async {
      final c = await mount(tester, android);
      for (final action in [
        'import-folder',
        'import-files',
        'import-scan-device',
      ]) {
        await tap(tester, add);
        await tap(tester, find.byKey(Key(action)));
        expect(cupertinoPopup, findsNothing);
      }
      expect([c.picked, c.pickedFiles, c.scans], [1, 1, 1]);
    },
  );
  testWidgets(
    'Original folder CTA stays direct, Android empty shortcuts stay separate',
    (tester) async {
      final c = await mount(tester, android);
      await tap(tester, find.text('选择音乐文件夹'));
      expect(c.picked, 1);
      expect(cupertinoPopup, findsNothing);
      await tap(tester, find.byKey(const Key('empty-scan-device')));
      await tap(tester, find.byKey(const Key('empty-pick-files')));
      expect([c.picked, c.pickedFiles, c.scans], [1, 1, 1]);
    },
  );
  testWidgets('Single-capability header retains direct picker activation', (
    tester,
  ) async {
    final c = await mount(tester, const LibrarySnapshot());
    await tap(tester, add);
    expect(c.picked, 1);
    expect(cupertinoPopup, findsNothing);
  });
  testWidgets('Music sources expose separate folder, files and scan actions', (
    tester,
  ) async {
    final c = await mount(tester, android);
    for (final action in [
      'source-pick-folder',
      'source-pick-files',
      'source-scan-device',
    ]) {
      await tap(tester, find.byKey(const Key('library-options')));
      await tap(tester, find.byKey(const Key('music-sources')));
      await tap(tester, find.byKey(Key(action)));
      expect(find.byTooltip('关闭音乐来源'), findsNothing);
    }
    expect([c.picked, c.pickedFiles, c.scans], [1, 1, 1]);
  });
  testWidgets('Android scanning offers cancellation while import is disabled', (
    tester,
  ) async {
    final c = await mount(tester, android);
    c.snapshot = const LibrarySnapshot(
      sourceKind: 'android',
      canScanDevice: true,
      canPickFiles: true,
      isScanning: true,
    );
    c.notifyListeners();
    await tester.pump();
    expect(tester.widget<CupertinoButton>(add).onPressed, isNull);
    await tester.tap(find.byKey(const Key('cancel-library-scan')));
    expect(c.cancelled, 1);
    expect(tester.takeException(), isNull);
  });
  testWidgets(
    'Staged local scan keeps Drive playback and cancels only the import',
    (tester) async {
      const active = Track(id: 'drive-active', title: 'Drive playing song');
      final c = await mount(
        tester,
        const LibrarySnapshot(
          sourceKind: 'googleDrive',
          folderName: 'Active Drive library',
          tracks: [active],
          currentTrackId: 'drive-active',
          isPlaying: true,
          canScanDevice: true,
          canPickFiles: true,
        ),
      );
      c.usingDrive = true;
      c.isLocalImportScanning = true;
      c.localImportMessage = '正在扫描本机音乐，现有资料库继续播放';
      c.notifyListeners();
      await tester.pump();
      expect(find.byKey(const Key('staged-import-progress')), findsOneWidget);
      expect(find.byKey(const Key('open-player')), findsOneWidget);
      expect(find.text('Drive playing song'), findsWidgets);
      expect(tester.widget<CupertinoButton>(add).onPressed, isNull);
      expect(find.byKey(const Key('cancel-library-scan')), findsNothing);
      await tester.tap(find.byKey(const Key('cancel-local-import')));
      await tester.pumpAndSettle();
      expectNoMaterialWidgets();
      expect(c.localImportCancelled, 1);
      expect(c.cancelled, 0);
      expect(c.usingDrive, isTrue);
      expect(c.snapshot.currentTrackId, 'drive-active');
      expect(c.snapshot.isPlaying, isTrue);
      expect(find.byKey(const Key('open-player')), findsOneWidget);
      expect(find.byKey(const Key('staged-import-progress')), findsNothing);
      expect(tester.widget<CupertinoButton>(add).onPressed, isNotNull);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Repeated chooser selection imports once without popping library',
    (tester) async {
      final c = await mount(tester, android);
      await tap(tester, add);
      final choose = tester
          .widget<CupertinoListTile>(
            find.descendant(
              of: find.byKey(const Key('import-files')),
              matching: find.byType(CupertinoListTile),
            ),
          )
          .onTap!;
      choose();
      choose();
      await tester.pumpAndSettle();
      expectNoMaterialWidgets();
      expect(c.pickedFiles, 1);
      expect(cupertinoPopup, findsNothing);
      expect(find.byKey(const Key('library-options')), findsOneWidget);
      expect(find.text('音乐资料库'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'Repeated source file selection imports once without popping library',
    (tester) async {
      final c = await mount(tester, android);
      await tap(tester, find.byKey(const Key('library-options')));
      await tap(tester, find.byKey(const Key('music-sources')));
      final choose = tester
          .widget<CupertinoButton>(
            find.descendant(
              of: find.byKey(const Key('source-pick-files')),
              matching: find.byType(CupertinoButton),
            ),
          )
          .onPressed!;
      choose();
      choose();
      await tester.pumpAndSettle();
      expectNoMaterialWidgets();
      expect(c.pickedFiles, 1);
      expect(find.byTooltip('关闭音乐来源'), findsNothing);
      expect(find.byKey(const Key('library-options')), findsOneWidget);
      expect(find.text('音乐资料库'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Deep library search starts at input and Back restores scroll offset',
    (tester) async {
      await mount(
        tester,
        LibrarySnapshot(
          tracks: List.generate(80, (i) => Track(id: '$i', title: 'Song $i')),
        ),
      );
      final scroll = tester
          .widget<CustomScrollView>(find.byKey(const Key('library-scroll')))
          .controller!;
      scroll.jumpTo(1300);
      await tester.pumpAndSettle();
      expectNoMaterialWidgets();
      final offset = scroll.offset;
      await tap(tester, find.text('搜索').first);
      expect(
        find.byKey(const Key('library-search')).hitTestable(),
        findsOneWidget,
      );
      expect(scroll.offset, 0);
      await tester.enterText(
        find.byKey(const Key('library-search')),
        'Song 70',
      );
      await tester.pumpAndSettle();
      expectNoMaterialWidgets();
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expectNoMaterialWidgets();
      expect(find.byKey(const Key('library-search')), findsNothing);
      expect(scroll.offset, closeTo(offset, .1));
      expect(tester.takeException(), isNull);
    },
  );
}
