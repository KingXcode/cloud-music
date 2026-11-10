import 'models.dart';

enum LibrarySort { original, title, artist, album, duration, playCount }

extension LibrarySortLabel on LibrarySort {
  String get label => switch (this) {
    LibrarySort.original => '资料库顺序',
    LibrarySort.title => '歌曲名称',
    LibrarySort.artist => '歌手',
    LibrarySort.album => '专辑',
    LibrarySort.duration => '时长',
    LibrarySort.playCount => '播放次数',
  };
}

/// 返回新的列表；未知歌手、专辑及音频时长始终放在末尾。
List<Track> sortLibraryTracks(
  Iterable<Track> tracks, {
  required LibrarySort sort,
  bool descending = false,
  required int Function(Track) playCount,
}) {
  final result = tracks.toList();
  if (sort == LibrarySort.original) return result;
  result.sort((a, b) {
    final missingA = _missing(a, sort), missingB = _missing(b, sort);
    if (missingA != missingB) return missingA ? 1 : -1;
    final order = switch (sort) {
      LibrarySort.original => 0,
      LibrarySort.title => _text(a.title, b.title),
      LibrarySort.artist => _text(a.artist, b.artist),
      LibrarySort.album => _text(a.album, b.album),
      LibrarySort.duration => a.duration.compareTo(b.duration),
      LibrarySort.playCount => playCount(a).compareTo(playCount(b)),
    };
    if (order != 0) return descending ? -order : order;
    final titleOrder = _text(a.title, b.title);
    return titleOrder != 0 ? titleOrder : a.id.compareTo(b.id);
  });
  return result;
}

bool _missing(Track track, LibrarySort sort) => switch (sort) {
  LibrarySort.artist => track.artist.trim().isEmpty,
  LibrarySort.album => track.album.trim().isEmpty,
  LibrarySort.duration => track.duration <= Duration.zero,
  _ => false,
};

int _text(String a, String b) =>
    a.trim().toLowerCase().compareTo(b.trim().toLowerCase());
