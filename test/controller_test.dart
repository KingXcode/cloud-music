import 'dart:async';

import 'package:cloud_music/gateway/music_gateway.dart';
import 'package:cloud_music/models.dart';
import 'package:cloud_music/music_controller.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

class FakeGateway implements MusicGateway {
  final events = StreamController<LibrarySnapshot>.broadcast(sync: true);
  final calls = <(String, Map<String, Object?>)>[];
  LibrarySnapshot initial = const LibrarySnapshot();
  Completer<LibrarySnapshot>? initialPending;
  Completer<void>? commandPending;
  Object? failure;
  @override
  Stream<LibrarySnapshot> get snapshots => events.stream;
  @override
  Future<LibrarySnapshot> initialize() async =>
      initialPending == null ? initial : initialPending!.future;
  @override
  Future<void> command(
    String method, [
    Map<String, Object?> arguments = const {},
  ]) async {
    calls.add((method, arguments));
    if (failure != null) throw failure!;
    await commandPending?.future;
  }

  @override
  Future<void> dispose() => events.close();
}

void main() {
  test('row selection sends the exact track ID', () async {
    final gateway = FakeGateway();
    final controller = MusicController(gateway: gateway);
    await controller.initialize();
    await controller.play(const Track(id: 'folder/B.mp3', title: 'B'));
    expect(gateway.calls.single.$1, 'play');
    expect(gateway.calls.single.$2, {'id': 'folder/B.mp3'});
    controller.dispose();
  });
  test('newer event wins over slower initial snapshot', () async {
    final gateway = FakeGateway()..initialPending = Completer();
    final controller = MusicController(gateway: gateway);
    final pending = controller.initialize();
    gateway.events.add(const LibrarySnapshot(folderName: 'new'));
    gateway.initialPending!.complete(const LibrarySnapshot(folderName: 'old'));
    await pending;
    expect(controller.snapshot.folderName, 'new');
    controller.dispose();
  });
  test('cancelled picker does not clear existing library and duplicate picker is ignored', () async {
    final gateway = FakeGateway()
      ..initial = const LibrarySnapshot(
        folderName: 'Music',
        tracks: [Track(id: 'a', title: 'A')],
      )
      ..commandPending = Completer<void>();
    final controller = MusicController(gateway: gateway);
    await controller.initialize();
    final pending = controller.pickFolder();
    await controller.pickFolder();
    expect(gateway.calls.length, 1);
    expect(controller.snapshot.tracks.length, 1);
    gateway.commandPending!.complete();
    await pending;
    expect(controller.snapshot.folderName, 'Music');
    expect(controller.isBusy, false);
    controller.dispose();
  });
  test('seek and volume clamp without mutating the track list', () async {
    final gateway = FakeGateway()
      ..initial = const LibrarySnapshot(duration: Duration(seconds: 10));
    final controller = MusicController(gateway: gateway);
    await controller.initialize();
    await controller.seek(const Duration(seconds: 40));
    await controller.setVolume(-1);
    expect(gateway.calls[0].$1, 'seek');
    expect(gateway.calls[0].$2, {'positionMs': 10000});
    expect(gateway.calls[1].$1, 'setVolume');
    expect(gateway.calls[1].$2, {'volume': 0.0});
    controller.dispose();
  });
  test(
    'permission failure surfaces explanation and preserves tracks',
    () async {
      final gateway = FakeGateway()
        ..initial = const LibrarySnapshot(
          tracks: [Track(id: 'a', title: 'A')],
        )
        ..failure = PlatformException(code: 'access', message: '请重新授权目录');
      final controller = MusicController(gateway: gateway);
      await controller.initialize();
      await controller.refresh();
      expect(controller.error, '请重新授权目录');
      expect(controller.snapshot.tracks.length, 1);
      expect(controller.isBusy, false);
      controller.dispose();
    },
  );
}
