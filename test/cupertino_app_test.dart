import 'dart:io';

import 'package:cloud_music/models.dart';
import 'package:cloud_music/ui/music_app.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';

import 'cupertino_test_helpers.dart';
import 'ui_music_app_test.dart' show FakeController;

void main() {
  test('production UI cannot import Material or alias its controls', () {
    final files = Directory('lib/ui')
        .listSync(recursive: true)
        .whereType<File>()
        .where((file) => file.path.endsWith('.dart'));
    expect(files, isNotEmpty);
    for (final file in files) {
      expect(
        file.readAsStringSync(),
        isNot(contains('package:flutter/material.dart')),
        reason: file.path,
      );
    }
  });

  for (final size in [const Size(320, 640), const Size(1280, 900)]) {
    testWidgets('native Cupertino navigation and controls at $size', (
      tester,
    ) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      tester.platformDispatcher.textScaleFactorTestValue = 1.8;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      final controller = FakeController(
        const LibrarySnapshot(
          tracks: [
            Track(
              id: 'a',
              title: 'First Song',
              artist: 'Artist',
              album: 'Album',
            ),
            Track(
              id: 'b',
              title: 'Second Song',
              artist: 'Artist',
              album: 'Album',
            ),
          ],
          currentTrackId: 'a',
          duration: Duration(minutes: 3),
        ),
      );
      addTearDown(controller.dispose);
      addTearDown(controller.lyrics.dispose);
      await tester.pumpWidget(MusicApp(controller: controller));
      await tester.pumpAndSettle();
      expect(find.byType(CupertinoApp), findsOneWidget);
      expect(find.byType(CupertinoPageScaffold), findsOneWidget);
      expect(
        find.byType(CupertinoTabBar),
        size.width < 750 ? findsOneWidget : findsNothing,
      );
      expect(
        find.byWidgetPredicate((w) => w is CupertinoSlidingSegmentedControl),
        size.width < 750 ? findsOneWidget : findsNothing,
      );
      expectNoMaterialWidgets();

      Future<void> tap(Finder finder) async {
        await tester.pumpAndSettle();
        await tester.ensureVisible(finder);
        await tester.pumpAndSettle();
        await tester.tap(finder);
        await tester.pumpAndSettle();
        expectNoMaterialWidgets();
        expect(tester.takeException(), isNull);
      }

      await tap(find.text('搜索').first);
      expect(find.byType(CupertinoSearchTextField), findsOneWidget);
      await tester.enterText(find.byType(CupertinoSearchTextField), 'Second');
      await tester.pumpAndSettle();
      expect(find.text('Second Song'), findsOneWidget);
      final editable = tester.state<EditableTextState>(
        find.byType(EditableText),
      );
      editable.widget.controller.selection = const TextSelection(
        baseOffset: 0,
        extentOffset: 6,
      );
      expect(editable.showToolbar(), isTrue);
      await tester.pumpAndSettle();
      expect(
        find.byType(CupertinoAdaptiveTextSelectionToolbar),
        findsOneWidget,
      );
      expectNoMaterialWidgets();
      editable.hideToolbar();
      await tester.pumpAndSettle();
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      for (var i = 0; i < 2; i++) {
        await tap(find.byKey(const Key('library-options')));
        expect(cupertinoPopup, findsOneWidget);
        await tap(find.byKey(const Key('library-filter')));
        expect(cupertinoPopup, findsOneWidget);
        expect(find.byType(CupertinoSwitch), findsOneWidget);
        expect(find.byType(CupertinoTextField), findsOneWidget);
        await tap(find.byTooltip('关闭短音频过滤'));
        expect(cupertinoPopup, findsNothing);
      }
      await tap(find.byKey(const Key('open-player')));
      expect(find.byType(CupertinoSlider), findsWidgets);
      final title = find.text('First Song').last;
      expect(
        DefaultTextStyle.of(tester.element(title)).style.color,
        CupertinoColors.white,
      );
      await tap(find.byTooltip('待播清单'));
      expect(find.byKey(const Key('player-queue')), findsOneWidget);
      await tap(find.byTooltip('歌词视图'));
      await tap(find.byTooltip('返回资料库'));
      expect(find.byKey(const Key('library-options')), findsOneWidget);
      expectNoMaterialWidgets();
    });
  }
}
