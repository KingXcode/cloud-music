import 'package:cloud_music/library_filter/library_filter.dart';
import 'package:cloud_music/lyrics/lyrics_controller.dart';
import 'package:cloud_music/models.dart';
import 'package:cloud_music/music_controller.dart';
import 'package:cloud_music/ui/music_app.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';

import 'cupertino_test_helpers.dart';

import 'controller_test.dart' show FakeGateway;
import 'library_filter_test.dart' show MemoryFilterStore, filterTracks;
import 'lyrics_test.dart' show FakeLyricsPlatform;

Future<MusicController> mountFilter(
  WidgetTester tester,
  Size size, {
  double scale = 1,
  List<Track> tracks = filterTracks,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  tester.platformDispatcher.textScaleFactorTestValue = scale;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
  final c = MusicController(
    gateway: FakeGateway()
      ..initial = LibrarySnapshot(folderName: 'Filter fixture', tracks: tracks),
    libraryFilter: LibraryFilter(store: MemoryFilterStore()),
    lyrics: LyricsController(platform: FakeLyricsPlatform()),
  );
  await c.initialize();
  addTearDown(c.dispose);
  await tester.pumpWidget(MusicApp(controller: c));
  await tester.pumpAndSettle();
  expectNoMaterialWidgets();
  return c;
}

Future<void> tapFilter(WidgetTester tester, Finder finder) async {
  await tester.pumpAndSettle();
  expectNoMaterialWidgets();
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  expectNoMaterialWidgets();
  await tester.tap(finder);
  await tester.pumpAndSettle();
  expectNoMaterialWidgets();
  expect(tester.takeException(), isNull);
}

Future<void> openFilter(WidgetTester tester) async {
  await tapFilter(tester, find.byKey(const Key('library-options')));
  expect(find.textContaining('1 首时长未知'), findsOneWidget);
  await tapFilter(tester, find.byKey(const Key('library-filter')));
}

void main() {
  for (final size in [
    const Size(320, 640),
    const Size(390, 844),
    const Size(844, 390),
    const Size(1280, 900),
  ]) {
    for (final scale in [1.0, 1.8]) {
      testWidgets(
        'filter settings save, cancel, close and reopen at $size scale $scale',
        (tester) async {
          final c = await mountFilter(tester, size, scale: scale);
          expect(find.text('Short clip'), findsNothing);
          expect(
            find.byKey(const Key('hidden-tracks-shortcut')),
            findsOneWidget,
          );
          await openFilter(tester);
          await tester.enterText(
            find.byKey(const Key('short-audio-minimum')),
            '0',
          );
          await tapFilter(tester, find.byKey(const Key('short-audio-apply')));
          expect(find.text('请输入 1–600 之间的整数'), findsOneWidget);
          await tester.enterText(
            find.byKey(const Key('short-audio-minimum')),
            '45',
          );
          await tapFilter(tester, find.byKey(const Key('short-audio-apply')));
          expect(c.libraryFilter.minimumSeconds, 45);
          expect(cupertinoPopup, findsNothing);
          await openFilter(tester);
          await tester.enterText(
            find.byKey(const Key('short-audio-minimum')),
            '90',
          );
          await tapFilter(tester, find.text('取消'));
          expect(c.libraryFilter.minimumSeconds, 45);
          await openFilter(tester);
          await tester.binding.handlePopRoute();
          await tester.pumpAndSettle();
          expectNoMaterialWidgets();
          expect(cupertinoPopup, findsNothing);
          await openFilter(tester);
          await tapFilter(tester, find.byKey(const Key('short-audio-switch')));
          await tapFilter(tester, find.byKey(const Key('short-audio-apply')));
          expect(c.libraryFilter.enabled, false);
          expect(c.libraryFilter.minimumSeconds, 45);
          expect(find.byKey(const Key('hidden-tracks-shortcut')), findsNothing);
        },
      );
    }
  }
  testWidgets(
    'repeated options open creates one sheet; filter replaces it and Back restores library',
    (tester) async {
      await mountFilter(tester, const Size(390, 844));
      final open = tester
          .widget<CupertinoButton>(
            find.descendant(
              of: find.byKey(const Key('library-options')),
              matching: find.byType(CupertinoButton),
            ),
          )
          .onPressed!;
      open();
      open();
      await tester.pumpAndSettle();
      expectNoMaterialWidgets();
      expect(cupertinoPopup, findsOneWidget);
      await tapFilter(tester, find.byKey(const Key('library-filter')));
      expect(cupertinoPopup, findsOneWidget);
      expect(find.byTooltip('关闭资料库选项'), findsNothing);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expectNoMaterialWidgets();
      expect(cupertinoPopup, findsNothing);
      expect(find.text('音乐资料库'), findsOneWidget);
    },
  );
  testWidgets(
    'albums, artists and search do not expose hidden clips; turning off restores',
    (tester) async {
      final c = await mountFilter(tester, const Size(1280, 900));
      await tapFilter(tester, find.text('专辑').first);
      expect(find.text('Clips'), findsNothing);
      expect(find.text('Album'), findsOneWidget);
      await tapFilter(tester, find.text('歌手').first);
      expect(find.text('Clip artist'), findsNothing);
      await tapFilter(tester, find.text('搜索').first);
      await tester.enterText(
        find.byKey(const Key('library-search')),
        'Short clip',
      );
      await tester.pumpAndSettle();
      expectNoMaterialWidgets();
      expect(find.text('没有找到匹配的歌曲'), findsOneWidget);
      await tapFilter(tester, find.text('调整过滤条件'));
      await tapFilter(tester, find.byKey(const Key('short-audio-switch')));
      await tapFilter(tester, find.byKey(const Key('short-audio-apply')));
      expect(
        find.byWidgetPredicate((w) => w is Text && w.data == 'Short clip'),
        findsOneWidget,
      );
      expect(c.snapshot.tracks.length, 4);
    },
  );
  testWidgets(
    'all-hidden library offers recovery instead of import empty state',
    (tester) async {
      await mountFilter(
        tester,
        const Size(390, 844),
        tracks: [filterTracks.first],
      );
      expect(find.text('短音频已隐藏'), findsOneWidget);
      await tapFilter(tester, find.text('调整过滤条件'));
      await tapFilter(tester, find.byKey(const Key('short-audio-switch')));
      await tapFilter(tester, find.byKey(const Key('short-audio-apply')));
      expect(
        find.byWidgetPredicate((w) => w is Text && w.data == 'Short clip'),
        findsOneWidget,
      );
    },
  );
}
