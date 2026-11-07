import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';

import 'package:web/web.dart' as web;

import 'lyrics_models.dart';
import 'lyrics_platform.dart';

LyricsPlatform createLyricsPlatform() => WebLyricsPlatform();

class WebLyricsPlatform implements LyricsPlatform {
  static const _cacheKey = 'cloud-music-lyrics-v1';
  final _requests = <web.AbortController>{};
  void Function()? _cancelPicker;

  @override
  Future<LyricsHttpResponse> get(Uri uri) async {
    if (uri.scheme != 'https' || uri.host != 'lrclib.net') {
      throw const FormatException('Unsupported lyrics provider');
    }
    final abort = web.AbortController();
    _requests.add(abort);
    final timeout = Timer(const Duration(seconds: 18), () => abort.abort());
    try {
      final response = await web.window
          .fetch(
            uri.toString().toJS,
            web.RequestInit(
              method: 'GET',
              credentials: 'omit',
              referrerPolicy: 'no-referrer',
              redirect: 'error',
              signal: abort.signal,
              headers:
                  {'Lrclib-Client': lyricsClientIdentity}.jsify()! as JSObject,
            ),
          )
          .toDart;
      final bytes = <int>[];
      final body = response.body;
      if (body != null) {
        final reader = web.ReadableStreamDefaultReader(body);
        try {
          while (true) {
            final chunk = await reader.read().toDart;
            if (chunk.done) break;
            final part = (chunk.value as JSUint8Array).toDart;
            if (bytes.length + part.length > maxLyricsResponseBytes) {
              abort.abort();
              throw const FormatException('歌词服务返回的数据过大。');
            }
            bytes.addAll(part);
          }
        } finally {
          reader.releaseLock();
        }
      }
      return LyricsHttpResponse(
        response.status,
        utf8.decode(bytes),
        retryAfter: response.headers.get('retry-after'),
      );
    } finally {
      timeout.cancel();
      _requests.remove(abort);
    }
  }

  @override
  Future<String?> readCache() async =>
      web.window.localStorage.getItem(_cacheKey);
  @override
  Future<void> writeCache(String value) async {
    if (utf8.encode(value).length > maxLyricsCacheBytes) {
      throw const FormatException('歌词缓存空间不足。');
    }
    web.window.localStorage.setItem(_cacheKey, value);
  }

  @override
  Future<String?> importFile() async {
    // 部分移动端文件提供器不会触发 change/cancel/focus 事件。
    // 新的用户手势可丢弃已放弃的输入，同时保留用户激活状态。
    _cancelPicker?.call();
    final result = Completer<String?>();
    final input = web.HTMLInputElement()
      ..type = 'file'
      ..accept = '.lrc,.txt,text/plain'
      ..style.display = 'none';
    Timer? focusTimer;
    var selected = false;
    void complete([String? value, Object? error]) {
      if (result.isCompleted) return;
      if (error != null) {
        result.completeError(error);
      } else {
        result.complete(value);
      }
    }

    final onChange = ((web.Event event) {
      final files = input.files;
      if (files == null || files.length == 0) {
        complete();
        return;
      }
      selected = true;
      final file = files.item(0)!;
      unawaited(() async {
        try {
          if (!RegExp(
            r'\.(lrc|txt)$',
            caseSensitive: false,
          ).hasMatch(file.name)) {
            throw const FormatException('请选择 .lrc 或 .txt 歌词文件。');
          }
          if (file.size > maxLyricsBytes) {
            throw const FormatException('歌词文件过大，请选择不超过 256 KB 的文件。');
          }
          final bytes = (await file.arrayBuffer().toDart).toDart.asUint8List();
          complete(utf8.decode(bytes));
        } catch (error) {
          complete(null, error);
        }
      }());
    }).toJS;
    final onCancel = ((web.Event event) => complete()).toJS;
    final onFocus = ((web.Event event) {
      focusTimer?.cancel();
      focusTimer = Timer(const Duration(milliseconds: 600), () {
        if (!selected) complete();
      });
    }).toJS;
    input.addEventListener('change', onChange);
    input.addEventListener('cancel', onCancel);
    web.window.addEventListener('focus', onFocus);
    void cancelThisPicker() => complete();
    _cancelPicker = cancelThisPicker;
    try {
      web.document.body!.append(input);
      input.click();
      return await result.future;
    } finally {
      focusTimer?.cancel();
      input.removeEventListener('change', onChange);
      input.removeEventListener('cancel', onCancel);
      web.window.removeEventListener('focus', onFocus);
      input.remove();
      if (identical(_cancelPicker, cancelThisPicker)) _cancelPicker = null;
    }
  }

  @override
  void dispose() {
    for (final request in _requests) {
      request.abort();
    }
    _requests.clear();
    _cancelPicker?.call();
  }
}
