import 'dart:async';

import '../drive/drive_gateway.dart';
import '../models.dart';
import 'music_gateway.dart';

/// 各来源独立保留会话；一次只让一个播放器活动。
class SourceMusicGateway implements MusicGateway {
  SourceMusicGateway({required MusicGateway local, required this.drive})
    // ignore: prefer_initializing_formals
    : _local = local {
    _localSubscription = _local.snapshots.listen((s) {
      _localRevision++;
      _localSnapshot = s;
      if (_disposed) return;
      if (_pendingLocalImport) {
        _localImportMessage = s.message;
        if (s.importRevision > _importBaseline &&
            !s.isScanning &&
            s.tracks.isNotEmpty) {
          _pendingLocalImport = false;
          _localImportMessage = null;
          unawaited(_commitLocalImport(_selectionRevision));
        } else {
          // Progress/errors from an inactive local source must not replace Drive.
          _events.add(_usingDrive ? drive.snapshot : s);
        }
      } else if (!_usingDrive) {
        _events.add(s);
      }
    }, onError: _events.addError);
    _driveSubscription = drive.snapshots.listen((s) {
      if (_usingDrive && !_disposed) _events.add(s);
    }, onError: _events.addError);
  }
  final MusicGateway _local;
  final DriveGateway drive;
  final _events = StreamController<LibrarySnapshot>.broadcast(sync: true);
  late final StreamSubscription<LibrarySnapshot> _localSubscription,
      _driveSubscription;
  LibrarySnapshot _localSnapshot = const LibrarySnapshot();
  bool _usingDrive = false, _disposed = false;
  int _selectionRevision = 0, _localRevision = 0, _importBaseline = 0;
  bool _pendingLocalImport = false;
  String? _localImportMessage;
  bool get isLocalImportScanning =>
      _pendingLocalImport && _localSnapshot.isScanning;
  String? get localImportMessage => _localImportMessage;
  void clearLocalImportMessage() {
    _localImportMessage = null;
  }

  Future<void> _commitLocalImport(int revision) async {
    if (_disposed || revision != _selectionRevision) return;
    try {
      if (_usingDrive) await drive.stop();
      if (_disposed || revision != _selectionRevision) return;
      _usingDrive = false;
      _localImportMessage = null;
      _events.add(_localSnapshot);
    } catch (error, stack) {
      if (!_disposed && revision == _selectionRevision) {
        _events.addError(error, stack);
      }
    }
  }

  bool get usingDrive => _usingDrive;
  LibrarySnapshot get localSnapshot => _localSnapshot;
  @override
  Stream<LibrarySnapshot> get snapshots => _events.stream;
  @override
  Future<LibrarySnapshot> initialize() async {
    final revision = _localRevision;
    final initial = await _local.initialize();
    if (revision == _localRevision) _localSnapshot = initial;
    // 没有配置客户端时仍可正常使用系统文件，不自动登录或发送授权请求。
    await drive.initialize();
    return _localSnapshot;
  }

  @override
  Future<void> command(
    String method, [
    Map<String, Object?> arguments = const {},
  ]) async {
    if (_disposed) return;
    switch (method) {
      case 'driveUseFolder':
        _pendingLocalImport = false;
        _localImportMessage = null;
        final revision = ++_selectionRevision;
        if (await drive.selectFolder() &&
            revision == _selectionRevision &&
            !_disposed) {
          final browseRevision = drive.browseRevision;
          await _local.command('pause');
          if (revision != _selectionRevision ||
              _disposed ||
              browseRevision != drive.browseRevision) {
            return;
          }
          _usingDrive = true;
          _events.add(drive.snapshot);
        }
      case 'driveDisconnect':
        _pendingLocalImport = false;
        _localImportMessage = null;
        final revision = ++_selectionRevision;
        await drive.disconnect();
        if (_disposed || revision != _selectionRevision) return;
        _usingDrive = false;
        _events.add(_localSnapshot);
      case 'useLocal':
        _pendingLocalImport = false;
        _localImportMessage = null;
        final revision = ++_selectionRevision;
        drive.cancelBrowse();
        await drive.stop();
        if (_disposed || revision != _selectionRevision) return;
        _usingDrive = false;
        _events.add(_localSnapshot);
      case 'pickFolder':
      case 'pickFiles':
      case 'scanDevice':
        final revision = ++_selectionRevision;
        _pendingLocalImport = true;
        _importBaseline = _localSnapshot.importRevision;
        _localImportMessage = null;
        drive.cancelBrowse();
        // Invoke immediately, inside the trusted click. Picker completion can
        // arrive through a later event; the returned Future is not acceptance.
        try {
          await _local.command(method, arguments);
        } catch (_) {
          if (revision == _selectionRevision) _pendingLocalImport = false;
          rethrow;
        }
      case 'cancelLocalImport':
        ++_selectionRevision;
        _pendingLocalImport = false;
        _localImportMessage = null;
        await _local.command('cancelImport');
        if (!_disposed) {
          _events.add(_usingDrive ? drive.snapshot : _localSnapshot);
        }
      default:
        await (_usingDrive ? drive : _local).command(method, arguments);
    }
  }

  @override
  Future<void> dispose() async {
    _disposed = true;
    await _localSubscription.cancel();
    await _driveSubscription.cancel();
    await drive.dispose();
    await _local.dispose();
    await _events.close();
  }
}
