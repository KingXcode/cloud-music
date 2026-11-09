import 'package:cloud_music/ui/update_panel.dart';
import 'package:cloud_music/ui/cupertino_settings.dart';
import 'package:cloud_music/updates/update_controller.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';

import 'cupertino_test_helpers.dart';

import 'update_controller_test.dart'
    show ControlledUpdateBackend, updateTestRelease;

Future<void> _mount(
  WidgetTester tester,
  UpdateController controller, {
  double scale = 1,
}) async {
  await tester.pumpWidget(
    CupertinoApp(
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(scale)),
        child: child!,
      ),
      home: CupertinoPageScaffold(
        child: Column(
          children: [
            UpdateBanner(controller: controller),
            Builder(
              builder: (context) => CupertinoButton(
                onPressed: () => showAppUpdates(context, controller),
                child: const Text('打开更新'),
              ),
            ),
          ],
        ),
      ),
    ),
  );
  await tester.tap(find.text('打开更新'));
  await tester.pumpAndSettle();
  expectNoMaterialWidgets();
}

Future<void> _unmount(WidgetTester tester, UpdateController controller) async {
  await tester.pumpWidget(const SizedBox());
  controller.dispose();
  await tester.pump();
}

void main() {
  for (final size in [const Size(320, 640), const Size(844, 390)]) {
    for (final scale in [1.0, 2.0]) {
      testWidgets('update panel fits $size with text scale $scale', (
        tester,
      ) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final backend = ControlledUpdateBackend();
        final controller = UpdateController(backend);
        await controller.check();
        await _mount(tester, controller, scale: scale);
        expect(find.text('应用更新'), findsOneWidget);
        await tester.ensureVisible(find.text('下载新版'));
        await tester.pumpAndSettle();
        expectNoMaterialWidgets();
        expect(tester.takeException(), isNull);
        await tester.ensureVisible(find.byTooltip('关闭更新面板'));
        await tester.tap(find.byTooltip('关闭更新面板'));
        await tester.pumpAndSettle();
        expectNoMaterialWidgets();
        expect(find.text('应用更新'), findsNothing);
        expect(find.byKey(const Key('update-banner')), findsOneWidget);
        expect(backend.downloadCalls, 0);
        expect(backend.installCalls, 0);
        expect(tester.takeException(), isNull);
        await _unmount(tester, controller);
      });
    }
  }

  testWidgets(
    'unknown total renders indeterminate progress and remains cancellable',
    (tester) async {
      final backend = ControlledUpdateBackend(platform: 'web')
        ..next = updateTestRelease(withAsset: false);
      final controller = UpdateController(backend);
      await controller.check();
      await _mount(tester, controller);
      final transfer = controller.download();
      backend.progressCallbacks.single(1024, null);
      await tester.pump();
      expect(find.textContaining('总大小未知'), findsWidgets);
      final indicators = tester.widgetList<SettingsProgress>(
        find.byType(SettingsProgress),
      );
      expect(indicators, isNotEmpty);
      expect(indicators.every((indicator) => indicator.value == null), isTrue);
      await tester.ensureVisible(find.text('取消下载'));
      await tester.tap(find.text('取消下载'));
      await tester.pumpAndSettle();
      expectNoMaterialWidgets();
      expect(backend.cancelCalls, 1);
      expect(controller.phase, UpdatePhase.available);
      backend.downloads.single.complete();
      await transfer;
      expect(controller.phase, UpdatePhase.available);
      expect(tester.takeException(), isNull);
      await _unmount(tester, controller);
    },
  );

  testWidgets(
    'closing the panel preserves the active download and visible banner',
    (tester) async {
      final backend = ControlledUpdateBackend();
      final controller = UpdateController(backend);
      await controller.check();
      await _mount(tester, controller);
      final transfer = controller.download();
      backend.progressCallbacks.single(1024, 2048);
      await tester.pump();
      await tester.tap(find.byTooltip('关闭更新面板'));
      await tester.pumpAndSettle();
      expectNoMaterialWidgets();
      expect(find.text('应用更新'), findsNothing);
      expect(find.textContaining('50%'), findsOneWidget);
      expect(backend.cancelCalls, 0);
      backend.downloads.single.complete();
      await transfer;
      await tester.pumpAndSettle();
      expectNoMaterialWidgets();
      expect(find.text('新版已下载 · 点击安装'), findsOneWidget);
      expect(backend.installCalls, 0);
      await tester.tap(find.byKey(const Key('update-banner')));
      await tester.pumpAndSettle();
      expectNoMaterialWidgets();
      expect(find.byKey(const Key('install-update')), findsOneWidget);
      await _unmount(tester, controller);
    },
  );

  for (final platform in ['android', 'macos', 'web']) {
    testWidgets(
      '$platform requires confirmation; Later preserves ready state',
      (tester) async {
        final backend = ControlledUpdateBackend(platform: platform);
        final controller = UpdateController(backend);
        await controller.check();
        final transfer = controller.download();
        backend.downloads.single.complete();
        await transfer;
        await _mount(tester, controller);
        await tester.ensureVisible(find.byKey(const Key('install-update')));
        await tester.tap(find.byKey(const Key('install-update')));
        await tester.pumpAndSettle();
        expectNoMaterialWidgets();
        expect(find.byType(CupertinoAlertDialog), findsOneWidget);
        expect(backend.installCalls, 0);
        if (platform == 'web') {
          expect(find.text('页面会重载，当前播放将停止。'), findsOneWidget);
        }
        await tester.tap(find.text('稍后'));
        await tester.pumpAndSettle();
        expectNoMaterialWidgets();
        expect(find.byType(CupertinoAlertDialog), findsNothing);
        expect(controller.phase, UpdatePhase.ready);
        expect(backend.installCalls, 0);
        await tester.tap(find.byKey(const Key('install-update')));
        await tester.pumpAndSettle();
        expectNoMaterialWidgets();
        await tester.tap(find.text('继续'));
        await tester.pumpAndSettle();
        expectNoMaterialWidgets();
        expect(backend.installCalls, 1);
        expect(controller.phase, UpdatePhase.ready);
        expect(tester.takeException(), isNull);
        await _unmount(tester, controller);
      },
    );
  }

  testWidgets(
    'iOS explains its distribution channel without download/install buttons',
    (tester) async {
      final backend = ControlledUpdateBackend(platform: 'ios');
      final controller = UpdateController(backend);
      await controller.check();
      await _mount(tester, controller);
      expect(find.textContaining('App Store'), findsOneWidget);
      expect(find.text('下载新版'), findsNothing);
      expect(find.byKey(const Key('install-update')), findsNothing);
      expect(find.byKey(const Key('update-banner')), findsNothing);
      await _unmount(tester, controller);
    },
  );

  testWidgets(
    'ready panel offers a redownload when the package becomes unusable',
    (tester) async {
      final backend = ControlledUpdateBackend();
      final controller = UpdateController(backend);
      await controller.check();
      final first = controller.download();
      backend.downloads.first.complete();
      await first;
      await _mount(tester, controller);
      await tester.ensureVisible(find.text('重新下载'));
      await tester.tap(find.text('重新下载'));
      await tester.pump();
      expect(controller.phase, UpdatePhase.downloading);
      expect(backend.downloadCalls, 2);
      expect(backend.installCalls, 0);
      backend.downloads.last.complete();
      await tester.pumpAndSettle();
      expectNoMaterialWidgets();
      expect(controller.phase, UpdatePhase.ready);
      await _unmount(tester, controller);
    },
  );
}
