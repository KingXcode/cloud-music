import 'dart:js_interop';

import 'update_backend.dart';

@JS('cloudMusicUpdates')
external _BrowserUpdates get _updates;

extension type _BrowserUpdates(JSObject _) implements JSObject {
  external JSObject getInstalledVersion();
  external JSPromise<JSAny?> check();
  external JSPromise<JSAny?> download(JSString id, JSFunction onProgress);
  external JSPromise<JSAny?> install(JSString id);
  external void cancel();
}

UpdateBackend createPlatformUpdateBackend() => WebUpdateBackend();

class WebUpdateBackend implements UpdateBackend {
  @override
  Future<void> openReleasePage(UpdateRelease release) async {
    throw const UpdateException('网页版请使用网页更新。');
  }

  String? _releaseId;
  UpdateRelease? _release;
  int _generation = 0;
  bool _disposed = false;

  @override
  Future<InstalledVersion> getInstalledVersion() async {
    final value = _updates.getInstalledVersion().dartify()! as Map;
    return InstalledVersion(
      version: value['version'] as String,
      build: value['build'] as String,
      platform: 'web',
      architecture: 'browser',
    );
  }

  @override
  Future<UpdateRelease?> check(InstalledVersion current) async {
    try {
      final value = (await _updates.check().toDart).dartify();
      if (value == null) return null;
      final map = value as Map;
      _releaseId = map['id'] as String;
      final release = UpdateRelease(
        version: map['version'] as String,
        build: map['build'] as String,
        notes: map['notes'] as String,
        releasePage: Uri.parse(map['releasePage'] as String),
        asset: UpdateAsset(
          name: '网页离线资源',
          url: Uri.parse(map['url'] as String),
          size: (map['size'] as num).toInt(),
          // Individual resources are SHA-256 verified by the service worker.
          sha256: '',
        ),
      );
      _release = release;
      return release;
    } catch (error) {
      throw UpdateException(_message(error));
    }
  }

  String _id(UpdateRelease release) {
    if (_release != release || _releaseId == null) {
      throw const UpdateException('请重新检查更新。');
    }
    return _releaseId!;
  }

  @override
  Future<void> download(
    UpdateRelease release,
    void Function(int received, int? total) onProgress,
  ) async {
    final generation = ++_generation;
    try {
      await _updates
          .download(
            _id(release).toJS,
            ((JSNumber received, JSNumber total) {
              if (generation == _generation && !_disposed) {
                onProgress(received.toDartInt, total.toDartInt);
              }
            }).toJS,
          )
          .toDart;
      if (generation != _generation) throw const UpdateCancelled();
    } on UpdateCancelled {
      rethrow;
    } catch (error) {
      if (generation != _generation) throw const UpdateCancelled();
      throw UpdateException(_message(error));
    }
  }

  @override
  Future<String> install(UpdateRelease release) async {
    try {
      await _updates.install(_id(release).toJS).toDart;
      return 'opened';
    } catch (error) {
      throw UpdateException(_message(error));
    }
  }

  @override
  void cancel() {
    ++_generation;
    _updates.cancel();
  }

  @override
  void dispose() {
    _disposed = true;
    cancel();
  }

  String _message(Object error) => error.toString().replaceFirst('Error: ', '');
}
