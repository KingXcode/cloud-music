import 'dart:typed_data';

enum TrackAvailability { ready, cloud, offline, missing, unsupported, unknown }

enum RepeatMode { off, all, one }

class Track {
  const Track({
    required this.id,
    required this.title,
    this.artist = '',
    this.album = '',
    this.relativePath = '',
    this.availability = TrackAvailability.unknown,
    this.duration = Duration.zero,
  });
  final String id, title, artist, album, relativePath;
  final TrackAvailability availability;
  final Duration duration;

  factory Track.fromMap(Map<Object?, Object?> map) => Track(
    id: map['id'] as String? ?? '',
    title: map['title'] as String? ?? '未命名音频',
    artist: map['artist'] as String? ?? '',
    album: map['album'] as String? ?? '',
    relativePath: map['relativePath'] as String? ?? '',
    availability:
        TrackAvailability.values
            .where((s) => s.name == map['status'])
            .firstOrNull ??
        TrackAvailability.unknown,
    duration: Duration(milliseconds: _positiveInt(map['durationMs'])),
  );

  Track copyWith({
    String? title,
    String? artist,
    String? album,
    TrackAvailability? availability,
    Duration? duration,
  }) => Track(
    id: id,
    title: title ?? this.title,
    artist: artist ?? this.artist,
    album: album ?? this.album,
    relativePath: relativePath,
    availability: availability ?? this.availability,
    duration: duration ?? this.duration,
  );
}

class LibrarySnapshot {
  const LibrarySnapshot({
    this.folderName,
    this.sourceKind = '',
    this.tracks = const [],
    this.currentTrackId,
    this.isPlaying = false,
    this.isLoading = false,
    this.isScanning = false,
    this.shuffle = false,
    this.position = Duration.zero,
    this.duration = Duration.zero,
    this.repeatMode = RepeatMode.off,
    this.volume = 1,
    this.artwork,
    this.message,
  });
  final String? folderName, currentTrackId, message;
  final String sourceKind;
  final List<Track> tracks;
  final bool isPlaying, isLoading, isScanning, shuffle;
  final Duration position, duration;
  final RepeatMode repeatMode;
  final double volume;
  final Uint8List? artwork;
  Track? get currentTrack =>
      tracks.where((t) => t.id == currentTrackId).firstOrNull;

  factory LibrarySnapshot.fromMap(Map<Object?, Object?> map) => LibrarySnapshot(
    folderName: map['folderName'] as String?,
    sourceKind: map['sourceKind'] as String? ?? '',
    tracks: (map['tracks'] as List? ?? const [])
        .whereType<Map>()
        .map((t) => Track.fromMap(Map<Object?, Object?>.from(t)))
        .toList(growable: false),
    currentTrackId: map['currentTrackId'] as String?,
    isPlaying: map['isPlaying'] == true,
    isLoading: map['isLoading'] == true,
    isScanning: map['isScanning'] == true,
    shuffle: map['shuffle'] == true,
    position: Duration(milliseconds: _positiveInt(map['positionMs'])),
    duration: Duration(milliseconds: _positiveInt(map['durationMs'])),
    repeatMode:
        RepeatMode.values
            .where((s) => s.name == map['repeatMode'])
            .firstOrNull ??
        RepeatMode.off,
    volume: ((map['volume'] as num?)?.toDouble() ?? 1).clamp(0, 1),
    artwork: map['artwork'] is Uint8List ? map['artwork'] as Uint8List : null,
    message: map['message'] as String?,
  );
}

int _positiveInt(Object? value) =>
    value is num && value.isFinite ? value.toInt().clamp(0, 1 << 53) : 0;
