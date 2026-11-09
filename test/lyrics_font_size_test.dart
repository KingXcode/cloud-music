import 'dart:async';
import 'dart:convert';
import 'dart:ui' show SemanticsAction;

import 'package:cloud_music/lyrics/lyrics_controller.dart';
import 'package:cloud_music/lyrics/lyrics_platform.dart';
import 'package:cloud_music/models.dart';
import 'package:cloud_music/ui/lyrics_panel.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';

import 'cupertino_test_helpers.dart';

const _track = Track(id: 'font-size-test', title: '虚构纸船', artist: '测试乐队');
const _lyrics = '[00:01]紙船載著想像前往遠方\n[00:02]窗邊有一座虛構的燈塔';

class _Platform implements LyricsPlatform {
  String? cache;
  bool failWrite = false;
  int requests = 0;
  Completer<String?>? pendingRead;
  final writes = <String>[];
  @override
  Future<String?> readCache() async => pendingRead?.future ?? cache;
  @override
  Future<void> writeCache(String value) async {
    if (failWrite) throw StateError('Storage unavailable');
    cache = value;
    writes.add(value);
  }

  @override
  Future<LyricsHttpResponse> get(Uri uri) async {
    requests++;
    throw StateError('Font size must never trigger networking');
  }

  @override
  Future<String?> importFile() async => null;
  @override
  void dispose() {}
}

Finder _key(String key) => find.byKey(Key(key));
Text _line(WidgetTester tester, int index) =>
    tester.widget<CupertinoButton>(_key('lyrics-line-$index')).child as Text;

Future<void> _tap(WidgetTester tester, String key) async {
  await tester.ensureVisible(_key(key));
  await tester.tap(_key(key));
  await tester.pumpAndSettle();
}

void main() {
  test('old caches use smaller default; stored values are validated', () async {
    for (final entry in <Object?, double>{
      null: 22,
      'large': 22,
      true: 22,
      9: 14,
      99: 36,
      25.6: 26,
      18: 18,
    }.entries) {
      final platform = _Platform()
        ..cache = jsonEncode({
          'version': 1,
          'entries': <String, Object>{},
          if (entry.key != null) 'fontSize': entry.key,
        });
      final c = LyricsController(platform: platform);
      await c.initialize();
      expect(c.fontSize, entry.value, reason: '${entry.key}');
      expect(c.notice, isNull);
      c.dispose();
    }
  });

  test(
    'size persists without changing original lyrics or synchronization',
    () async {
      final platform = _Platform();
      final c = LyricsController(platform: platform)..selectTrack(_track);
      await c.initialize();
      await c.importText(_lyrics);
      final original = c.originalDocument;
      final times = original!.lines.map((line) => line.time).toList();
      await c.setFontSize(18);
      await c.setPreferSimplified(false);
      expect(c.originalDocument, same(original));
      expect(c.originalDocument!.text, _lyrics);
      expect(c.document!.lines.map((line) => line.time), times);
      expect(c.document!.activeLineIndex(const Duration(seconds: 2)), 1);
      final restored = LyricsController(platform: platform)
        ..selectTrack(_track);
      await restored.initialize();
      expect(restored.fontSize, 18);
      expect(restored.preferSimplified, false);
      expect(restored.originalDocument!.text, _lyrics);
      expect(restored.document!.lines.map((line) => line.time), times);
      restored.selectTrack(const Track(id: 'another-song', title: '另一首歌'));
      expect(restored.fontSize, 18);
      expect(platform.requests, 0);
      c.dispose();
      restored.dispose();
    },
  );

  test(
    'rapid updates, bounds and non-finite values keep the final setting',
    () async {
      final platform = _Platform();
      final c = LyricsController(platform: platform);
      await c.initialize();
      await Future.wait([
        c.setFontSize(16),
        c.setFontSize(30),
        c.setFontSize(20),
      ]);
      expect(c.fontSize, 20);
      expect(jsonDecode(platform.cache!)['fontSize'], 20);
      await c.setFontSize(double.nan);
      await c.setFontSize(double.infinity);
      expect(c.fontSize, 20);
      await c.setFontSize(1);
      expect(c.fontSize, 14);
      await c.setFontSize(100);
      expect(c.fontSize, 36);
      await c.setFontSize(LyricsController.defaultFontSize);
      expect(jsonDecode(platform.cache!)['fontSize'], 22);
      c.dispose();
    },
  );

  test(
    'user change during initialization wins over loaded preference',
    () async {
      final platform = _Platform()..pendingRead = Completer<String?>();
      final c = LyricsController(platform: platform);
      final change = c.setFontSize(17);
      platform.pendingRead!.complete(
        jsonEncode({'version': 1, 'fontSize': 30, 'entries': {}}),
      );
      await change;
      expect(c.fontSize, 17);
      expect(jsonDecode(platform.cache!)['fontSize'], 17);
      c.dispose();
    },
  );

  test(
    'storage failure is truthful while the live size remains usable',
    () async {
      final platform = _Platform()..failWrite = true;
      final c = LyricsController(platform: platform);
      await c.setFontSize(18);
      expect(c.fontSize, 18);
      expect(c.fontSizeError, contains('字号仅在本次使用中有效'));
      platform.failWrite = false;
      await c.setFontSize(18);
      expect(c.fontSizeError, isNull);
      expect(jsonDecode(platform.cache!)['fontSize'], 18);
      expect(platform.requests, 0);
      c.dispose();
    },
  );

  for (final layout in [
    (const Size(390, 844), 1.0),
    (const Size(320, 700), 1.8),
    (const Size(844, 390), 1.0),
    (const Size(1440, 900), 1.0),
  ]) {
    testWidgets('size controls, semantics and dismissal at $layout', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(layout.$1);
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final platform = _Platform();
      final c = LyricsController(platform: platform)..selectTrack(_track);
      addTearDown(c.dispose);
      await c.initialize();
      await c.importText(_lyrics);
      final semantics = tester.ensureSemantics();
      await tester.pumpWidget(
        CupertinoApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: TextScaler.linear(layout.$2)),
            child: child!,
          ),
          home: CupertinoPageScaffold(
            child: SafeArea(
              child: LyricsPanel(
                controller: c,
                position: const Duration(seconds: 1),
                immersive: true,
                onSeek: (_) {},
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(_line(tester, 0).style!.fontSize, 22);
      await _tap(tester, 'lyrics-font-size');
      expect(_key('lyrics-font-size-controls'), findsOneWidget);
      await _tap(tester, 'lyrics-font-size-decrease');
      expect(c.fontSize, 21);
      expect(_line(tester, 0).style!.fontSize, 21);
      expect(
        tester.widget<Text>(_key('lyrics-font-size-preview')).style!.fontSize,
        21,
      );
      await _tap(tester, 'lyrics-font-size-increase');
      expect(c.fontSize, 22);
      await tester.ensureVisible(_key('lyrics-font-size-slider'));
      final sliderRect = tester.getRect(_key('lyrics-font-size-slider'));
      await tester.dragFrom(
        Offset(
          sliderRect.left + sliderRect.width * 8 / 22,
          sliderRect.center.dy,
        ),
        const Offset(45, 0),
      );
      await tester.pumpAndSettle();
      expect(c.fontSize, greaterThan(22));
      final slider = tester.widget<CupertinoSlider>(
        _key('lyrics-font-size-slider'),
      );
      slider.onChanged!(14);
      await tester.pumpAndSettle();
      expect(c.fontSize, 14);
      expect(
        tester
            .widget<CupertinoButton>(_key('lyrics-font-size-decrease'))
            .onPressed,
        isNull,
      );
      final node = tester.getSemantics(_key('lyrics-font-size-semantics'));
      expect(node.getSemanticsData().value, '14 点');
      tester.binding.rootPipelineOwner.visitChildren((owner) {
        owner.semanticsOwner?.performAction(node.id, SemanticsAction.increase);
      });
      await tester.pumpAndSettle();
      expect(c.fontSize, 15);
      slider.onChanged!(36);
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<CupertinoButton>(_key('lyrics-font-size-increase'))
            .onPressed,
        isNull,
      );
      expect(tester.takeException(), isNull);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(_key('lyrics-options-sheet'), findsNothing);
      await _tap(tester, 'lyrics-font-size');
      expect(c.fontSize, 36);
      await _tap(tester, 'lyrics-font-size-reset');
      expect(c.fontSize, 22);
      await tester.ensureVisible(find.text('完成'));
      await tester.tap(find.text('完成'));
      await tester.pumpAndSettle();
      expect(_key('lyrics-options-sheet'), findsNothing);
      expect(c.originalDocument!.text, _lyrics);
      expect(platform.requests, 0);
      expectNoMaterialWidgets();
      expect(tester.takeException(), isNull);
      semantics.dispose();
    });
  }

  testWidgets(
    'same active line re-centers after resizing; manual scroll stays paused',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final c = LyricsController(platform: _Platform())..selectTrack(_track);
      addTearDown(c.dispose);
      await c.initialize();
      await c.importText(
        List.generate(
          30,
          (i) => '[00:${i.toString().padLeft(2, '0')}]原创测试纸船载着想象前往远方 $i',
        ).join('\n'),
      );
      Duration? seek;
      await tester.pumpWidget(
        CupertinoApp(
          home: CupertinoPageScaffold(
            child: LyricsPanel(
              controller: c,
              position: const Duration(seconds: 12),
              immersive: true,
              onSeek: (time) => seek = time,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      double activeFraction() {
        final viewport = tester.getRect(_key('lyrics-synced-scroll'));
        final line = tester.getRect(_key('lyrics-line-12'));
        return (line.top - viewport.top) / (viewport.height - line.height);
      }

      expect(activeFraction(), closeTo(.45, .04));
      await c.setFontSize(36);
      await tester.pumpAndSettle();
      expect(activeFraction(), closeTo(.45, .04));
      await c.setFontSize(14);
      await tester.pumpAndSettle();
      expect(activeFraction(), closeTo(.45, .04));
      await tester.binding.setSurfaceSize(const Size(844, 390));
      await tester.pumpAndSettle();
      expect(activeFraction(), closeTo(.45, .04));
      tester.platformDispatcher.textScaleFactorTestValue = 1.8;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await tester.pumpAndSettle();
      expect(activeFraction(), closeTo(.45, .04));
      await tester.drag(_key('lyrics-synced-scroll'), const Offset(0, -100));
      await tester.pumpAndSettle();
      expect(_key('lyrics-follow'), findsOneWidget);
      await c.setFontSize(24);
      await tester.pumpAndSettle();
      expect(_key('lyrics-follow'), findsOneWidget);
      await _tap(tester, 'lyrics-follow');
      expect(_key('lyrics-follow'), findsNothing);
      await _tap(tester, 'lyrics-line-12');
      expect(seek, const Duration(seconds: 12));
      await tester.drag(_key('lyrics-synced-scroll'), const Offset(0, -80));
      await tester.pumpAndSettle();
      expect(_key('lyrics-follow'), findsOneWidget);
      await c.importText('[00:00]另一首原创测试歌词\n[00:10]更换文本时恢复跟随');
      await tester.pumpAndSettle();
      expect(_key('lyrics-follow'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('plain lyrics and nonimmersive panel share the preference', (
    tester,
  ) async {
    final c = LyricsController(platform: _Platform())..selectTrack(_track);
    addTearDown(c.dispose);
    await c.initialize();
    await c.importText('原创测试纸船\n向着想象的远方');
    await tester.pumpWidget(
      CupertinoApp(
        home: CupertinoPageScaffold(
          child: SingleChildScrollView(
            child: LyricsPanel(
              controller: c,
              position: Duration.zero,
              onSeek: (_) {},
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await _tap(tester, 'lyrics-font-size-decrease');
    expect(c.fontSize, 21);
    final text = tester.widget<Text>(
      find.descendant(of: _key('lyrics-plain'), matching: find.byType(Text)),
    );
    expect(text.style!.fontSize, 21);
    expect(tester.takeException(), isNull);
  });
}
