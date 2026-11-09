import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'gateway/music_gateway.dart';
import 'gateway/source_music_gateway.dart';
import 'drive/drive_gateway.dart';
import 'models.dart';
import 'lyrics/lyrics_controller.dart';
import 'library_filter/library_filter.dart';

class MusicController extends ChangeNotifier {
  // 公开的注入参数名有意与私有字段名区分。
  MusicController({
    required MusicGateway gateway,
    LyricsController? lyrics,
    LibraryFilter? libraryFilter,
  })
    // ignore: prefer_initializing_formals
    : _gateway = gateway,
       lyrics = lyrics ?? LyricsController(),
       libraryFilter = libraryFilter ?? LibraryFilter() {
    this.libraryFilter.addListener(_filterChanged);
  }
  final LyricsController lyrics;
  final LibraryFilter libraryFilter;
  void _filterChanged() {
    if (!_disposed) notifyListeners();
  }

  final MusicGateway _gateway;
  DriveGateway? get drive =>
      _gateway is SourceMusicGateway ? _gateway.drive : null;
  bool get usingDrive => _gateway is SourceMusicGateway && _gateway.usingDrive;
  LibrarySnapshot get _localSnapshot =>
      _gateway is SourceMusicGateway ? _gateway.localSnapshot : _snapshot;
  bool get isLocalImportScanning => _gateway is SourceMusicGateway
      ? _gateway.isLocalImportScanning
      : _snapshot.sourceKind == 'android' && _snapshot.isScanning;
  String? get localImportMessage => _gateway is SourceMusicGateway && usingDrive
      ? _gateway.localImportMessage
      : null;
  Future<void> cancelLocalImport() => _command(
    _gateway is SourceMusicGateway ? 'cancelLocalImport' : 'cancelLoading',
  );
  bool get canPickFiles => _localSnapshot.canPickFiles;
  bool get canScanDevice => _localSnapshot.canScanDevice;
  bool get selectsFiles => _localSnapshot.selectsFiles;
  Future<void> useDriveFolder() => _command('driveUseFolder');
  Future<void> disconnectDrive() => _command('driveDisconnect');
  Future<void> useLocalSource() => _command('useLocal');
  LibrarySnapshot _snapshot = const LibrarySnapshot();
  LibrarySnapshot get snapshot => _snapshot;
  String? _error;
  String? get error =>
      _error ??
      (usingDrive && !isLocalImportScanning ? localImportMessage : null);
  bool _initialized = false,
      _choosingFolder = false,
      _refreshing = false,
      _disposed = false;
  int _eventRevision = 0;
  bool get initialized => _initialized;
  bool get isBusy =>
      !_initialized ||
      _choosingFolder ||
      _refreshing ||
      _snapshot.isScanning ||
      isLocalImportScanning;
  Future<void>? _initialization;
  StreamSubscription<LibrarySnapshot>? _subscription;

  Future<void> initialize() => _initialization ??= _initialize();
  Future<void> _initialize() async {
    final revision = _eventRevision;
    unawaited(lyrics.initialize());
    final filterLoaded = libraryFilter.initialize();
    _subscription = _gateway.snapshots.listen(
      (value) {
        if (_disposed) return;
        _eventRevision++;
        _snapshot = value;
        _selectLyricsTrack();
        notifyListeners();
      },
      onError: (Object error) {
        _showError(error);
      },
    );
    try {
      final initial = await _gateway.initialize();
      if (!_disposed && revision == _eventRevision) {
        _snapshot = initial;
        _selectLyricsTrack();
      }
    } catch (error) {
      _showError(error);
    } finally {
      await filterLoaded;
      if (!_disposed) {
        _initialized = true;
        notifyListeners();
      }
    }
  }

  void _selectLyricsTrack() => lyrics.selectTrack(
    _snapshot.currentTrack,
    source: _snapshot.sourceKind,
    sourceIdentity: _snapshot.sourceIdentity,
    folder: _snapshot.folderName ?? '',
  );

  Future<void> pickFolder() => _selectLocal('pickFolder');
  Future<void> pickFiles() => _selectLocal('pickFiles');
  Future<void> scanDevice() => _selectLocal('scanDevice');

  Future<void> _selectLocal(String method) async {
    if (isBusy) return;
    _choosingFolder = true;
    notifyListeners();
    await _command(method);
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
    if (_gateway is SourceMusicGateway) _gateway.clearLocalImportMessage();
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
    libraryFilter.removeListener(_filterChanged);
    libraryFilter.dispose();
    lyrics.dispose();
    unawaited(_subscription?.cancel());
    unawaited(_gateway.dispose());
    super.dispose();
  }
}
