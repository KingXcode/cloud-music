import 'dart:async';
import 'dart:js_interop';

import '../models.dart';
import 'music_gateway.dart';

@JS('createCloudMusicGateway')
external _BrowserGateway _createGateway(JSFunction listener);

extension type _BrowserGateway(JSObject _) implements JSObject {
  external JSPromise<JSAny?> initialize();
  external JSPromise<JSAny?> command(JSString method, JSObject arguments);
  external void dispose();
}

/// Uses browser-owned file references. Audio bytes never enter Dart or storage.
class WebMusicGateway implements MusicGateway {
  WebMusicGateway() {
    _browser = _createGateway(
      ((JSAny? value) {
        if (!_events.isClosed) _events.add(_decode(value));
      }).toJS,
    );
  }

  final _events = StreamController<LibrarySnapshot>.broadcast();
  late final _BrowserGateway _browser;
  bool _disposed = false;

  LibrarySnapshot _decode(JSAny? value) => LibrarySnapshot.fromMap(
    Map<Object?, Object?>.from(value.dartify()! as Map),
  );

  @override
  Stream<LibrarySnapshot> get snapshots => _events.stream;

  @override
  Future<LibrarySnapshot> initialize() async =>
      _decode(await _browser.initialize().toDart);

  @override
  Future<void> command(
    String method, [
    Map<String, Object?> arguments = const {},
  ]) async {
    if (_disposed) return;
    await _browser.command(method.toJS, arguments.jsify()! as JSObject).toDart;
  }

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _browser.dispose();
    await _events.close();
  }
}
