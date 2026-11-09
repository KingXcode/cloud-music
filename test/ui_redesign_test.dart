import 'package:cloud_music/models.dart';
import 'package:cloud_music/ui/lyrics_panel.dart';
import 'package:cloud_music/ui/music_app.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'ui_music_app_test.dart' show FakeController;

const _tracks = [
  Track(id: 'a', title: 'First Song', artist: 'Artist A', album: 'Album A'),
  Track(id: 'b', title: 'Second Song', artist: 'Artist A', album: 'Album A'),
  Track(id: 'c', title: 'Third Song', artist: 'Artist B', album: 'Album B'),
];

class _Controller extends FakeController {
  _Controller()
    : super(
        const LibrarySnapshot(
          folderName: 'Test Library',
          tracks: _tracks,
          currentTrackId: 'a',
          duration: Duration(minutes: 3),
        ),
      );
  double? changedVolume;
  @override
  Future<void> setVolume(double value) async => changedVolume = value;
}

Future<_Controller> _mount(
  WidgetTester tester,
  Size size, {
  double scale = 1,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  tester.platformDispatcher.textScaleFactorTestValue = scale;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
  final controller = _Controller();
  addTearDown(controller.lyrics.dispose);
  addTearDown(controller.dispose);
  await tester.pumpWidget(MusicApp(controller: controller));
  await tester.pumpAndSettle();
  return controller;
}

Future<void> _tap(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
  expect(tester.takeException(), isNull);
}

void main() {
  for (final size in [const Size(320, 640), const Size(390, 844)]) {
    for (final scale in [1.0, 1.8]) {
      testWidgets('Compact library exposes first track at $size scale $scale', (
        tester,
      ) async {
        await _mount(tester, size, scale: scale);
        expect(find.byKey(const Key('library-search')), findsNothing);
        expect(find.byKey(const Key('music-sources')), findsNothing);
        expect(find.byKey(const Key('library-filter')), findsNothing);
        expect(
          find.byKey(const Key('library-options')).hitTestable(),
          findsOneWidget,
        );
        final first = find.text('First Song').first;
        expect(first.hitTestable(), findsOneWidget);
        expect(tester.getTopLeft(first).dy, lessThan(size.height / 2));
        expect(tester.takeException(), isNull);
      });
      testWidgets(
        'Empty library exposes import without scrolling at $size scale $scale',
        (tester) async {
          final controller = await _mount(tester, size, scale: scale);
          controller.snapshot = const LibrarySnapshot();
          controller.notifyListeners();
          await tester.pumpAndSettle();
          expect(find.byKey(const Key('open-player')), findsNothing);
          expect(find.text('专辑'), findsNothing);
          expect(find.text('歌手'), findsNothing);
          expect(find.text('选择音乐文件夹').hitTestable(), findsOneWidget);
          await tester.tap(find.text('选择音乐文件夹'));
          expect(controller.picked, 1);
          expect(tester.takeException(), isNull);
        },
      );
    }
  }

  testWidgets('Options close and system back restore the same library', (
    tester,
  ) async {
    await _mount(tester, const Size(390, 844), scale: 1.8);
    await _tap(tester, find.byKey(const Key('library-options')));
    expect(find.byType(BottomSheet), findsOneWidget);
    await _tap(tester, find.byTooltip('关闭资料库选项'));
    expect(find.byType(BottomSheet), findsNothing);
    await _tap(tester, find.byKey(const Key('library-options')));
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.byType(BottomSheet), findsNothing);
    expect(find.text('First Song').first.hitTestable(), findsOneWidget);
  });

  testWidgets(
    'Long library notices stay compact, expose details and dismiss independently',
    (tester) async {
      final controller = await _mount(tester, const Size(320, 640), scale: 1.8);
      const message = '文件提供方暂时无法读取这个文件，请检查网络连接并重新选择文件夹以恢复权限。';
      controller.snapshot = const LibrarySnapshot(
        tracks: _tracks,
        message: message,
      );
      controller.notifyListeners();
      await tester.pumpAndSettle();
      expect(tester.widget<Text>(find.text(message)).maxLines, 1);
      await _tap(tester, find.byKey(const Key('library-status-details')));
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.text(message),
        ),
        findsOneWidget,
      );
      await _tap(tester, find.text('知道了'));
      await _tap(tester, find.byTooltip('关闭资料库提示'));
      expect(find.byKey(const Key('library-status-details')), findsNothing);
      controller.snapshot = const LibrarySnapshot(
        tracks: _tracks,
        message: '已发现新的音乐文件',
      );
      controller.notifyListeners();
      await tester.pumpAndSettle();
      expect(find.text('已发现新的音乐文件'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  for (final returnWithBack in [false, true]) {
    testWidgets(
      'Search restores album group and clears query, system back $returnWithBack',
      (tester) async {
        await _mount(tester, const Size(390, 844));
        await _tap(tester, find.text('专辑').first);
        await _tap(tester, find.text('Album A'));
        await _tap(tester, find.text('搜索').first);
        await tester.enterText(
          find.byKey(const Key('library-search')),
          'Third',
        );
        await tester.pumpAndSettle();
        expect(find.text('Third Song'), findsOneWidget);
        if (returnWithBack) {
          await tester.binding.handlePopRoute();
          await tester.pumpAndSettle();
        } else {
          await _tap(tester, find.text('资料库').first);
        }
        expect(find.byKey(const Key('library-search')), findsNothing);
        expect(find.text('Album A'), findsOneWidget);
        expect(find.text('Second Song'), findsOneWidget);
        expect(find.text('Third Song'), findsNothing);
        await tester.binding.handlePopRoute();
        await tester.pumpAndSettle();
        expect(find.text('Album B'), findsOneWidget);
        await _tap(tester, find.text('搜索').first);
        expect(
          tester
              .widget<TextField>(find.byKey(const Key('library-search')))
              .controller!
              .text,
          isEmpty,
        );
        expect(tester.takeException(), isNull);
      },
    );
  }

  for (final size in [
    const Size(320, 640),
    const Size(390, 844),
    const Size(1280, 900),
  ]) {
    for (final scale in [1.0, 1.8]) {
      testWidgets('Album and artist navigation at $size, scale $scale', (
        tester,
      ) async {
        final controller = await _mount(tester, size, scale: scale);
        expect(tester.takeException(), isNull);
        await _tap(tester, find.text('专辑').first);
        expect(find.text('2 首歌曲'), findsWidgets);
        await _tap(tester, find.text('Album A'));
        await tester.scrollUntilVisible(
          find.text('Second Song'),
          120,
          scrollable: find
              .descendant(
                of: find.byKey(const Key('library-scroll')),
                matching: find.byType(Scrollable),
              )
              .first,
        );
        expect(find.text('Second Song'), findsOneWidget);
        expect(find.text('Third Song'), findsNothing);
        await _tap(tester, find.text('Second Song'));
        expect(controller.playedId, 'b');
        await _tap(tester, find.widgetWithText(TextButton, '专辑').last);
        expect(find.text('Album B'), findsOneWidget);
        // Scrolling the category header back into view is intentional on small
        // screens, where large text makes group details taller than the viewport.
        await _tap(tester, find.text('歌手').first);
        await _tap(tester, find.text('Artist B').first);
        await tester.scrollUntilVisible(
          find.text('Third Song'),
          120,
          scrollable: find
              .descendant(
                of: find.byKey(const Key('library-scroll')),
                matching: find.byType(Scrollable),
              )
              .first,
        );
        expect(find.text('Third Song'), findsOneWidget);
        expect(find.text('Second Song'), findsNothing);
        await _tap(tester, find.text('Third Song'));
        expect(controller.playedId, 'c');
        await _tap(tester, find.widgetWithText(TextButton, '歌手').last);
        expect(find.text('2 首歌曲'), findsWidgets);
      });
    }
  }

  for (final size in [
    const Size(320, 640),
    const Size(390, 844),
    const Size(1280, 900),
  ]) {
    testWidgets('Search reset and player route preserve library at $size', (
      tester,
    ) async {
      await _mount(tester, size);
      await _tap(tester, find.text('搜索').first);
      await tester.enterText(find.byKey(const Key('library-search')), 'Second');
      await tester.pumpAndSettle();
      expect(find.text('Second Song'), findsOneWidget);
      expect(find.text('Third Song'), findsNothing);
      // Invoke the actual mini-player callback twice before the route builds.
      final open = tester
          .widget<InkWell>(find.byKey(const Key('open-player')))
          .onTap!;
      open();
      open();
      await tester.pumpAndSettle();
      expect(find.byTooltip('返回资料库'), findsOneWidget);
      await _tap(tester, find.byTooltip('返回资料库'));
      expect(find.byTooltip('返回资料库'), findsNothing);
      expect(find.text('Second Song'), findsOneWidget);
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        'Second',
      );
      await _tap(tester, find.byKey(const Key('open-player')));
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.text('搜索结果 · 1 首'), findsOneWidget);
      await _tap(tester, find.text(size.width < 750 ? '资料库' : '歌曲').first);
      expect(find.byKey(const Key('library-search')), findsNothing);
      await tester.scrollUntilVisible(
        find.text('Third Song'),
        120,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('Third Song'), findsOneWidget);
      expect(find.text('搜索结果 · 1 首'), findsNothing);
    });
  }

  for (final size in [
    const Size(320, 640),
    const Size(390, 844),
    const Size(844, 390),
    const Size(1280, 900),
  ]) {
    testWidgets('Player views and exact queue selection at $size', (
      tester,
    ) async {
      final controller = await _mount(tester, size);
      await _tap(tester, find.byKey(const Key('open-player')));
      expect(
        find.byType(LyricsPanel),
        size.width >= 750 ? findsOneWidget : findsNothing,
      );
      await _tap(tester, find.byTooltip('待播清单'));
      expect(find.byKey(const Key('player-queue')), findsOneWidget);
      await _tap(tester, find.text('Second Song'));
      expect(controller.playedId, 'b');
      await _tap(tester, find.byTooltip('歌词视图'));
      expect(find.byType(LyricsPanel), findsOneWidget);
      expect(find.byKey(const Key('player-queue')), findsNothing);
      await _tap(tester, find.byTooltip('歌词视图'));
      expect(find.byType(LyricsPanel), findsNothing);
      expect(find.text('正在播放'), findsOneWidget);
      await _tap(tester, find.byTooltip('待播清单'));
      await _tap(tester, find.byTooltip('待播清单'));
      expect(find.byKey(const Key('player-queue')), findsNothing);
      if (size.height < 500) {
        await _tap(tester, find.byTooltip('音量'));
        final slider = find.descendant(
          of: find.byType(BottomSheet),
          matching: find.byType(Slider),
        );
        expect(slider, findsOneWidget);
        await tester.tap(slider);
        await tester.pumpAndSettle();
        expect(controller.changedVolume, isNotNull);
        await tester.binding.handlePopRoute();
        await tester.pumpAndSettle();
        expect(find.byTooltip('返回资料库'), findsOneWidget);
      }
      expect(tester.takeException(), isNull);
    });
  }
}
