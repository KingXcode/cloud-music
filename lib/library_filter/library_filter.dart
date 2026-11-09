import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../models.dart';
import 'filter_store.dart';
import 'filter_store_factory.dart';

/// A display-only view over source metadata. Never opens or removes audio files.
class LibraryFilter extends ChangeNotifier {
  LibraryFilter({FilterStore? store}) : _store = store ?? createFilterStore();
  final FilterStore _store;
  bool _enabled = true, _disposed = false;
  int _minimumSeconds = 30;
  bool get enabled => _enabled;
  int get minimumSeconds => _minimumSeconds;
  String? _notice;
  String? get notice => _notice;
  Future<void>? _initialization;
  Future<void> _pendingWrite = Future<void>.value();
  int _writeRevision = 0;

  bool hides(Track track) =>
      _enabled &&
      track.duration > Duration.zero &&
      track.duration < Duration(seconds: _minimumSeconds);

  List<Track> visibleTracks(List<Track> tracks) =>
      tracks.where((track) => !hides(track)).toList(growable: false);

  Future<void> initialize() => _initialization ??= _load();

  Future<void> _load() async {
    try {
      final raw = await _store.read();
      if (_disposed || raw == null) return;
      if (raw.length > 512) throw const FormatException('Settings too large');
      final value = jsonDecode(raw);
      if (value is! Map ||
          value['version'] != 1 ||
          value['enabled'] is! bool ||
          value['minimumSeconds'] is! int ||
          value['minimumSeconds'] < 1 ||
          value['minimumSeconds'] > 600) {
        throw const FormatException('Invalid library filter');
      }
      _enabled = value['enabled'] as bool;
      _minimumSeconds = value['minimumSeconds'] as int;
    } catch (_) {
      if (!_disposed) _notice = '无法读取过滤设置，暂用默认的 30 秒。';
    } finally {
      if (!_disposed) notifyListeners();
    }
  }

  Future<void> update({
    required bool enabled,
    required int minimumSeconds,
  }) async {
    if (minimumSeconds < 1 || minimumSeconds > 600) {
      throw ArgumentError.value(minimumSeconds, 'minimumSeconds', '1–600');
    }
    await initialize();
    if (_disposed) return;
    _enabled = enabled;
    _minimumSeconds = minimumSeconds;
    _notice = null;
    final revision = ++_writeRevision;
    notifyListeners();
    // Capture each setting and serialize writes so rapid changes cannot restore
    // an older preference after the latest choice or a source switch.
    final raw = jsonEncode({
      'version': 1,
      'enabled': enabled,
      'minimumSeconds': minimumSeconds,
    });
    final write = _pendingWrite.then((_) => _store.write(raw));
    _pendingWrite = write.catchError((Object _) {});
    try {
      await write;
    } catch (_) {
      if (!_disposed && revision == _writeRevision) {
        _notice = '过滤已生效，但无法保存到本机；下次打开可能恢复原设置。';
        notifyListeners();
      }
    }
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
