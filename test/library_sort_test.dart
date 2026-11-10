import 'package:cloud_music/library_sort.dart';
import 'package:cloud_music/models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const tracks = [
    Track(
      id: 'b',
      title: 'Bravo',
      artist: 'Z',
      album: 'B',
      duration: Duration(seconds: 20),
    ),
    Track(id: 'c', title: 'Charlie'),
    Track(
      id: 'a',
      title: 'Alpha',
      artist: 'A',
      album: 'A',
      duration: Duration(seconds: 40),
    ),
  ];
  final counts = {'b': 3, 'c': 0, 'a': 8};
  List<String> sorted(LibrarySort sort, {bool descending = false}) =>
      sortLibraryTracks(
        tracks,
        sort: sort,
        descending: descending,
        playCount: (track) => counts[track.id]!,
      ).map((track) => track.id).toList();

  test('Sorts by title, artist, album and duration without changing input', () {
    expect(sorted(LibrarySort.original), ['b', 'c', 'a']);
    expect(sorted(LibrarySort.title), ['a', 'b', 'c']);
    expect(sorted(LibrarySort.artist), ['a', 'b', 'c']);
    expect(sorted(LibrarySort.album), ['a', 'b', 'c']);
    expect(sorted(LibrarySort.duration), ['b', 'a', 'c']);
    expect(tracks.map((track) => track.id), ['b', 'c', 'a']);
  });

  test(
    'Descending reverses known values while leaving unknown metadata last',
    () {
      expect(sorted(LibrarySort.title, descending: true), ['c', 'b', 'a']);
      expect(sorted(LibrarySort.artist, descending: true), ['b', 'a', 'c']);
      expect(sorted(LibrarySort.album, descending: true), ['b', 'a', 'c']);
      expect(sorted(LibrarySort.duration, descending: true), ['a', 'b', 'c']);
    },
  );

  test('Play count supports most and least played first, including zero', () {
    expect(sorted(LibrarySort.playCount, descending: true), ['a', 'b', 'c']);
    expect(sorted(LibrarySort.playCount), ['c', 'b', 'a']);
  });

  test('Equal counts have deterministic title order', () {
    final result = sortLibraryTracks(
      tracks,
      sort: LibrarySort.playCount,
      descending: true,
      playCount: (_) => 0,
    );
    expect(result.map((track) => track.id), ['a', 'b', 'c']);
  });
}
