import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../models.dart';
import 'playback_stats_store.dart';
import 'playback_stats_store_factory.dart';

/// 每个设备累加自己的计数，合并时按设备取最大值，避免重复同步累加。
class PlaybackStats extends ChangeNotifier {
  PlaybackStats({PlaybackStatsStore? store})
    : _store = store ?? createPlaybackStatsStore();

  final PlaybackStatsStore _store;
  final _counts = <String, Map<String, int>>{};
  final _unbasedCounts = <String, int>{};
  final _seenSessions = <String>{};
  Future<void>? _initialization;
  Future<void> _pendingWrite = Future<void>.value();
  String? _deviceId, _notice, _storageLocation;
  bool _disposed = false, _canWrite = false;
  bool _choosingFolder = false;

  String? get notice => _notice;
  String? get storageLocation => _storageLocation;
  bool get choosingFolder => _choosingFolder;
  bool get canPickFolder =>
      _store is PlaybackStatsFolderStore &&
      (_store as PlaybackStatsFolderStore).canPickFolder;

  Future<void> pickFolder() async {
    if (_disposed || !canPickFolder || _choosingFolder) return;
    _choosingFolder = true;
    _notify();
    try {
      await flush();
      if (_disposed) return;
      final selected = await (_store as PlaybackStatsFolderStore).pickFolder();
      if (selected) await reload();
    } catch (_) {
      _notice = '无法连接统计保存文件夹，请重新选择可写入的文件夹。';
    } finally {
      _choosingFolder = false;
      _notify();
    }
  }

  // 文件夹内的相对路径不随标签补全、重新授权或换设备而改变。
  // Drive 按账户隔离，浏览器按文件夹句柄隔离；Apple 保留跨设备的目录映射。
  static String trackKey(LibrarySnapshot source, Track track) => jsonEncode([
    source.sourceKind,
    const {'googleDrive', 'android', 'web'}.contains(source.sourceKind)
        ? source.sourceIdentity
        : source.folderName ?? '',
    source.sourceKind == 'android' || track.relativePath.isEmpty
        ? track.id
        : track.relativePath,
  ]);

  int count(LibrarySnapshot source, Track track) =>
      (_counts[trackKey(source, track)]?.values.fold<int>(0, (a, b) => a + b) ??
          0) +
      (_unbasedCounts[trackKey(source, track)] ?? 0);

  Future<void> initialize() => _initialization ??= _load();

  Future<void> _load() async {
    try {
      final device = await _store.deviceId();
      if (device.isEmpty) throw const FormatException('Missing device ID');
      _deviceId = device;
      _merge(await _store.read());
      _storageLocation = await _store.storageLocation();
      _canWrite = true;
    } catch (_) {
      _notice = '无法读取播放统计缓存，已保留原数据；本次新增统计暂存内存。';
    } finally {
      _notify();
    }
  }

  /// 只消费实际开始播放的会话，进度、缓冲和暂停续播都沿用同一编号。
  void observe(LibrarySnapshot snapshot) {
    if (_disposed) return;
    final session = snapshot.playbackSessionId;
    final track = snapshot.currentTrack;
    if (!snapshot.isPlaying ||
        session == null ||
        session.isEmpty ||
        track == null) {
      return;
    }
    final identity = jsonEncode([
      snapshot.sourceKind,
      snapshot.sourceIdentity,
      session,
    ]);
    if (!_seenSessions.add(identity)) return;
    final key = trackKey(snapshot, track);
    // 立即更新界面；排队保存时才在最新的持久化基数上加上这些增量。
    _unbasedCounts[key] = (_unbasedCounts[key] ?? 0) + 1;
    _notify();
    unawaited(_enqueue(_savePending));
  }

  Future<void> _savePending() async {
    await initialize();
    // 缓存读取失败时仍允许查看本次统计，但不覆盖原文件。
    if (!_canWrite || _unbasedCounts.isEmpty) return;
    try {
      // 同一设备的较新缓存也必须先合并，再应用本次尚未保存的播放。
      _merge(await _store.read());
      _applyPending();
      await _store.write(jsonEncode({'version': 1, 'counts': _counts}));
      _storageLocation = await _store.storageLocation();
      _notice = null;
    } catch (_) {
      _notice = '播放统计已在本次使用中更新，但缓存保存失败；下次播放时会重试。';
    }
    _notify();
  }

  Future<void> _enqueue(Future<void> Function() operation) {
    final next = _pendingWrite.then((_) => operation());
    _pendingWrite = next;
    return next;
  }

  void _applyPending() {
    final device = _deviceId!;
    for (final entry in _unbasedCounts.entries) {
      final devices = _counts.putIfAbsent(entry.key, () => {});
      devices[device] = (devices[device] ?? 0) + entry.value;
    }
    _unbasedCounts.clear();
  }

  Future<void> reload() => _enqueue(() async {
    await initialize();
    try {
      _deviceId ??= await _store.deviceId();
      if (_deviceId!.isEmpty) throw const FormatException('Missing device ID');
      _merge(await _store.read());
      // 读取故障恢复后，可以把尚未保存的本设备增量写回。
      _applyPending();
      _canWrite = true;
      await _store.write(jsonEncode({'version': 1, 'counts': _counts}));
      _storageLocation = await _store.storageLocation();
      _notice = null;
    } catch (_) {
      _notice = '无法刷新播放统计缓存，暂时保留当前统计。';
    }
    _notify();
  });

  /// 测试和应用退出前可等待所有已接收会话写入完成。
  Future<void> flush() async {
    await initialize();
    // observe 同步入队；等待期间新收到的会话也一并落盘。
    while (true) {
      final pending = _pendingWrite;
      await pending;
      if (identical(pending, _pendingWrite)) return;
    }
  }

  void _merge(String? raw) {
    if (raw == null) return;
    if (utf8.encode(raw).length > 8 * 1024 * 1024) {
      throw const FormatException('Playback stats too large');
    }
    final decoded = jsonDecode(raw);
    if (decoded is! Map ||
        decoded['version'] != 1 ||
        decoded['counts'] is! Map) {
      throw const FormatException('Invalid playback stats');
    }
    final parsed = <String, Map<String, int>>{};
    for (final entry in (decoded['counts'] as Map).entries) {
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
      parsed[entry.key as String] = devices;
    }
    // 整份缓存校验完后再合并，损坏文件不引入半份计数。
    for (final entry in parsed.entries) {
      final devices = _counts.putIfAbsent(entry.key, () => {});
      for (final device in entry.value.entries) {
        if (device.value > (devices[device.key] ?? 0)) {
          devices[device.key] = device.value;
        }
      }
    }
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
