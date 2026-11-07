import 'dart:async';
import 'dart:convert';

import 'package:cloud_music/lyrics/lyrics_controller.dart';
import 'package:cloud_music/lyrics/lyrics_models.dart';
import 'package:cloud_music/lyrics/lyrics_platform.dart';
import 'package:cloud_music/models.dart';
import 'package:flutter_test/flutter_test.dart';

class FakeLyricsPlatform implements LyricsPlatform {
  String? cache, imported;
  Object? readFailure, writeFailure, importFailure, httpFailure;
  final queries = <Uri>[];
  final writes = <String>[];
  Completer<LyricsHttpResponse>? pending;
  Completer<String?>? pendingRead, pendingImport;
  LyricsHttpResponse response = const LyricsHttpResponse(200, '[]');
  bool disposed = false;
  @override
  Future<LyricsHttpResponse> get(Uri uri) async {
    queries.add(uri);
    if (httpFailure != null) throw httpFailure!;
    return pending == null ? response : pending!.future;
  }

  @override
  Future<String?> readCache() async {
    if (readFailure != null) throw readFailure!;
    return pendingRead == null ? cache : pendingRead!.future;
  }

  @override
  Future<void> writeCache(String value) async {
    if (writeFailure != null) throw writeFailure!;
    cache = value;
    writes.add(value);
  }

  @override
  Future<String?> importFile() async {
    if (importFailure != null) throw importFailure!;
    return pendingImport == null ? imported : pendingImport!.future;
  }

  @override
  void dispose() {
    disposed = true;
  }
}

const a = Track(
  id: 'local/a.mp3',
  title: 'Test Meadow',
  artist: 'Test Singer',
  album: 'Test Album',
);
const b = Track(id: 'local/b.mp3', title: 'Test Rain', artist: 'Test Singer');
String records({
  String? synced = '[00:01.00]One invented line\n[00:03.00]Two invented lines',
  String? plain,
  bool instrumental = false,
}) => jsonEncode([
  {
    'id': 1,
    'trackName': 'Test Meadow',
    'artistName': 'Test Singer',
    'albumName': 'Test Album',
    'duration': 120.5,
    'syncedLyrics': synced,
    'plainLyrics': plain,
    'instrumental': instrumental,
  },
]);

void main() {
  group('LRC parsing', () {
    test(
      'BOM, metadata, fractions, multiple timestamps, grouping and sorting',
      () {
        final doc = LyricsDocument.parse(
          '\uFEFF[ar:Someone]\r\n[ti:Example]\r\n[00:10.5][00:03.050]Repeat\r\n[00:03.05]Translation\n[00:02]Start\n[00:12.123]End',
        );
        expect(doc.isSynced, true);
        expect(doc.lines.map((l) => l.time.inMilliseconds), [
          2000,
          3050,
          10500,
          12123,
        ]);
        expect(doc.lines[1].text, 'Repeat\nTranslation');
        expect(doc.activeLineIndex(Duration.zero), -1);
        expect(doc.activeLineIndex(const Duration(milliseconds: 3050)), 1);
        expect(doc.activeLineIndex(const Duration(seconds: 100)), 3);
        expect(doc.activeLineIndex(const Duration(seconds: 2)), 0);
      },
    );
    test('offset advances lyrics, preserves blank cues and supports hours', () {
      final doc = LyricsDocument.parse(
        '[offset:500]\n[00:01.00]Start\n[00:02.00]\n[01:02:03.250]End',
      );
      expect(doc.lines[0].time.inMilliseconds, 500);
      expect(doc.lines[1].text, '');
      expect(doc.lines[2].time.inMilliseconds, 3722750);
      expect(
        LyricsDocument.parse('[offset:-250]\n[00:01]X')
            .lines
            .single
            .time
            .inMilliseconds,
        1250,
      );
    });
    test(
      'invalid timestamps degrade to text and plain fallback is preferred',
      () {
        expect(LyricsDocument.parse('[00:75]Bad timestamp').isSynced, false);
        final doc = LyricsDocument.parse(
          '[ar:Header]\n[00:01]',
          plainFallback: 'Readable words',
        );
        expect(doc.isSynced, false);
        expect(doc.text, 'Readable words');
        expect(LyricsDocument.parse('One\r\nTwo').text, 'One\nTwo');
      },
    );
    test(
      'instrumental is explicit but real lyric content takes precedence',
      () {
        expect(LyricsDocument.parse('', instrumental: true).instrumental, true);
        expect(
          LyricsDocument.parse('Some text', instrumental: true).instrumental,
          false,
        );
        expect(LyricsDocument.parse('[ar:Only metadata]').isEmpty, true);
      },
    );
    test('bounds oversized UTF-8 and timestamp expansion', () {
      expect(() => LyricsDocument.parse('测' * 100000), throwsFormatException);
      expect(
        () => LyricsDocument.parse('${'[00:01]' * 5001}X'),
        throwsFormatException,
      );
    });
    test('colon centiseconds cannot be mistaken for hour timestamps', () {
      final doc = LyricsDocument.parse(
        '[00:01:50]First\n[03:24:45]Second\n[01:02:03.250]Hours',
      );
      expect(doc.lines.map((line) => line.time.inMilliseconds), [
        1500,
        204450,
        3723250,
      ]);
    });
    test('cache round trip retains synchronization and source', () {
      final doc = LyricsDocument.parse(
        '[offset:100]\n[00:01]Invented',
        source: 'Test',
      );
      final copy = LyricsDocument.fromJson(
        jsonDecode(jsonEncode(doc.toJson())),
      );
      expect(copy.lines.single.time.inMilliseconds, 900);
      expect(copy.source, 'Test');
    });
  });
  group('lyrics lifecycle and privacy', () {
    late FakeLyricsPlatform platform;
    late LyricsController c;
    setUp(() {
      platform = FakeLyricsPlatform();
      c = LyricsController(platform: platform);
    });
    tearDown(() => c.dispose());
    test('initialization and track switching never request lyrics', () async {
      await c.initialize();
      c.selectTrack(a);
      c.selectTrack(b);
      c.selectTrack(null);
      expect(platform.queries, isEmpty);
      expect(platform.writes, isEmpty);
    });
    test('explicit search transmits only the approved fields, no paths or duration', () async {
      c.selectTrack(a, folder: 'Secret folder');
      platform.response = LyricsHttpResponse(200, records());
      await c.search(
        title: ' Edited title ',
        artist: ' Edited artist ',
        album: '',
      );
      expect(platform.queries.single.host, 'lrclib.net');
      expect(platform.queries.single.queryParameters, {
        'track_name': 'Edited title',
        'artist_name': 'Edited artist',
      });
      expect(c.candidates.length, 1);
      expect(c.document, isNull);
      expect(platform.writes, isEmpty);
      await c.choose(c.candidates.single);
      expect(c.document!.isSynced, true);
      expect(platform.writes.length, 1);
    });
    test(
      'required metadata and length validation never query the provider',
      () async {
        c.selectTrack(a);
        await c.search(title: 'Song', artist: '', album: '');
        expect(c.error, contains('歌手'));
        await c.search(title: 'a' * 301, artist: 'Artist', album: '');
        expect(platform.queries, isEmpty);
      },
    );
    test('duplicate searches suppressed and stale response cannot attach to next song', () async {
      c.selectTrack(a);
      platform.pending = Completer();
      final first = c.search(title: a.title, artist: a.artist, album: '');
      await c.search(title: a.title, artist: a.artist, album: '');
      expect(platform.queries.length, 1);
      c.selectTrack(b);
      platform.pending!.complete(LyricsHttpResponse(200, records()));
      await first;
      expect(c.candidates, isEmpty);
      expect(c.document, isNull);
      expect(c.busy, false);
    });
    test(
      'cancelled response is ignored and existing lyrics retained',
      () async {
        c.selectTrack(a);
        await c.importText('Existing local words');
        platform.pending = Completer();
        final search = c.search(title: a.title, artist: a.artist, album: '');
        c.cancelSearch();
        platform.pending!.complete(LyricsHttpResponse(200, records()));
        await search;
        expect(c.candidates, isEmpty);
        expect(c.document!.text, 'Existing local words');
        expect(platform.writes.length, 1);
      },
    );
    test(
      'empty, malformed and failed searches preserve prior lyrics',
      () async {
        c.selectTrack(a);
        await c.importText('Original');
        await c.search(title: a.title, artist: a.artist, album: '');
        expect(c.notice, contains('没有找到'));
        platform.response = const LyricsHttpResponse(
          200,
          '<html>not JSON</html>',
        );
        await c.search(title: a.title, artist: a.artist, album: '');
        expect(c.error, isNotNull);
        platform.response = const LyricsHttpResponse(500, '<html>Error</html>');
        await c.search(title: a.title, artist: a.artist, album: '');
        expect(c.error, contains('500'));
        expect(c.document!.text, 'Original');
        expect(platform.writes.length, 1);
      },
    );
    test('plain and instrumental candidates remain distinct', () async {
      c.selectTrack(a);
      platform.response = LyricsHttpResponse(
        200,
        records(synced: null, plain: 'Plain text'),
      );
      await c.search(title: a.title, artist: a.artist, album: '');
      expect(c.candidates.single.document.isSynced, false);
      platform.response = LyricsHttpResponse(
        200,
        records(synced: null, instrumental: true),
      );
      await c.search(title: a.title, artist: a.artist, album: '');
      expect(c.candidates.single.document.instrumental, true);
    });
    test('429 Retry-After prohibits retries until delay elapsed', () async {
      var now = DateTime.utc(2026, 11, 7, 12);
      c.dispose();
      c = LyricsController(platform: platform, now: () => now)..selectTrack(a);
      platform.response = const LyricsHttpResponse(
        429,
        'Too many requests',
        retryAfter: '120',
      );
      await c.search(title: a.title, artist: a.artist, album: '');
      expect(c.retryAfter!.inSeconds, 121);
      await c.search(title: a.title, artist: a.artist, album: '');
      expect(platform.queries.length, 1);
      now = now.add(const Duration(seconds: 122));
      platform.response = const LyricsHttpResponse(200, '[]');
      await c.search(title: a.title, artist: a.artist, album: '');
      expect(platform.queries.length, 2);
    });
    test('503 HTTP-date Retry-After and missing header fallback', () async {
      c.dispose();
      c = LyricsController(
        platform: platform,
        now: () => DateTime.utc(2026, 11, 7, 12),
      )..selectTrack(a);
      platform.response = const LyricsHttpResponse(
        503,
        'Unavailable',
        retryAfter: 'Sat, 07 Nov 2026 12:02:00 GMT',
      );
      await c.search(title: a.title, artist: a.artist, album: '');
      expect(c.retryAfter!.inSeconds, 121);
    });
    test('downloaded cache restores offline and isolates songs', () async {
      c.selectTrack(a, source: 'web', folder: 'Music');
      await c.importText('[00:01]Cached words');
      c.selectTrack(b, source: 'web', folder: 'Music');
      expect(c.document, isNull);
      final restored = LyricsController(platform: platform);
      restored.selectTrack(a, source: 'web', folder: 'Music');
      await restored.initialize();
      expect(restored.document!.lines.single.text, 'Cached words');
      expect(platform.queries, isEmpty);
      restored.dispose();
    });
    test(
      'read and write storage failures are recoverable and honest',
      () async {
        platform.readFailure = StateError('Private storage');
        platform.writeFailure = StateError('Quota');
        c.selectTrack(a);
        await c.importText('Session words');
        expect(c.document!.text, 'Session words');
        expect(c.notice, contains('保存失败'));
        expect(c.busy, false);
      },
    );
    test('cancelled or invalid import preserves current text', () async {
      c.selectTrack(a);
      await c.importText('Retain');
      await c.importFile();
      expect(c.document!.text, 'Retain');
      await c.importText('[ar:Only metadata]');
      expect(c.error, isNotNull);
      expect(c.document!.text, 'Retain');
      expect(platform.writes.length, 1);
    });
    test(
      'distinct source roots never share lyrics or accept stale imports',
      () async {
        c.selectTrack(
          a,
          source: 'web',
          folder: 'Music',
          sourceIdentity: 'root-1',
        );
        await c.importText('First folder lyrics');
        platform.pendingImport = Completer();
        final pending = c.importFile();
        c.selectTrack(
          a,
          source: 'web',
          folder: 'Music',
          sourceIdentity: 'root-2',
        );
        expect(c.document, isNull);
        platform.pendingImport!.complete('Stale import');
        await pending;
        expect(c.document, isNull);
        expect(platform.writes.length, 1);
        c.selectTrack(
          a,
          source: 'web',
          folder: 'Music',
          sourceIdentity: 'root-1',
        );
        expect(c.document!.text, 'First folder lyrics');
      },
    );
    test('source display-name changes do not detach accepted lyrics', () async {
      c.selectTrack(
        a,
        source: 'android',
        folder: 'Old name',
        sourceIdentity: 'root',
      );
      await c.importText('Retained');
      c.selectTrack(
        a,
        source: 'android',
        folder: 'New name',
        sourceIdentity: 'root',
      );
      expect(c.document!.text, 'Retained');
    });
    test('import finishing after song switch is ignored', () async {
      c.selectTrack(a);
      platform.pendingImport = Completer();
      final pending = c.importFile();
      c.selectTrack(b);
      platform.pendingImport!.complete('Other track text');
      await pending;
      expect(c.document, isNull);
      expect(platform.writes, isEmpty);
    });
    test('late cache read cannot erase new imported content', () async {
      platform.pendingRead = Completer();
      c.selectTrack(a);
      final initialization = c.initialize();
      final imported = c.importText('New words');
      platform.pendingRead!.complete(jsonEncode({'version': 1, 'entries': {}}));
      await initialization;
      await imported;
      expect(c.document!.text, 'New words');
    });
    test('corrupt cache entries do not block recovery', () async {
      platform.cache = '{broken';
      await c.initialize();
      expect(c.notice, contains('无法读取'));
      c.selectTrack(a);
      await c.importText('Recovered');
      expect(c.document!.text, 'Recovered');
    });
  });
}
