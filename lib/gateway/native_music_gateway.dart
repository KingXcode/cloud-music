import 'package:flutter/services.dart';

import '../models.dart';
import 'music_gateway.dart';

class NativeMusicGateway implements MusicGateway {
  NativeMusicGateway({MethodChannel? methods, EventChannel? events})
    : _methods = methods ?? const MethodChannel('cloud_music/control'),
      _events = events ?? const EventChannel('cloud_music/events');
  final MethodChannel _methods;
  final EventChannel _events;
  late final Stream<LibrarySnapshot> _snapshots = _events
      .receiveBroadcastStream()
      .map(
        (event) =>
            LibrarySnapshot.fromMap(Map<Object?, Object?>.from(event as Map)),
      );
  @override
  Stream<LibrarySnapshot> get snapshots => _snapshots;
  @override
  Future<LibrarySnapshot> initialize() async {
    final value = await _methods.invokeMapMethod<Object?, Object?>(
      'initialize',
    );
    return LibrarySnapshot.fromMap(value ?? const {});
  }

  @override
  Future<void> command(
    String method, [
    Map<String, Object?> arguments = const {},
  ]) async {
    await _methods.invokeMethod<Object?>(method, arguments);
  }

  @override
  Future<void> dispose() async {}
}
