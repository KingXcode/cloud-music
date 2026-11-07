import 'package:cloud_music/models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('native snapshot preserves cloud and missing as distinct states', () {
    final state = LibrarySnapshot.fromMap({
      'tracks': [
        {'id': 'a', 'title': '云端歌曲', 'status': 'cloud'},
        {'id': 'b', 'title': '已移走歌曲', 'status': 'missing'},
      ],
      'currentTrackId': 'a',
    });
    expect(state.tracks[0].availability, TrackAvailability.cloud);
    expect(state.tracks[1].availability, TrackAvailability.missing);
    expect(state.currentTrack?.id, 'a');
  });
  test('unknown status stays unknown rather than missing', () {
    final state = LibrarySnapshot.fromMap({
      'tracks': [
        {'id': 'a', 'status': 'provider_error'},
      ],
      'durationMs': -3,
      'positionMs': double.nan,
      'volume': 3,
    });
    expect(state.tracks.single.availability, TrackAvailability.unknown);
    expect(state.duration, Duration.zero);
    expect(state.position, Duration.zero);
    expect(state.volume, 1);
  });
}
