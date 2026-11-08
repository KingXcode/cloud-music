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
      if (!_usingDrive && !_disposed) _events.add(s);
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
  int _selectionRevision = 0, _localRevision = 0;
  bool get usingDrive => _usingDrive;
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
        final revision = ++_selectionRevision;
        await drive.disconnect();
        if (_disposed || revision != _selectionRevision) return;
        _usingDrive = false;
        _events.add(_localSnapshot);
      case 'useLocal':
        final revision = ++_selectionRevision;
        drive.cancelBrowse();
        await drive.stop();
        if (_disposed || revision != _selectionRevision) return;
        _usingDrive = false;
        _events.add(_localSnapshot);
      case 'pickFolder':
        final revision = ++_selectionRevision;
        drive.cancelBrowse();
        await drive.stop();
        if (_disposed || revision != _selectionRevision) return;
        _usingDrive = false;
        _events.add(_localSnapshot);
        await _local.command(method, arguments);
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
