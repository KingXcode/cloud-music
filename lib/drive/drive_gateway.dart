import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../gateway/music_gateway.dart';
import '../models.dart';
import 'drive_api.dart';
import 'drive_platform.dart';

/// 网盘浏览与播放会话。保存文件编号，不保存临时媒体 URL 或访问令牌。
class DriveGateway extends ChangeNotifier implements MusicGateway {
  DriveGateway({required DrivePlatform platform, http.Client? client})
    // ignore: prefer_initializing_formals
    : _platform = platform {
    _api = DriveApi(accessToken: _accessToken, client: client);
    _playbackSubscription = _platform.playback.listen(_onPlayback);
  }
  final DrivePlatform _platform;
  late final DriveApi _api;
  final _events = StreamController<LibrarySnapshot>.broadcast(sync: true);
  late final StreamSubscription<DrivePlayback> _playbackSubscription;
  final _random = Random();
  bool _disposed = false, _connected = false, _busy = false;
  int _revision = 0, _playRevision = 0;
  String? _account, _error;
  bool? _connectedBeforeAuthorization;
  List<DriveFile> _entries = const [];
  List<DriveFile> _path = const [];
  List<Track> _tracks = const [];
  Map<String, DriveFile> _files = const {};
  DriveFile? _selectedFolder;
  DrivePlayback _playback = const DrivePlayback();
  bool _shuffle = false;
  bool _ignorePlayback = false;
  bool _completionHandled = false;
  final Set<String> _shufflePlayed = {};
  final List<String> _history = [];
  RepeatMode _repeat = RepeatMode.off;
  double _volume = 1;

  bool get configured => _platform.configured;
  String get setupMessage => _platform.setupMessage;
  String get playbackNotice => _platform.playbackNotice;
  bool get connected => _connected;
  bool get busy => _busy;
  int get browseRevision => _revision;
  String? get error => _error;
  List<DriveFile> get entries => List.unmodifiable(_entries);
  List<DriveFile> get path => List.unmodifiable(_path);
  DriveFile get currentFolder => _path.isEmpty
      ? const DriveFile(
          id: 'root',
          name: '我的云端硬盘',
          mimeType: 'application/vnd.google-apps.folder',
        )
      : _path.last;

  LibrarySnapshot get snapshot => LibrarySnapshot(
    sourceKind: 'googleDrive',
    sourceIdentity: _account ?? '',
    folderName: _selectedFolder == null
        ? null
        : 'Google Drive · ${_selectedFolder!.name}',
    tracks: _tracks,
    currentTrackId: _playback.id,
    isPlaying: _playback.playing,
    isLoading: _playback.loading,
    isScanning: _busy,
    position: _playback.position,
    duration: _playback.duration,
    shuffle: _shuffle,
    repeatMode: _repeat,
    volume: _volume,
    message:
        _playback.error ??
        (_playback.loading ? '正在读取 Google Drive 音频…' : _error),
  );

  @override
  Stream<LibrarySnapshot> get snapshots => _events.stream;

  @override
  Future<LibrarySnapshot> initialize() async {
    try {
      await _platform.initialize();
    } catch (_) {
      _error = 'Google 登录组件初始化失败，系统文件仍可使用。请检查客户端配置。';
    }
    return snapshot;
  }

  void _notify() {
    if (_disposed) return;
    _events.add(snapshot);
    notifyListeners();
  }

  Future<String> _accessToken() async {
    final authorization = await _platform.authorize();
    if (authorization == null || authorization.accessToken.isEmpty) {
      throw const DriveException(
        'Google 授权已过期，请点击“重新连接”。',
        requiresAuthorization: true,
      );
    }
    return authorization.accessToken;
  }

  String _safeError(Object error) => error is DriveException
      ? error.message
      : 'Google Drive 操作未完成。请检查网络、授权和开发者配置后重试。';

  void _recordError(Object error) {
    _error = _safeError(error);
    if (error is DriveException && error.requiresAuthorization) {
      _connected = false;
    }
  }

  /// 仅由连接按钮调用；授权弹窗在第一个 await 之前交给平台启动。
  Future<void> connect() async {
    if (_busy || _disposed) return;
    if (!configured) {
      _error = setupMessage;
      _notify();
      return;
    }
    final revision = ++_revision;
    _busy = true;
    _connectedBeforeAuthorization = _connected;
    _connected = false;
    _error = null;
    _notify();
    try {
      final authorization = await _platform.authorize(interactive: true);
      if (_disposed || revision != _revision) return;
      if (authorization == null) {
        _connected = _connectedBeforeAuthorization ?? false;
        _connectedBeforeAuthorization = null;
        return;
      }
      _connectedBeforeAuthorization = null;
      await stop();
      final account = await _api.accountIdentity();
      if (_disposed || revision != _revision) return;
      if (_account != account) {
        _tracks = const [];
        _files = const {};
        _selectedFolder = null;
        _path = const [];
      }
      _account = account;
      _connected = true;
      final entries = await _api.listFolder(
        currentFolder.id,
        cancelled: () => revision != _revision || _disposed,
      );
      if (_disposed || revision != _revision) return;
      _entries = entries;
    } catch (error) {
      if (revision == _revision && !_disposed) {
        _connected = _connectedBeforeAuthorization ?? _connected;
        _connectedBeforeAuthorization = null;
        _recordError(error);
      }
    } finally {
      if (revision == _revision && !_disposed) {
        _busy = false;
        _notify();
      }
    }
  }

  Future<void> openFolder(DriveFile folder) async {
    if (_busy || !_connected || !folder.isFolder || _disposed) return;
    final revision = ++_revision;
    _busy = true;
    _error = null;
    _notify();
    try {
      final entries = await _api.listFolder(
        folder.id,
        cancelled: () => revision != _revision || _disposed,
      );
      if (revision != _revision || _disposed) return;
      final existing = _path.indexWhere((f) => f.id == folder.id);
      _path = folder.id == 'root'
          ? []
          : existing >= 0
          ? _path.sublist(0, existing + 1)
          : [..._path, folder];
      _entries = entries;
    } catch (error) {
      if (revision == _revision && !_disposed) _recordError(error);
    } finally {
      if (revision == _revision && !_disposed) {
        _busy = false;
        _notify();
      }
    }
  }

  Future<bool> selectFolder([DriveFile? folder]) async {
    if (_busy || !_connected || _disposed) return false;
    final target = folder ?? currentFolder;
    final revision = ++_revision;
    _busy = true;
    _error = null;
    _notify();
    try {
      final scan = await _api.scanFolder(
        target.id,
        cancelled: () => revision != _revision || _disposed,
      );
      if (revision != _revision || _disposed) return false;
      await stop();
      if (revision != _revision || _disposed) return false;
      _selectedFolder = target;
      _shufflePlayed.clear();
      _history.clear();
      _tracks = scan.tracks;
      _files = scan.files;
      return true;
    } catch (error) {
      if (revision == _revision && !_disposed) _recordError(error);
      return false;
    } finally {
      if (revision == _revision && !_disposed) {
        _busy = false;
        _notify();
      }
    }
  }

  void cancelBrowse({bool deferNotification = false}) {
    if (_disposed) return;
    _platform.cancelAuthorization();
    _connected = _connectedBeforeAuthorization ?? _connected;
    _connectedBeforeAuthorization = null;
    _revision++;
    _busy = false;
    if (deferNotification) {
      scheduleMicrotask(_notify);
    } else {
      _notify();
    }
  }

  Future<void> disconnect() async {
    _connectedBeforeAuthorization = null;
    _revision++;
    _busy = false;
    _connected = false;
    _account = null;
    _entries = const [];
    _path = const [];
    _tracks = const [];
    _files = const {};
    _selectedFolder = null;
    _error = null;
    await stop();
    try {
      await _platform.disconnect();
    } catch (_) {
      _error = '已清除本次会话。撤销 Google 授权未完成，可在 Google 账户的第三方连接中移除云听。';
    }
    _notify();
  }

  void _onPlayback(DrivePlayback value) {
    if (_disposed || _ignorePlayback || value.id != _playback.id) return;
    if (value.completed && (_completionHandled || _playback.loading)) return;
    _playback = value;
    if (value.duration > Duration.zero) {
      _tracks = _tracks
          .map(
            (t) => t.id == value.id ? t.copyWith(duration: value.duration) : t,
          )
          .toList();
    }
    _notify();
    if (value.completed) {
      _completionHandled = true;
      // 先消费完成事件，避免播放器重复回报导致跳过多首。
      unawaited(
        _advance(completed: true).catchError((Object error) {
          _recordError(error);
          _notify();
        }),
      );
    }
  }

  Future<void> _play(String id) async {
    if (!_connected) {
      throw const DriveException(
        '请先重新连接 Google Drive。',
        requiresAuthorization: true,
      );
    }
    final file = _files[id];
    if (file == null) return;
    if (!file.canDownload) throw const DriveException('文件所有者未允许下载，此歌曲无法播放。');
    final revision = ++_playRevision;
    _ignorePlayback = true;
    _completionHandled = false;
    _error = null;
    _shufflePlayed.add(id);
    if (_history.isEmpty || _history.last != id) _history.add(id);
    _playback = DrivePlayback(id: id, loading: true);
    _notify();
    try {
      await _platform.stop();
      final token = await _accessToken();
      if (revision != _playRevision || _disposed) return;
      _ignorePlayback = false;
      await _platform.play(
        DriveAudioRequest(
          id: id,
          url: DriveApi.mediaUrl(file.id),
          accessToken: token,
          mimeType: file.mimeType,
          size: file.size,
        ),
      );
    } catch (error) {
      if (revision == _playRevision && !_disposed) {
        _ignorePlayback = false;
        _recordError(error);
        _playback = DrivePlayback(id: id, error: _error);
        _notify();
      }
    }
  }

  Future<void> _advance({
    bool backwards = false,
    bool completed = false,
  }) async {
    if (_tracks.isEmpty) return;
    final candidates = _tracks
        .where((t) => t.availability != TrackAvailability.unsupported)
        .toList();
    if (candidates.isEmpty) return;
    final index = candidates.indexWhere((t) => t.id == _playback.id);
    if (completed && _repeat == RepeatMode.one && index >= 0) {
      await _play(candidates[index].id);
      return;
    }
    if (backwards && _playback.position.inSeconds > 3) {
      await _platform.seek(Duration.zero);
      return;
    }
    var next = index + (backwards ? -1 : 1);
    if (_shuffle && backwards && _history.length > 1) {
      _history.removeLast();
      final previous = _history.removeLast();
      await _play(previous);
      return;
    } else if (_shuffle && candidates.length > 1) {
      var remaining = candidates
          .where((t) => !_shufflePlayed.contains(t.id))
          .toList();
      if (remaining.isEmpty) {
        if (completed && _repeat == RepeatMode.off) return;
        _shufflePlayed.clear();
        remaining = candidates.where((t) => t.id != _playback.id).toList();
      }
      await _play(remaining[_random.nextInt(remaining.length)].id);
      return;
    } else if (next < 0 || next >= candidates.length) {
      if (completed && _repeat == RepeatMode.off) return;
      next = backwards ? candidates.length - 1 : 0;
    }
    await _play(candidates[next].id);
  }

  Future<void> stop() async {
    _playRevision++;
    _ignorePlayback = true;
    _playback = const DrivePlayback();
    await _platform.stop();
    _notify();
  }

  @override
  Future<void> command(
    String method, [
    Map<String, Object?> arguments = const {},
  ]) async {
    switch (method) {
      case 'play':
        await _play(arguments['id'] as String);
      case 'togglePlayback':
        if (_playback.id == null) {
          await _advance();
        } else if (_playback.playing) {
          await _platform.pause();
        } else if (_playback.completed ||
            (_playback.error != null && !_playback.resumable)) {
          await _play(_playback.id!);
        } else {
          await _platform.resume();
        }
      case 'pause':
        if (_playback.loading) {
          await stop();
        } else {
          await _platform.pause();
        }
      case 'next':
        await _advance();
      case 'previous':
        await _advance(backwards: true);
      case 'cancelLoading':
        await stop();
      case 'seek':
        await _platform.seek(
          Duration(milliseconds: (arguments['positionMs'] as num).toInt()),
        );
      case 'setVolume':
        _volume = (arguments['volume'] as num).toDouble().clamp(0, 1);
        await _platform.setVolume(_volume);
        _notify();
      case 'setShuffle':
        _shuffle = arguments['enabled'] == true;
        _shufflePlayed.clear();
        if (_playback.id != null) _shufflePlayed.add(_playback.id!);
        _notify();
      case 'setRepeat':
        _repeat = RepeatMode.values.firstWhere(
          (m) => m.name == arguments['mode'],
          orElse: () => RepeatMode.off,
        );
        _notify();
      case 'refresh':
        if (_selectedFolder != null) await selectFolder(_selectedFolder);
    }
  }

  // ChangeNotifier 的同步 dispose 与网关接口的异步 dispose 使用同一实现。
  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _revision++;
    _playRevision++;
    await _playbackSubscription.cancel();
    await _platform.dispose();
    _api.dispose();
    await _events.close();
    super.dispose();
  }
}
