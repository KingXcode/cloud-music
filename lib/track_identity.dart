/// 仅从本地字段推断缺失的信息，不查询网络，也不猜测专辑。
class TrackIdentity {
  const TrackIdentity({required this.title, required this.artist});

  final String title;
  final String artist;
}

/// 保留有效的内嵌标签，只修正占位标签和明显的文件名回退值。
TrackIdentity normalizeTrackIdentity({
  String title = '',
  String artist = '',
  String relativePath = '',
}) {
  final rawTitle = title.trim();
  final rawArtist = artist.trim();
  final filename = relativePath.replaceAll('\\', '/').split('/').last;
  final stem = _withoutExtension(filename.trim());
  final missingTitle = _isPlaceholder(rawTitle, isArtist: false);
  final missingArtist = _isPlaceholder(rawArtist, isArtist: true);
  final filenameTitle =
      stem.isNotEmpty &&
      (_withoutExtension(rawTitle) == stem || rawTitle == filename);
  final source = stem.isNotEmpty ? stem : (missingTitle ? '' : rawTitle);
  final cleaned = _cleanFilename(source);
  final parsed = _splitIdentity(cleaned);

  // 没有路径时，未知歌手加明确分隔符才视作文件名，避免拆开真实标题。
  final fallbackTitle =
      missingTitle ||
      (filenameTitle &&
          (missingArtist ||
              parsed == null ||
              _sameTitle(rawArtist, parsed.artist))) ||
      (stem.isEmpty &&
          missingArtist &&
          (parsed != null || cleaned != rawTitle));
  final resolvedTitle = fallbackTitle ? (parsed?.title ?? cleaned) : rawTitle;
  // 有效标题与文件名不一致时不引入文件名里的歌手，防止错误配对。
  final canInferArtist =
      parsed != null && (fallbackTitle || _sameTitle(rawTitle, parsed.title));
  return TrackIdentity(
    title: resolvedTitle.isEmpty ? '未命名音频' : resolvedTitle,
    artist: missingArtist ? (canInferArtist ? parsed.artist : '') : rawArtist,
  );
}

bool _isPlaceholder(String value, {required bool isArtist}) {
  final normalized = value.trim().toLowerCase();
  return normalized.isEmpty ||
      const {
        'unknown',
        '<unknown>',
        '(unknown)',
        'null',
        'n/a',
        '未知',
      }.contains(normalized) ||
      (isArtist
          ? const {
              'unknown artist',
              '未知歌手',
              '未知艺术家',
              '未知艺人',
            }.contains(normalized)
          : const {
              'unknown title',
              'untitled',
              '未命名音频',
              '未知歌曲',
              '未知标题',
            }.contains(normalized));
}

String _withoutExtension(String value) => value
    .replaceFirst(
      RegExp(
        r'\.(?:mp3|flac|wav|m4a|aac|ogg|opus|aiff?|alac|wma|ape|dsf|dff|mp4)$',
        caseSensitive: false,
      ),
      '',
    )
    .trim();

String _cleanFilename(String value) {
  var result = _withoutExtension(value).trim();
  // 只移除显式曲序；保留 1979、99 Luftballons 等有意义的数字标题。
  result = result.replaceFirst(
    RegExp(
      r'^(?:[sS]\d{1,6}(?:\s*[-–—－._]\s*|\s+)|\d{1,3}\s*[-–—－._]\s*|0\d{1,2}\s+)',
    ),
    '',
  );
  // 只删除末尾确定的编码/音质标签，不删除现场、混音、版本名等内容。
  const quality =
      r'(?:flac|mp3|wav|aac|ape|alac|lossless|hi[- ]?res|hq|sq|无损|高品质|高音质|\d{2,4}\s*kbps|\d{2}\s*bit(?:[ /_-]*\d{2,3}(?:\.\d+)?\s*k(?:hz)?)?)';
  final suffix = RegExp(
    '(?:\\s*[\\[【(（]\\s*$quality\\s*[\\]】)）]|[ _-]+$quality)\$',
    caseSensitive: false,
  );
  while (true) {
    final next = result.replaceFirst(suffix, '').trim();
    if (next == result) break;
    result = next;
  }
  return result;
}

TrackIdentity? _splitIdentity(String value) {
  // ASCII 连字符必须带空格，避免把 AC-DC 或普通英文连字符标题拆开。
  var separator = RegExp(r'\s+[-–—－]\s*|\s*[-–—－]\s+|[–—－]').firstMatch(value);
  if (separator == null) {
    // 常见中文下载文件不带空格；两侧含汉字才允许紧凑的 ASCII 分隔符。
    final compact = RegExp(r'(?<=[\u3400-\u9fff])-(?=[\u3400-\u9fff])')
        .firstMatch(value);
    separator = compact;
  }
  if (separator == null && '_'.allMatches(value).length == 1) {
    separator = RegExp('_').firstMatch(value);
  }
  if (separator == null) return null;
  final artist = value.substring(0, separator.start).trim();
  final title = value.substring(separator.end).trim();
  if (artist.isEmpty || title.isEmpty || RegExp(r'^\d+$').hasMatch(artist)) {
    return null;
  }
  return TrackIdentity(title: title, artist: artist);
}

bool _sameTitle(String a, String b) =>
    a.trim().toLowerCase() == b.trim().toLowerCase();
