import '../models.dart';
import 'lyrics_models.dart';
import 'lyrics_text_conversion.dart';

// 仅忽略字形、空白和标点差异，不删除现场、翻唱、混音等版本信息。
String normalizeLyricsIdentity(String value) {
  final width = String.fromCharCodes(
    value.runes.map((r) {
      if (r == 0x3000) return 0x20;
      return r >= 0xff01 && r <= 0xff5e ? r - 0xfee0 : r;
    }),
  );
  return simplifyChinese(width)
      .toLowerCase()
      .replaceAll(RegExp(r'\b(?:featuring|feat|ft)\.?\s*'), ' feat ')
      .replaceAll(RegExp(r'[^\p{L}\p{N}]', unicode: true), '');
}

/// 字形转换只影响比较；候选元数据和下载原文保持不变。
bool lyricsIdentityMatches(Track track, LyricsCandidate candidate) =>
    normalizeLyricsIdentity(track.title).isNotEmpty &&
    normalizeLyricsIdentity(track.title) ==
        normalizeLyricsIdentity(candidate.title) &&
    (track.artist.trim().isEmpty ||
        normalizeLyricsIdentity(track.artist) ==
            normalizeLyricsIdentity(candidate.artist)) &&
    _sameVersion(track, candidate);

List<LyricsCandidate> rankLyricsCandidates(
  Track track,
  List<LyricsCandidate> values,
) {
  final ranked = List<LyricsCandidate>.of(values);
  ranked.sort((a, b) {
    final score = lyricsMatchScore(
      track,
      b,
    ).compareTo(lyricsMatchScore(track, a));
    if (score != 0) return score;
    // 确定性分组使比较器可传递；时间轴只打破同一歌曲版本的平局。
    for (final pair in [
      (a.title, b.title),
      (a.artist, b.artist),
      (a.album, b.album),
    ]) {
      final identity = normalizeLyricsIdentity(pair.$1)
          .compareTo(normalizeLyricsIdentity(pair.$2));
      if (identity != 0) return identity;
    }
    // Missing duration is unknown, not a zero-length recording. Never put it
    // ahead of equally matched versions with usable source metadata.
    if ((a.duration > Duration.zero) != (b.duration > Duration.zero)) {
      return a.duration > Duration.zero ? -1 : 1;
    }
    if (track.duration > Duration.zero) {
      final distance = (a.duration - track.duration).inMilliseconds
          .abs()
          .compareTo((b.duration - track.duration).inMilliseconds.abs());
      if (distance != 0) return distance;
    }
    final duration = a.duration.compareTo(b.duration);
    if (duration != 0) return duration;
    if (a.duration > Duration.zero &&
        a.document.isSynced != b.document.isSynced) {
      return a.document.isSynced ? -1 : 1;
    }
    return a.id.compareTo(b.id);
  });
  return ranked;
}

int lyricsMatchScore(Track track, LyricsCandidate candidate) {
  var score = 0;
  if (normalizeLyricsIdentity(track.title) ==
      normalizeLyricsIdentity(candidate.title)) {
    score += 50;
  }
  if (track.artist.isNotEmpty &&
      normalizeLyricsIdentity(track.artist) ==
          normalizeLyricsIdentity(candidate.artist)) {
    score += 30;
  }
  if (track.album.isNotEmpty &&
      normalizeLyricsIdentity(track.album) ==
          normalizeLyricsIdentity(candidate.album)) {
    score += 10;
  }
  if (track.duration > Duration.zero &&
      candidate.duration > Duration.zero &&
      (track.duration - candidate.duration).inMilliseconds.abs() <= 3000) {
    score += 15;
  }
  return score;
}

Set<String> _versionFlags(String title, String album) {
  final text = simplifyChinese('$title $album').toLowerCase();
  return {
    for (final entry in <String, String>{
      'live': r'\blive\b|现场|演唱会',
      'remix': r'\bremix\b|混音',
      'instrumental': r'\binstrumental\b|\bkaraoke\b|伴奏',
      'acoustic': r'\bacoustic\b|不插电',
      'demo': r'\bdemo\b',
      'cover': r'\bcover\b|翻唱',
    }.entries)
      if (RegExp(entry.value).hasMatch(text)) entry.key,
  };
}

bool _sameVersion(Track track, LyricsCandidate candidate) {
  final local = _versionFlags(track.title, track.album);
  final remote = _versionFlags(candidate.title, candidate.album);
  return local.length == remote.length && local.containsAll(remote);
}

/// 必须同时核对歌名、完整歌手、版本标记和时长；多个不同时间轴不猜测。
LyricsCandidate? confidentLyricsMatch(
  Track track,
  List<LyricsCandidate> values,
) {
  if (track.artist.trim().isEmpty || track.duration <= Duration.zero) {
    return null;
  }
  var matches = values
      .where(
        (candidate) =>
            normalizeLyricsIdentity(track.title).isNotEmpty &&
            normalizeLyricsIdentity(track.title) ==
                normalizeLyricsIdentity(candidate.title) &&
            normalizeLyricsIdentity(track.artist) ==
                normalizeLyricsIdentity(candidate.artist) &&
            _sameVersion(track, candidate) &&
            candidate.duration > Duration.zero &&
            (candidate.duration - track.duration).inMilliseconds.abs() <= 3000,
      )
      .toList();
  if (matches.isEmpty) return null;
  if (track.album.isNotEmpty) {
    final sameAlbum = matches
        .where(
          (c) =>
              normalizeLyricsIdentity(c.album) ==
              normalizeLyricsIdentity(track.album),
        )
        .toList();
    if (sameAlbum.isNotEmpty) matches = sameAlbum;
  }
  if (matches.length == 1) return matches.single;
  // 无时间轴与有时间轴记录只有逐行文字完全一致时才可视为同一份。
  // 两个不同时间轴仍保持歧义，不按“有时间轴”盲选。
  final synced = matches.where((c) => c.document.isSynced).toList();
  String body(LyricsDocument doc) =>
      (doc.isSynced ? doc.lines.map((line) => line.text).join('\n') : doc.text)
          .split('\n')
          .map((line) => line.trim())
          .where((line) => line.isNotEmpty)
          .join('\n');
  if (synced.isNotEmpty &&
      matches.every(
        (c) =>
            !c.document.instrumental &&
            body(c.document) == body(synced.first.document),
      )) {
    matches = synced;
    if (matches.length == 1) return matches.single;
  }
  // 同一份歌词的重复记录不算版本歧义。
  if (matches.every(
    (c) =>
        c.document.text == matches.first.document.text &&
        c.document.instrumental == matches.first.document.instrumental,
  )) {
    return matches.first;
  }
  return null;
}
