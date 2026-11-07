@TestOn('browser')
library;

import 'dart:js_interop';

import 'package:cloud_music/lyrics/lyrics_controller.dart';
import 'package:cloud_music/lyrics/lyrics_web.dart';
import 'package:cloud_music/models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:web/web.dart' as web;

// 测试真实浏览器输入生命周期时，阻止弹出实际系统对话框。
@JS('HTMLInputElement.prototype')
external _InputPrototype get _prototype;

extension type _InputPrototype(JSObject _) implements JSObject {
  external JSFunction get click;
  external set click(JSFunction value);
}

void main() {
  test('abandoned Web picker can Cancel and reopen; stale cleanup is isolated', () async {
    final original = _prototype.click;
    _prototype.click = (() {}).toJS;
    final c = LyricsController(platform: WebLyricsPlatform());
    c.selectTrack(
      const Track(id: 'fictional', title: 'Fictional', artist: 'Fixture'),
    );
    try {
      final first = c.importFile();
      expect(c.busy, isTrue);
      expect(web.document.querySelectorAll('input[type=file]').length, 1);
      // 模拟移动端文件提供器返回时未触发 change、cancel 或 focus 事件。
      c.cancelSearch();
      final second = c.importFile();
      await first;
      expect(c.busy, isTrue);
      expect(c.error, isNull);
      expect(web.document.querySelectorAll('input[type=file]').length, 1);
      final active = web.document.querySelector('input[type=file]')!;
      active.dispatchEvent(web.Event('cancel'));
      await second;
      expect(c.busy, isFalse);
      expect(web.document.querySelectorAll('input[type=file]').length, 0);
      final third = c.importFile();
      web.document
          .querySelector('input[type=file]')!
          .dispatchEvent(web.Event('cancel'));
      await third;
      expect(c.error, isNull);
    } finally {
      c.dispose();
      _prototype.click = original;
    }
  });
}
