import 'dart:convert';

import 'package:web/web.dart' as web;

import 'playback_stats_store.dart';

PlaybackStatsStore createPlaybackStatsStore() => WebPlaybackStatsStore();

class WebPlaybackStatsStore implements PlaybackStatsStore {
  WebPlaybackStatsStore({String? writerId}) : _writer = writerId ?? _writerId;

  static const key = 'cloud-music-playback-stats-v1';
  static const deviceKey = 'cloud-music-playback-device-v1';
  static const writerPrefix = '$key:writer:';
  // 同一浏览器的多个标签页分别递增，避免同时写同一设备分量。
  static final _writerId = web.window.crypto.randomUUID();
  final String _writer;
  String? _deviceIdentity;

  @override
  Future<String?> read() async {
    final counts = <String, Map<String, int>>{};
    var found = false;
    final storage = web.window.localStorage;
    for (var i = 0; i < storage.length; i++) {
      final name = storage.key(i);
      if (name != key && !(name?.startsWith(writerPrefix) ?? false)) continue;
      final raw = storage.getItem(name!);
      if (raw == null) continue;
      found = true;
      _merge(counts, _decode(raw));
    }
    return found ? jsonEncode({'version': 1, 'counts': counts}) : null;
  }

  @override
  Future<void> write(String value) async {
    final incoming = _decode(value);
    final device = await deviceId();
    final name = '$writerPrefix$_writer';
    final storage = web.window.localStorage;
    final previous = storage.getItem(name);
    final own = previous == null
        ? <String, Map<String, int>>{}
        : _decode(previous);
    _merge(own, incoming);
    final counts = <String, Map<String, int>>{
      for (final entry in own.entries)
        if ((entry.value[device] ?? 0) > 0)
          entry.key: {device: entry.value[device]!},
    };
    // 只保存本标签页的分量；其他标签页和旧版主缓存始终保留，避免覆盖。
    storage.setItem(name, jsonEncode({'version': 1, 'counts': counts}));
  }

  @override
  Future<String> deviceId() async {
    if (_deviceIdentity != null) return _deviceIdentity!;
    final saved = web.window.localStorage.getItem(deviceKey);
    if (saved != null && saved.isNotEmpty) {
      return _deviceIdentity = '$saved:$_writer';
    }
    final value = web.window.crypto.randomUUID();
    web.window.localStorage.setItem(deviceKey, value);
    return _deviceIdentity = '$value:$_writer';
  }

  @override
  Future<String> storageLocation() async => 'browser';
}

Map<String, Map<String, int>> _decode(String raw) {
  if (utf8.encode(raw).length > 8 * 1024 * 1024) {
    throw const FormatException('Playback stats too large');
  }
  final document = jsonDecode(raw);
  if (document is! Map ||
      document['version'] != 1 ||
      document['counts'] is! Map) {
    throw const FormatException('Invalid playback stats');
  }
  final counts = <String, Map<String, int>>{};
  for (final entry in (document['counts'] as Map).entries) {
    if (entry.key is! String || entry.value is! Map) {
      throw const FormatException('Invalid playback stats entry');
    }
    final devices = <String, int>{};
    for (final device in (entry.value as Map).entries) {
      if (device.key is! String ||
          (device.key as String).isEmpty ||
          device.value is! int ||
          device.value < 0 ||
          device.value > 9007199254740991) {
        throw const FormatException('Invalid playback count');
      }
      devices[device.key as String] = device.value as int;
    }
    counts[entry.key as String] = devices;
  }
  return counts;
}

void _merge(
  Map<String, Map<String, int>> into,
  Map<String, Map<String, int>> from,
) {
  for (final entry in from.entries) {
    final devices = into.putIfAbsent(entry.key, () => {});
    for (final device in entry.value.entries) {
      if (device.value > (devices[device.key] ?? 0)) {
        devices[device.key] = device.value;
      }
    }
  }
}
