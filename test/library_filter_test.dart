import 'dart:async';
import 'dart:convert';

import 'package:cloud_music/library_filter/filter_store.dart';
import 'package:cloud_music/library_filter/filter_store_native.dart';
import 'package:cloud_music/library_filter/library_filter.dart';
import 'package:cloud_music/models.dart';
import 'package:cloud_music/music_controller.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'controller_test.dart' show FakeGateway;

class MemoryFilterStore implements FilterStore {
  String? value;
  bool failRead = false, failWrite = false;
  int writes = 0;
  Completer<String?>? pendingRead;
  Completer<void>? pendingWrite;
  @override
  Future<String?> read() async {
    if (failRead) throw StateError('Read unavailable');
    return pendingRead == null ? value : pendingRead!.future;
  }

  @override
  Future<void> write(String next) async {
    writes++;
    if (failWrite) throw StateError('Write unavailable');
    await pendingWrite?.future;
    value = next;
  }
}

const filterTracks = [
  Track(
    id: 'clip',
    title: 'Short clip',
    duration: Duration(seconds: 12),
    album: 'Clips',
    artist: 'Clip artist',
  ),
  Track(
    id: 'edge',
    title: 'Boundary song',
    duration: Duration(seconds: 30),
    album: 'Album',
    artist: 'Artist',
  ),
  Track(
    id: 'long',
    title: 'Long song',
    duration: Duration(minutes: 3),
    album: 'Album',
    artist: 'Artist',
  ),
  Track(
    id: 'unknown',
    title: 'Unknown cloud song',
    availability: TrackAvailability.cloud,
  ),
];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'default is strict 30 seconds; unknown, invalid and exact boundary stay',
    () {
      final filter = LibraryFilter(store: MemoryFilterStore());
      expect(filter.visibleTracks(filterTracks).map((t) => t.id), [
        'edge',
        'long',
        'unknown',
      ]);
      expect(
        filter.hides(
          const Track(id: 'n', title: 'n', duration: Duration(seconds: -1)),
        ),
        false,
      );
      expect(
        filter.hides(
          const Track(
            id: 'm',
            title: 'm',
            duration: Duration(milliseconds: 29999),
          ),
        ),
        true,
      );
      expect(filterTracks.length, 4);
      filter.dispose();
    },
  );
  test(
    'threshold and off survive reload, off preserves chosen threshold',
    () async {
      final store = MemoryFilterStore();
      final filter = LibraryFilter(store: store);
      await filter.update(enabled: true, minimumSeconds: 60);
      expect(filter.visibleTracks(filterTracks).map((t) => t.id), [
        'long',
        'unknown',
      ]);
      await filter.update(enabled: false, minimumSeconds: 60);
      final restored = LibraryFilter(store: store);
      await restored.initialize();
      expect(restored.enabled, false);
      expect(restored.minimumSeconds, 60);
      expect(restored.visibleTracks(filterTracks), filterTracks);
      filter.dispose();
      restored.dispose();
    },
  );
  test(
    'slow load cannot replace new user choice; rapid writes stay ordered',
    () async {
      final store = MemoryFilterStore()
        ..pendingRead = Completer()
        ..pendingWrite = Completer();
      final filter = LibraryFilter(store: store);
      final load = filter.initialize();
      final first = filter.update(enabled: false, minimumSeconds: 90);
      final second = filter.update(enabled: true, minimumSeconds: 120);
      store.pendingRead!.complete(
        '{"version":1,"enabled":true,"minimumSeconds":10}',
      );
      await load;
      await Future<void>.delayed(Duration.zero);
      expect(filter.minimumSeconds, 120);
      expect(store.writes, 1);
      store.pendingWrite!.complete();
      await Future.wait([first, second]);
      expect(jsonDecode(store.value!)['minimumSeconds'], 120);
      expect(jsonDecode(store.value!)['enabled'], true);
      filter.dispose();
    },
  );
  test(
    'storage failure keeps session setting and later writes recover',
    () async {
      final store = MemoryFilterStore()
        ..failRead = true
        ..failWrite = true;
      final filter = LibraryFilter(store: store);
      await filter.initialize();
      expect(filter.notice, contains('无法读取'));
      await filter.update(enabled: false, minimumSeconds: 60);
      expect(filter.enabled, false);
      expect(filter.notice, contains('无法保存'));
      store.failWrite = false;
      await filter.update(enabled: true, minimumSeconds: 90);
      expect(filter.notice, isNull);
      expect(jsonDecode(store.value!)['minimumSeconds'], 90);
      filter.dispose();
    },
  );
  test(
    'older delayed save failure cannot leave a warning after newer success',
    () async {
      final store = MemoryFilterStore()..pendingWrite = Completer();
      final filter = LibraryFilter(store: store);
      final first = filter.update(enabled: true, minimumSeconds: 45);
      await Future<void>.delayed(Duration.zero);
      final second = filter.update(enabled: false, minimumSeconds: 60);
      await Future<void>.delayed(Duration.zero);
      final failed = store.pendingWrite!;
      store.pendingWrite = null;
      failed.completeError(StateError('old write failed'));
      await Future.wait([first, second]);
      expect(filter.notice, isNull);
      expect(jsonDecode(store.value!)['minimumSeconds'], 60);
      filter.dispose();
    },
  );
  test(
    'malformed/out-of-range saved preferences safely use defaults',
    () async {
      for (final raw in [
        'no json',
        '{}',
        '{"version":1,"enabled":true,"minimumSeconds":0}',
        '{"version":1,"enabled":true,"minimumSeconds":601}',
        '{"version":1,"enabled":true,"minimumSeconds":30.5}',
      ]) {
        final filter = LibraryFilter(store: MemoryFilterStore()..value = raw);
        await filter.initialize();
        expect(filter.enabled, true);
        expect(filter.minimumSeconds, 30);
        expect(filter.notice, isNotNull);
        filter.dispose();
      }
      final filter = LibraryFilter(store: MemoryFilterStore());
      await expectLater(
        filter.update(enabled: true, minimumSeconds: 0),
        throwsArgumentError,
      );
      await expectLater(
        filter.update(enabled: true, minimumSeconds: 601),
        throwsArgumentError,
      );
      filter.dispose();
    },
  );
  test('all sources filter display only; metadata update never issues audio commands', () async {
    final gateway = FakeGateway();
    final filter = LibraryFilter(store: MemoryFilterStore());
    final c = MusicController(gateway: gateway, libraryFilter: filter);
    await c.initialize();
    for (final source in ['apple', 'android', 'web', 'googleDrive']) {
      gateway.events.add(
        LibrarySnapshot(
          sourceKind: source,
          tracks: filterTracks,
          currentTrackId: 'clip',
          isPlaying: true,
        ),
      );
      expect(filter.visibleTracks(c.snapshot.tracks).length, 3);
      expect(c.snapshot.tracks, filterTracks);
      expect(c.snapshot.currentTrack?.id, 'clip');
      expect(c.snapshot.isPlaying, true);
      await filter.update(enabled: false, minimumSeconds: 30);
      expect(filter.visibleTracks(c.snapshot.tracks).length, 4);
      await filter.update(enabled: true, minimumSeconds: 30);
      gateway.events.add(
        LibrarySnapshot(
          sourceKind: source,
          tracks: [
            filterTracks.last.copyWith(duration: const Duration(seconds: 5)),
          ],
        ),
      );
      expect(filter.visibleTracks(c.snapshot.tracks), isEmpty);
    }
    expect(gateway.calls, isEmpty);
    c.dispose();
  });
  test('disposing during storage read cannot notify dead listeners', () async {
    final store = MemoryFilterStore()..pendingRead = Completer();
    final filter = LibraryFilter(store: store);
    final pending = filter.update(enabled: false, minimumSeconds: 60);
    filter.dispose();
    store.pendingRead!.complete(null);
    await pending;
    expect(store.writes, 0);
  });
  test('native preferences use dedicated local storage methods', () async {
    const channel = MethodChannel('test-filter-store');
    final calls = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
          return call.method.startsWith('read') ? 'saved' : null;
        });
    final store = NativeFilterStore(channel: channel);
    expect(await store.read(), 'saved');
    await store.write('new');
    expect(calls.map((c) => c.method), [
      'readLibraryFilter',
      'writeLibraryFilter',
    ]);
    expect(calls.last.arguments, {'value': 'new'});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });
}
