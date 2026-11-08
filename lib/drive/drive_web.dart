import 'dart:async';
import 'dart:js_interop';

import 'drive_api.dart';
import 'drive_platform.dart';

@JS('createGoogleDrivePlatform')
external _BrowserDrive _createDrive(JSString clientId, JSFunction listener);

extension type _BrowserDrive(JSObject _) implements JSObject {
  external JSPromise<JSAny?> initialize();
  external JSPromise<JSAny?> authorizeResult(JSBoolean interactive);
  external void cancelAuthorization();
  external JSPromise<JSAny?> disconnect();
  external JSPromise<JSAny?> play(JSObject request);
  external JSPromise<JSAny?> pause();
  external JSPromise<JSAny?> resume();
  external JSPromise<JSAny?> seek(JSNumber seconds);
  external JSPromise<JSAny?> setVolume(JSNumber value);
  external JSPromise<JSAny?> stop();
  external JSPromise<JSAny?> dispose();
}

DrivePlatform createDrivePlatform() => WebDrivePlatform();

class WebDrivePlatform implements DrivePlatform {
  WebDrivePlatform() {
    _browser = _createDrive(
      _clientId.toJS,
      ((JSAny? event) {
        if (_events.isClosed) return;
        final map = event.dartify()! as Map;
        _events.add(
          DrivePlayback(
            id: map['id'] as String?,
            playing: map['playing'] == true,
            loading: map['loading'] == true,
            completed: map['completed'] == true,
            resumable: map['resumable'] == true,
            position: Duration(
              milliseconds: (((map['position'] as num?) ?? 0) * 1000).round(),
            ),
            duration: Duration(
              milliseconds: (((map['duration'] as num?) ?? 0) * 1000).round(),
            ),
            error: map['error'] as String?,
          ),
        );
      }).toJS,
    );
  }
  static const _clientId = String.fromEnvironment('GOOGLE_DRIVE_WEB_CLIENT_ID');
  late final _BrowserDrive _browser;
  final _events = StreamController<DrivePlayback>.broadcast();
  bool _disposed = false;
  @override
  bool get configured =>
      _clientId.endsWith('.apps.googleusercontent.com') &&
      !_clientId.contains(RegExp(r'\s'));
  @override
  String get setupMessage =>
      '需配置 GOOGLE_DRIVE_WEB_CLIENT_ID，并在 Google Cloud 中启用 Drive API、配置 OAuth 同意屏幕和当前网页的授权 JavaScript 来源。';
  @override
  String get playbackNotice =>
      '网页版会把当前整首歌曲缓冲到内存后播放（最多 100 MiB），不是分段流式播放；停止或切歌会释放缓冲。Google Drive 只读权限可读取账号内文件，应用只索引所选文件夹，不保存访问令牌。';
  @override
  Stream<DrivePlayback> get playback => _events.stream;
  @override
  Future<void> initialize() async {
    await _browser.initialize().toDart;
  }

  @override
  Future<DriveAuthorization?> authorize({bool interactive = false}) async {
    final result = (await _browser.authorizeResult(interactive.toJS).toDart)
        .dartify();
    if (result == null) return null;
    final map = result as Map;
    if (map['error'] case final String message) {
      throw DriveException(message, requiresAuthorization: true);
    }
    return DriveAuthorization(
      map['accessToken'] as String,
      expiresAt: DateTime.fromMillisecondsSinceEpoch(
        (map['expiresAt'] as num).round(),
      ),
    );
  }

  @override
  void cancelAuthorization() {
    _browser.cancelAuthorization();
  }

  @override
  Future<void> disconnect() async {
    await _browser.disconnect().toDart;
  }

  @override
  Future<void> play(DriveAudioRequest request) async {
    await _browser
        .play(
          {
                'id': request.id,
                'fileId': Uri.parse(request.url).pathSegments.last,
                'accessToken': request.accessToken,
                'mimeType': request.mimeType,
                'size': request.size,
              }.jsify()!
              as JSObject,
        )
        .toDart;
  }

  @override
  Future<void> pause() async {
    await _browser.pause().toDart;
  }

  @override
  Future<void> resume() async {
    await _browser.resume().toDart;
  }

  @override
  Future<void> seek(Duration position) async {
    await _browser.seek((position.inMilliseconds / 1000).toJS).toDart;
  }

  @override
  Future<void> setVolume(double value) async {
    await _browser.setVolume(value.toJS).toDart;
  }

  @override
  Future<void> stop() async {
    await _browser.stop().toDart;
  }

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    await _browser.dispose().toDart;
    await _events.close();
  }
}
