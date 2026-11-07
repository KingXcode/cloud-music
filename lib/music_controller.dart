import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'gateway/music_gateway.dart';
import 'models.dart';

class MusicController extends ChangeNotifier {
  // Public injection name intentionally differs from the private field.
  // ignore: prefer_initializing_formals
  MusicController({required MusicGateway gateway}) : _gateway = gateway;
  final MusicGateway _gateway;
  LibrarySnapshot _snapshot = const LibrarySnapshot();
  LibrarySnapshot get snapshot => _snapshot;
  String? _error;
  String? get error => _error;
  bool _initialized = false,
      _choosingFolder = false,
      _refreshing = false,
      _disposed = false;
  int _eventRevision = 0;
  bool get initialized => _initialized;
  bool get isBusy =>
      !_initialized || _choosingFolder || _refreshing || _snapshot.isScanning;
  Future<void>? _initialization;
  StreamSubscription<LibrarySnapshot>? _subscription;

  Future<void> initialize() => _initialization ??= _initialize();
  Future<void> _initialize() async {
    final revision = _eventRevision;
    _subscription = _gateway.snapshots.listen(
      (value) {
        if (_disposed) return;
        _eventRevision++;
        _snapshot = value;
        notifyListeners();
      },
      onError: (Object error) {
        _showError(error);
      },
    );
    try {
      final initial = await _gateway.initialize();
      if (!_disposed && revision == _eventRevision) _snapshot = initial;
    } catch (error) {
      _showError(error);
    } finally {
      if (!_disposed) {
        _initialized = true;
        notifyListeners();
      }
    }
  }

  Future<void> pickFolder() async {
    if (isBusy) return;
    _choosingFolder = true;
    notifyListeners();
    await _command('pickFolder');
    if (!_disposed) {
      _choosingFolder = false;
      notifyListeners();
    }
  }

  Future<void> refresh() async {
    if (isBusy) return;
    _refreshing = true;
    notifyListeners();
    await _command('refresh');
    if (!_disposed) {
      _refreshing = false;
      notifyListeners();
    }
  }

  Future<void> play(Track track) => _command('play', {'id': track.id});
  Future<void> togglePlayback() => _command('togglePlayback');
  Future<void> pause() => _command('pause');
  Future<void> next() => _command('next');
  Future<void> previous() => _command('previous');
  Future<void> cancelLoading() => _command('cancelLoading');
  Future<void> seek(Duration position) => _command('seek', {
    'positionMs': position.inMilliseconds.clamp(
      0,
      _snapshot.duration.inMilliseconds,
    ),
  });
  Future<void> setShuffle(bool enabled) =>
      _command('setShuffle', {'enabled': enabled});
  Future<void> setRepeat(RepeatMode mode) =>
      _command('setRepeat', {'mode': mode.name});
  Future<void> setVolume(double volume) =>
      _command('setVolume', {'volume': volume.clamp(0, 1)});
  void clearError() {
    if (_disposed) return;
    _error = null;
    notifyListeners();
  }

  Future<void> _command(
    String name, [
    Map<String, Object?> arguments = const {},
  ]) async {
    if (_disposed) return;
    _error = null;
    notifyListeners();
    try {
      await _gateway.command(name, arguments);
    } catch (error) {
      _showError(error);
    }
  }

  void _showError(Object error) {
    if (_disposed) return;
    _error = switch (error) {
      PlatformException(:final message) => message ?? '暂时无法完成，请重试。',
      MissingPluginException() => '此平台的音频服务尚未连接。请使用完整构建的应用。',
      _ => '操作未完成：$error',
    };
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    unawaited(_subscription?.cancel());
    unawaited(_gateway.dispose());
    super.dispose();
  }
}
