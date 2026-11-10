import 'dart:io';
import 'dart:ui' as ui;

import 'package:cloud_music/lyrics/lyrics_controller.dart';
import 'package:cloud_music/models.dart';
import 'package:cloud_music/ui/music_app.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'lyrics_test.dart' show FakeLyricsPlatform;
import 'ui_music_app_test.dart' show FakeController;

const _track = Track(
  id: 'paper-window',
  title: 'Paper Window',
  artist: 'Imaginary Ensemble',
  duration: Duration(seconds: 90),
);
final _captureKey = GlobalKey();
final _captureDirectory =
    Platform.environment['CLOUD_MUSIC_SCROLL_CAPTURE_DIR'];

Future<void> _loadCaptureFonts(WidgetTester tester) async {
  if (_captureDirectory == null) return;
  await tester.runAsync(() async {
    const path =
        '/System/Library/AssetsV2/com_apple_MobileAsset_Font8/'
        '86ba2c91f017a3749571a82f2c6d890ac7ffb2fb.asset/AssetData/PingFang.ttc';
    final font = File(path);
    if (!font.existsSync()) return;
    final bytes = await font.readAsBytes();
    for (final family in [
      '.SF Pro Text',
      '.SF Pro Display',
      'CupertinoSystemText',
      'CupertinoSystemDisplay',
      'PingFang SC',
      'Roboto',
    ]) {
      await (FontLoader(
        family,
      )..addFont(Future.value(ByteData.sublistView(bytes)))).load();
    }
    final icons = File(
      '${Platform.environment['HOME']}/.pub-cache/hosted/pub.dev/'
      'cupertino_icons-1.0.9/assets/CupertinoIcons.ttf',
    );
    if (icons.existsSync()) {
      await (FontLoader(
        'packages/cupertino_icons/CupertinoIcons',
      )..addFont(icons.readAsBytes().then(ByteData.sublistView))).load();
    }
  });
}

Future<void> _capture(WidgetTester tester, String name) async {
  if (_captureDirectory == null) return;
  final boundary =
      _captureKey.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  boundary.markNeedsPaint();
  await tester.pump();
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 2);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    final output = Directory(_captureDirectory!);
    await output.create(recursive: true);
    await File('${output.path}/$name.png')
        .writeAsBytes(bytes!.buffer.asUint8List());
    image.dispose();
  });
}

LibrarySnapshot _snapshot(Duration position) => LibrarySnapshot(
  tracks: const [_track],
  currentTrackId: _track.id,
  duration: _track.duration,
  position: position,
);

Future<FakeController> _mount(
  WidgetTester tester, {
  Size size = const Size(800, 640),
  double scale = 1,
}) async {
  await _loadCaptureFonts(tester);
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  tester.platformDispatcher.textScaleFactorTestValue = scale;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
  final lyrics = LyricsController(platform: FakeLyricsPlatform());
  await lyrics.initialize();
  lyrics.selectTrack(_track);
  await lyrics.importText(
    List.generate(40, (i) {
      final seconds = i * 2;
      return '[${(seconds ~/ 60).toString().padLeft(2, '0')}:'
          '${(seconds % 60).toString().padLeft(2, '0')}.00]'
          'Paper window test line $i';
    }).join('\n'),
  );
  final controller = FakeController(_snapshot(Duration.zero), lyrics: lyrics);
  addTearDown(controller.dispose);
  addTearDown(lyrics.dispose);
  await tester.pumpWidget(
    RepaintBoundary(
      key: _captureKey,
      child: MusicApp(controller: controller),
    ),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const Key('open-player')));
  await tester.pumpAndSettle();
  return controller;
}

Finder _area(String key) => find.byKey(Key(key));

Finder _bar(String key) =>
    find.descendant(of: _area(key), matching: find.byType(RawScrollbar));

ScrollbarPainter _painter(WidgetTester tester, String key) {
  final paint = find.descendant(
    of: _bar(key),
    matching: find.byWidgetPredicate(
      (widget) =>
          widget is CustomPaint && widget.foregroundPainter is ScrollbarPainter,
    ),
  );
  return tester.widget<CustomPaint>(paint).foregroundPainter!
      as ScrollbarPainter;
}

double _opacity(WidgetTester tester, String key) =>
    _painter(tester, key).fadeoutOpacityAnimation.value;

void main() {
  const channel = MethodChannel('cloud_music/window_chrome');
  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async => 32.0);
  });
  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  testWidgets(
    'Regular Mac player fits controls and reserves a separate scrollbar gutter',
    (tester) async {
      await _mount(tester);
      final details = _area('player-details-layout');
      expect(
        find.descendant(
          of: details,
          matching: find.byType(SingleChildScrollView),
        ),
        findsNothing,
      );
      expect(
        find.byKey(const Key('player-play-pause')).hitTestable(),
        findsOneWidget,
      );
      expect(find.byTooltip('待播清单').hitTestable(), findsOneWidget);
      final volume = find.bySemanticsLabel('音量');
      expect(volume.hitTestable(), findsOneWidget);
      expect(_bar('player-details-scroll-area'), findsNothing);
      final detailsBar = tester.getRect(details);
      expect(
        tester.getRect(volume).right,
        lessThanOrEqualTo(detailsBar.right - 24),
      );
      final lyricsBar = tester.getRect(_bar('lyrics-scroll-area'));
      final lyricsViewport = tester.getRect(_area('lyrics-synced-scroll'));
      expect(lyricsBar.right - lyricsViewport.right, closeTo(24, .1));
      expect(_opacity(tester, 'lyrics-scroll-area'), 0);
      expect(tester.takeException(), isNull);
      await _capture(tester, 'player-800x640-idle');
    },
    variant: TargetPlatformVariant.only(TargetPlatform.macOS),
  );

  for (final scenario in [
    (size: const Size(800, 320), scale: 1.0),
    (size: const Size(1000, 700), scale: 2.0),
  ]) {
    testWidgets('Mac player keeps overflow controls reachable at $scenario', (
      tester,
    ) async {
      await _mount(tester, size: scenario.size, scale: scenario.scale);
      final detailsScroll = _area('player-details-scroll');
      expect(detailsScroll, findsOneWidget);
      final scroll = tester.widget<SingleChildScrollView>(detailsScroll);
      expect(scroll.controller!.position.maxScrollExtent, greaterThan(0));
      final queue = find.byTooltip('待播清单');
      await tester.ensureVisible(queue);
      await tester.pumpAndSettle();
      expect(queue.hitTestable(), findsOneWidget);
      await tester.tap(queue);
      await tester.pumpAndSettle();
      expect(find.text('来自音乐资料库 · 1 首'), findsOneWidget);
      expect(tester.takeException(), isNull);
    }, variant: TargetPlatformVariant.only(TargetPlatform.macOS));
  }

  testWidgets(
    'Mac resizing from short to regular clears the obsolete details scrollbar',
    (tester) async {
      await _mount(tester, size: const Size(800, 320));
      await tester.sendEventToBinding(
        PointerScrollEvent(
          position: tester.getCenter(_area('player-details-scroll')),
          scrollDelta: const Offset(0, 60),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      expect(_opacity(tester, 'player-details-scroll-area'), greaterThan(0));
      tester.view.physicalSize = const Size(800, 640);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      expect(_area('player-details-scroll'), findsNothing);
      expect(_bar('player-details-scroll-area'), findsNothing);
      expect(find.byTooltip('待播清单').hitTestable(), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.macOS),
  );

  testWidgets(
    'Automatic lyrics stay quiet while wheel scrolling shows and fades its bar',
    (tester) async {
      final controller = await _mount(tester);
      final viewport = _area('lyrics-synced-scroll');
      final scroll = tester.widget<SingleChildScrollView>(viewport).controller!;
      controller.snapshot = _snapshot(const Duration(seconds: 42));
      controller.notifyListeners();
      await tester.pump();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      expect(scroll.offset, greaterThan(0));
      expect(_opacity(tester, 'lyrics-scroll-area'), 0);
      await tester.pumpAndSettle();
      expect(_opacity(tester, 'lyrics-scroll-area'), 0);

      await tester.sendEventToBinding(
        PointerScrollEvent(
          position: tester.getCenter(viewport),
          scrollDelta: const Offset(0, 80),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      expect(_opacity(tester, 'lyrics-scroll-area'), greaterThan(0));
      expect(_area('lyrics-follow'), findsOneWidget);
      await _capture(tester, 'player-800x640-lyrics-wheel');
      final bar = tester.getRect(_bar('lyrics-scroll-area'));
      final painter = _painter(tester, 'lyrics-scroll-area');
      final thumbPoints = [
        for (double y = 0; y < bar.height; y++)
          if (painter.hitTestOnlyThumbInteractive(
            Offset(bar.width - 7.5, y),
            PointerDeviceKind.mouse,
          ))
            bar.topLeft + Offset(bar.width - 7.5, y),
      ];
      expect(thumbPoints, isNotEmpty);
      final beforeThumbDrag = scroll.offset;
      final drag = await tester.startGesture(
        thumbPoints[thumbPoints.length ~/ 2],
        kind: PointerDeviceKind.mouse,
      );
      await tester.pump();
      await drag.moveBy(const Offset(0, 35));
      await tester.pump();
      await drag.up();
      await tester.pump(const Duration(milliseconds: 200));
      expect(scroll.offset, greaterThan(beforeThumbDrag + 35));
      final manualOffset = scroll.offset;
      controller.snapshot = _snapshot(const Duration(seconds: 58));
      controller.notifyListeners();
      await tester.pumpAndSettle();
      expect(scroll.offset, closeTo(manualOffset, .1));
      await tester.pump(const Duration(seconds: 2));
      await tester.pumpAndSettle();
      expect(_opacity(tester, 'lyrics-scroll-area'), 0);
      expect(tester.takeException(), isNull);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.macOS),
  );
}
