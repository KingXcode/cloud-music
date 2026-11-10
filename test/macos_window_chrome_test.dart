import 'package:cloud_music/models.dart';
import 'package:cloud_music/ui/music_app.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'ui_music_app_test.dart' show FakeController;

const _channel = MethodChannel('cloud_music/window_chrome');
const _windowSize = Size(1100, 800);

Future<void> _mount(WidgetTester tester) async {
  tester.view.physicalSize = _windowSize;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final controller = FakeController(
    const LibrarySnapshot(
      tracks: [Track(id: 'song', title: 'Test song', artist: 'Test artist')],
      currentTrackId: 'song',
      duration: Duration(minutes: 3),
    ),
  );
  addTearDown(controller.lyrics.dispose);
  addTearDown(controller.dispose);
  await tester.pumpWidget(MusicApp(controller: controller));
  await tester.pumpAndSettle();
}

Future<void> _setNativeInset(WidgetTester tester, double inset) async {
  await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
    _channel.name,
    const StandardMethodCodec().encodeMethodCall(
      MethodCall('topInsetChanged', inset),
    ),
    null,
  );
  await tester.pumpAndSettle();
}

void main() {
  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, (call) async => 32.0);
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, null);
  });

  testWidgets('Mac library background reaches titlebar and controls avoid it', (
    tester,
  ) async {
    await _mount(tester);
    final sidebar = find
        .ancestor(of: find.text('弦泊'), matching: find.byType(Container))
        .first;
    final title = find.text('弦泊');
    final options = find.byKey(const Key('library-options'));
    expect(tester.getTopLeft(sidebar), Offset.zero);
    expect(tester.getTopLeft(title).dy, greaterThanOrEqualTo(32));
    final windowedOptionsTop = tester.getTopLeft(options).dy;
    expect(windowedOptionsTop, greaterThanOrEqualTo(32));

    await _setNativeInset(tester, 0);
    expect(tester.getTopLeft(sidebar), Offset.zero);
    expect(tester.getTopLeft(options).dy, windowedOptionsTop - 32);

    await _setNativeInset(tester, 32);
    expect(tester.getTopLeft(options).dy, windowedOptionsTop);
    expect(tester.takeException(), isNull);
  }, variant: TargetPlatformVariant.only(TargetPlatform.macOS));

  testWidgets(
    'Mac player paints to top and updates safe controls in fullscreen',
    (tester) async {
      await _mount(tester);
      await tester.tap(find.byKey(const Key('open-player')));
      await tester.pumpAndSettle();
      final back = find.byTooltip('返回资料库');
      final windowedBackTop = tester.getTopLeft(back).dy;
      expect(windowedBackTop, greaterThanOrEqualTo(32));

      final gradients = find.byWidgetPredicate(
        (widget) =>
            widget is DecoratedBox &&
            widget.decoration is BoxDecoration &&
            (widget.decoration as BoxDecoration).gradient != null,
      );
      expect(
        gradients.evaluate().any(
          (element) =>
              tester.getRect(find.byWidget(element.widget)) ==
              Offset.zero & _windowSize,
        ),
        isTrue,
        reason: 'The player backdrop must extend under native window chrome.',
      );

      await _setNativeInset(tester, 0);
      expect(tester.getTopLeft(back).dy, windowedBackTop - 32);
      await _setNativeInset(tester, 32);
      expect(tester.getTopLeft(back).dy, windowedBackTop);
      await tester.tap(back);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('library-options')), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.macOS),
  );

  testWidgets('iOS keeps its system safe area without calling Mac bridge', (
    tester,
  ) async {
    var bridgeCalls = 0;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(_channel, (
      call,
    ) async {
      bridgeCalls++;
      return 32.0;
    });
    tester.view.padding = const FakeViewPadding(top: 47);
    tester.view.viewPadding = const FakeViewPadding(top: 47);
    addTearDown(tester.view.resetPadding);
    addTearDown(tester.view.resetViewPadding);
    await _mount(tester);
    expect(bridgeCalls, 0);
    final optionsTop = tester
        .getTopLeft(find.byKey(const Key('library-options')))
        .dy;
    expect(optionsTop, greaterThanOrEqualTo(47));
    await tester.tap(find.byKey(const Key('open-player')));
    await tester.pumpAndSettle();
    expect(
      tester.getTopLeft(find.byTooltip('返回资料库')).dy,
      greaterThanOrEqualTo(47),
    );
    expect(bridgeCalls, 0);
    expect(tester.takeException(), isNull);
  }, variant: TargetPlatformVariant.only(TargetPlatform.iOS));
}
