import 'dart:convert';

const maxLyricsBytes = 256 * 1024;

class LyricLine {
  const LyricLine(this.time, this.text);
  final Duration time;
  final String text;
}

/// Lyrics remain plain text. No HTML, URLs or executable markup are interpreted.
class LyricsDocument {
  LyricsDocument._({
    required this.text,
    required this.lines,
    required this.source,
    this.instrumental = false,
  });

  factory LyricsDocument.parse(
    String text, {
    String source = '本地导入',
    bool instrumental = false,
    String? plainFallback,
  }) {
    if (utf8.encode(text).length > maxLyricsBytes ||
        utf8.encode(plainFallback ?? '').length > maxLyricsBytes) {
      throw const FormatException('歌词文件过大，请选择不超过 256 KB 的文件。');
    }
    final normalized = text.replaceFirst('\uFEFF', '').replaceAll('\r', '');
    final offset = RegExp(
      r'\[offset:([+-]?\d+)\]',
      caseSensitive: false,
    ).firstMatch(normalized);
    // LRC positive offsets advance lyrics relative to the audio clock.
    final offsetMs = int.tryParse(offset?.group(1) ?? '') ?? 0;
    // A third colon component without a dot is LRC centiseconds, not hours.
    // Hour-form timestamps require an explicit fractional dot: hh:mm:ss.xxx.
    final timestamps = RegExp(
      r'\[(?:(\d{1,3}):(\d{2}):(\d{2})\.(\d{1,3})|(\d{1,3}):(\d{2})(?:[.:](\d{1,3}))?)\]',
    );
    int hours(RegExpMatch m) => int.parse(m.group(1) ?? '0');
    int minutes(RegExpMatch m) => int.parse(m.group(2) ?? m.group(5)!);
    int seconds(RegExpMatch m) => int.parse(m.group(3) ?? m.group(6)!);
    int fractions(RegExpMatch m) =>
        int.parse((m.group(4) ?? m.group(7) ?? '0').padRight(3, '0'));
    final metadata = RegExp(
      r'^\s*\[(?:ar|ti|al|by|re|ve|length|offset):[^\]]*\]\s*$',
      caseSensitive: false,
    );
    final grouped = <int, List<String>>{};
    final plain = <String>[];
    var count = 0;
    for (final row in const LineSplitter().convert(normalized)) {
      if (metadata.hasMatch(row)) continue;
      final matches = timestamps.allMatches(row).where((m) {
        return seconds(m) < 60 && (m.group(1) == null || minutes(m) < 60);
      }).toList();
      if (matches.isEmpty) {
        plain.add(row);
        continue;
      }
      final content = row.replaceAll(timestamps, '').trim();
      plain.add(content);
      for (final match in matches) {
        if (++count > 5000) {
          throw const FormatException('歌词行数过多，请选择较短的文件。');
        }
        final milliseconds =
            (hours(match) * 3600 + minutes(match) * 60 + seconds(match)) *
                1000 +
            fractions(match) -
            offsetMs;
        final bucket = grouped.putIfAbsent(
          milliseconds.clamp(0, 1 << 53),
          () => [],
        );
        if (!bucket.contains(content)) bucket.add(content);
      }
    }
    final keys = grouped.keys.toList()..sort();
    final lines = keys
        .map(
          (key) =>
              LyricLine(Duration(milliseconds: key), grouped[key]!.join('\n')),
        )
        .toList(growable: false);
    final hasTimedText = lines.any((line) => line.text.isNotEmpty);
    final fallback = (plainFallback?.trim().isNotEmpty ?? false)
        ? plainFallback!.replaceFirst('\uFEFF', '').replaceAll('\r', '').trim()
        : plain.join('\n').trim();
    return LyricsDocument._(
      text: hasTimedText ? normalized.trim() : fallback,
      lines: hasTimedText ? List.unmodifiable(lines) : const [],
      source: source,
      instrumental: instrumental && !hasTimedText && fallback.isEmpty,
    );
  }

  final String text, source;
  final List<LyricLine> lines;
  final bool instrumental;
  bool get isSynced => lines.isNotEmpty;
  bool get isEmpty => !instrumental && text.trim().isEmpty;

  int activeLineIndex(Duration position) {
    var low = 0, high = lines.length - 1, result = -1;
    while (low <= high) {
      final mid = (low + high) ~/ 2;
      if (lines[mid].time <= position) {
        result = mid;
        low = mid + 1;
      } else {
        high = mid - 1;
      }
    }
    return result;
  }

  Map<String, Object> toJson() => {
    'text': text,
    'source': source,
    'instrumental': instrumental,
  };

  factory LyricsDocument.fromJson(Map<String, dynamic> value) =>
      LyricsDocument.parse(
        value['text'] as String,
        source: value['source'] as String,
        instrumental: value['instrumental'] == true,
      );
}

class LyricsCandidate {
  const LyricsCandidate({
    required this.id,
    required this.title,
    required this.artist,
    required this.album,
    required this.duration,
    required this.document,
  });
  final int id;
  final String title, artist, album;
  final Duration duration;
  final LyricsDocument document;

  factory LyricsCandidate.fromJson(Map<String, dynamic> value) {
    final seconds = value['duration'];
    final milliseconds = seconds is num && seconds.isFinite && seconds >= 0
        ? (seconds * 1000).round().clamp(0, 1 << 53)
        : 0;
    return LyricsCandidate(
      id: value['id'] as int,
      title: value['trackName'] as String? ?? '',
      artist: value['artistName'] as String? ?? '',
      album: value['albumName'] as String? ?? '',
      duration: Duration(milliseconds: milliseconds),
      document: LyricsDocument.parse(
        value['syncedLyrics'] as String? ?? '',
        plainFallback: value['plainLyrics'] as String?,
        instrumental: value['instrumental'] == true,
        source: 'LRCLIB · #${value['id']}',
      ),
    );
  }
}
