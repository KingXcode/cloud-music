import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';

import 'lyrics_platform.dart';

LyricsPlatform createLyricsPlatform() => NativeLyricsPlatform();

class NativeLyricsPlatform implements LyricsPlatform {
  NativeLyricsPlatform({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel('cloud_music/control');
  final MethodChannel _channel;
  final _clients = <HttpClient>{};

  @override
  Future<LyricsHttpResponse> get(Uri uri) async {
    // 控制器构造固定的 LRCLIB HTTPS 目标地址，拒绝重定向，
    // 避免在用户不知情时向其他服务泄露歌曲元数据。
    if (uri.scheme != 'https' || uri.host != 'lrclib.net') {
      throw const FormatException('Unsupported lyrics provider');
    }
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 12);
    client.userAgent = lyricsClientIdentity;
    _clients.add(client);
    try {
      return await (() async {
        final request = await client.getUrl(uri);
        request.followRedirects = false;
        final response = await request.close();
        final bytes = <int>[];
        await for (final part in response) {
          if (bytes.length + part.length > maxLyricsResponseBytes) {
            throw const FormatException('歌词服务返回的数据过大。');
          }
          bytes.addAll(part);
        }
        return LyricsHttpResponse(
          response.statusCode,
          utf8.decode(bytes),
          retryAfter: response.headers.value('retry-after'),
        );
      })().timeout(const Duration(seconds: 18));
    } finally {
      _clients.remove(client);
      client.close(force: true);
    }
  }

  @override
  Future<String?> readCache() =>
      _channel.invokeMethod<String>('readLyricsCache');
  @override
  Future<void> writeCache(String value) =>
      _channel.invokeMethod<void>('writeLyricsCache', {'value': value});
  @override
  Future<String?> importFile() => _channel.invokeMethod<String>('importLyrics');
  @override
  void dispose() {
    for (final client in _clients) {
      client.close(force: true);
    }
    _clients.clear();
  }
}
