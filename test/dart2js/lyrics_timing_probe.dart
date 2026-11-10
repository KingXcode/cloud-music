// Run unchanged on the Dart VM and compiled JavaScript. These imports are the
// production parsing paths, not a second implementation of their arithmetic.
import 'package:cloud_music/lyrics/lyrics_matching.dart';
import 'package:cloud_music/lyrics/lyrics_models.dart';
import 'package:cloud_music/models.dart';
import 'package:cloud_music/time_values.dart';

void _equal(Object? actual, Object? expected, String label) {
  if (actual != expected) {
    throw StateError('$label: expected $expected, got $actual');
  }
}

void main() {
  _equal(nonNegativeMilliseconds(315140), 315140, 'numeric clock');
  _equal(nonNegativeMilliseconds(1512.75), 1512, 'fractional clock');
  for (final bad in [null, '315140', -1, double.nan, double.infinity]) {
    _equal(nonNegativeMilliseconds(bad), 0, 'invalid clock $bad');
  }
  _equal(nonNegativeMilliseconds(1e20), maxSafeTimeInteger, 'upper bound');

  for (final source in ['web', 'apple', 'android', 'googleDrive']) {
    final snapshot = LibrarySnapshot.fromMap({
      'sourceKind': source,
      'currentTrackId': 'fictional',
      'positionMs': 24750,
      'durationMs': 315140,
      'importRevision': 12,
      'tracks': [
        {'id': 'fictional', 'title': 'Test Paper', 'durationMs': 315140},
      ],
    });
    _equal(snapshot.position.inMilliseconds, 24750, '$source position');
    _equal(snapshot.duration.inMilliseconds, 315140, '$source duration');
    _equal(
      snapshot.currentTrack!.duration.inMilliseconds,
      315140,
      '$source track duration',
    );
    _equal(snapshot.importRevision, 12, '$source import revision');
  }

  // Fictional content; no downloaded lyrics or network requests in this test.
  final candidate = LyricsCandidate.fromJson({
    'id': 1,
    'trackName': 'Test Paper',
    'artistName': 'Test Ensemble',
    'duration': 315.14,
    'syncedLyrics':
        '[offset:250]\n'
        '[00:01.50]Paper moon\n'
        '[00:24.75]Imaginary harbor\n'
        '[00:30.00][00:40.00]Fictional repeat\n'
        '[00:50.00]',
  });
  _equal(candidate.duration.inMilliseconds, 315140, 'provider duration');
  final document = candidate.document;
  _equal(document.lines.length, 5, 'distinct lyric timestamps');
  _equal(document.lines[0].time.inMilliseconds, 1250, 'offset timestamp');
  _equal(document.lines[1].time.inMilliseconds, 24500, 'fraction timestamp');
  _equal(document.lines[2].time.inMilliseconds, 29750, 'repeat timestamp');
  _equal(document.lines[3].time.inMilliseconds, 39750, 'second repeat');
  _equal(document.activeLineIndex(Duration.zero), -1, 'before first line');
  _equal(
    document.activeLineIndex(const Duration(milliseconds: 24500)),
    1,
    'advance playback',
  );
  _equal(
    document.activeLineIndex(const Duration(seconds: 40)),
    3,
    'seek forward',
  );
  _equal(
    document.activeLineIndex(const Duration(seconds: 2)),
    0,
    'seek backward',
  );
  _equal(
    document.activeLineIndex(const Duration(seconds: 55)),
    4,
    'blank ending cue',
  );
  final restored = LyricsDocument.fromJson(document.toJson());
  _equal(restored.lines[1].time.inMilliseconds, 24500, 'cached timestamp');
  _equal(
    document.simplified().lines[1].time.inMilliseconds,
    24500,
    'display conversion keeps timestamp',
  );

  final colon = LyricsDocument.parse('[00:01:50]Paper\n[01:02:03.250]Moon');
  _equal(colon.lines.first.time.inMilliseconds, 1500, 'colon centiseconds');
  _equal(colon.lines.last.time.inMilliseconds, 3723250, 'hours');
  _equal(
    LyricsDocument.parse('Plain test text').isSynced,
    false,
    'plain text has no fabricated timestamps',
  );
  final unknown = LyricsCandidate.fromJson({
    'id': 2,
    'trackName': 'Test Paper',
    'artistName': 'Test Ensemble',
    'syncedLyrics': '[00:01]Test line',
  });
  _equal(unknown.duration, Duration.zero, 'missing duration stays unknown');
  const track = Track(
    id: 'fictional',
    title: 'Test Paper',
    artist: 'Test Ensemble',
  );
  _equal(
    rankLyricsCandidates(track, [unknown, candidate]).first.id,
    1,
    'known duration sorts before unknown',
  );
  // ignore: avoid_print
  print('Playback and lyric timing passed on this Dart runtime.');
}
