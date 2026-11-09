import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../models.dart';
import 'lyrics_factory.dart';
import 'lyrics_models.dart';
import 'lyrics_matching.dart';
import 'lyrics_platform.dart';
import 'lyrics_script.dart';

/// 自动搜索须先由用户开启；仅发送歌名、歌手与可选专辑，不发送音频或路径。
class LyricsController extends ChangeNotifier {
  LyricsController({LyricsPlatform? platform, DateTime Function()? now})
    : _platform = platform ?? createLyricsPlatform(),
      _now = now ?? DateTime.now;

  final LyricsPlatform _platform;
  final DateTime Function() _now;
  final _cache = <String, LyricsDocument>{};
  final _automaticMatches = <String, LyricsCandidate>{};
  Track? _track;
  Track? get track => _track;
  String? _key, _cacheKey;
  bool _automaticEnabled = false;
  bool get automaticEnabled => _automaticEnabled;
  bool _automaticSearch = false;
  Timer? _autoTimer;
  final _attempted = <String, DateTime>{};
  bool get searchingAutomatically => _busy && _automaticSearch;
  Object? get selectionIdentity => _key;
  LyricsDocument? _document;
  bool _preferSimplified = true;
  bool get preferSimplified => _preferSimplified;
  LyricsDocument? _simplifiedSource, _simplifiedDocument;
  LyricsDocument? get originalDocument => _document;
  LyricsDocument? get document {
    if (!_preferSimplified || _document == null) return _document;
    if (!identical(_simplifiedSource, _document)) {
      _simplifiedSource = _document;
      _simplifiedDocument = _document!.simplified();
    }
    return _simplifiedDocument;
  }

  Future<void> setPreferSimplified(bool value) async {
    await initialize();
    if (_disposed || value == _preferSimplified) return;
    _preferSimplified = value;
    notifyListeners();
    final write = _pendingWrite.then(
      (_) => _platform.writeCache(_serializeCache()),
    );
    _pendingWrite = write.catchError((Object _) {});
    try {
      await write;
    } catch (_) {
      if (!_disposed) {
        _notice = '字形设置仅在本次使用中有效，无法保存到本机。';
        notifyListeners();
      }
    }
  }

  List<LyricsCandidate> _candidates = const [];
  List<LyricsCandidate> get candidates => _candidates;
  String? _error, _notice;
  String? get error => _error;
  String? get notice => _notice;
  String? _searchStage;
  String? get searchStage => _busy ? _searchStage : null;
  bool _busy = false, _disposed = false, _searchInFlight = false;
  bool get busy => _busy;
  int _generation = 0;
  Future<void>? _initialization;
  Future<void> _pendingWrite = Future<void>.value();
  DateTime? _retryAt;
  Duration? get retryAfter {
    final remaining = _retryAt?.difference(_now());
    return remaining != null && remaining > Duration.zero ? remaining : null;
  }

  Future<void> initialize() => _initialization ??= _load();
  Future<void> _load() async {
    try {
      final raw = await _platform.readCache();
      if (_disposed || raw == null) return;
      if (utf8.encode(raw).length > maxLyricsCacheBytes) {
        throw const FormatException('缓存过大');
      }
      final value = jsonDecode(raw) as Map<String, dynamic>;
      if (value['version'] != 1) throw const FormatException('未知缓存版本');
      _automaticEnabled = value['automaticSearch'] == true;
      _preferSimplified = value['preferSimplified'] != false;
      final entries = value['entries'] as Map<String, dynamic>;
      for (final entry in entries.entries.take(100)) {
        try {
          final doc = LyricsDocument.fromJson(
            entry.value as Map<String, dynamic>,
          );
          if (!doc.isEmpty) {
            _cache.putIfAbsent(_stableCacheKey(entry.key), () => doc);
          }
        } catch (_) {
          // 无效条目不得阻止其他已下载歌词的加载。
        }
      }
      final automaticMatches = value['automaticMatches'];
      if (automaticMatches is Map) {
        for (final entry in automaticMatches.entries.take(100)) {
          try {
            final key = entry.key as String;
            final metadata = Map<String, dynamic>.from(entry.value as Map);
            final doc = _cache[key];
            if (doc == null) continue;
            _automaticMatches[key] = LyricsCandidate(
              id: metadata['id'] as int,
              title: metadata['title'] as String,
              artist: metadata['artist'] as String,
              album: metadata['album'] as String,
              duration: Duration(milliseconds: metadata['durationMs'] as int),
              document: doc,
            );
          } catch (_) {
            // 损坏的自动匹配来源不可当作手动确认结果复用。
            _cache.remove(entry.key);
          }
        }
      }
      _document = _cachedForTrack();
    } catch (_) {
      if (!_disposed) _notice = '无法读取本地歌词缓存。仍可导入或手动下载歌词。';
    } finally {
      if (!_disposed) {
        notifyListeners();
        _scheduleAutomatic();
      }
    }
  }

  // 旧缓存包含元数据，迁移后按同一来源的原文件定位，标签补全不丢失已选歌词。
  String _stableCacheKey(String key) {
    try {
      final parts = jsonDecode(key);
      if (parts is List && parts.length >= 4) {
        return jsonEncode(parts.take(4).toList());
      }
    } catch (_) {
      /* 无效条目留给原缓存格式校验处理。 */
    }
    return key;
  }

  LyricsDocument? _cachedForTrack() {
    final match = _automaticMatches[_cacheKey];
    if (match != null && _track != null) {
      // 手动确认的歌词始终保留；自动结果必须通过后来补全的标签再次核验。
      final track = _track!;
      final checked = track.duration > Duration.zero
          ? track
          : track.copyWith(duration: match.duration);
      if (confidentLyricsMatch(checked, [match]) == null) return null;
    }
    return _cache[_cacheKey];
  }

  Future<void> setAutomaticSearch(bool enabled) async {
    await initialize();
    if (_disposed) return;
    _automaticEnabled = enabled;
    if (!enabled) {
      _autoTimer?.cancel();
      if (_automaticSearch) cancelSearch();
    } else {
      _attempted.remove(_key);
    }
    notifyListeners();
    final write = _pendingWrite.then(
      (_) => _platform.writeCache(_serializeCache()),
    );
    _pendingWrite = write.catchError((Object _) {});
    try {
      await write;
    } catch (_) {
      if (!_disposed) {
        _notice = '自动歌词设置仅在本次使用中有效，无法保存到本机。';
        notifyListeners();
      }
    }
    _scheduleAutomatic();
  }

  void _scheduleAutomatic() {
    if (_disposed ||
        !_automaticEnabled ||
        _track == null ||
        _document != null ||
        _busy) {
      return;
    }
    _autoTimer?.cancel();
    // 等待播放网关补全标签和时长，快速切歌时只搜索最后一首。
    _autoTimer = Timer(
      const Duration(milliseconds: 700),
      () => unawaited(_autoSearch()),
    );
  }

  Future<void> _autoSearch() async {
    await initialize();
    if (_disposed ||
        !_automaticEnabled ||
        _key == null ||
        _track == null ||
        _document != null ||
        _busy ||
        _searchInFlight) {
      return;
    }
    final track = _track!;
    if (track.title.trim().isEmpty) return;
    if (_candidates.isNotEmpty) {
      if (!_automaticSearch) return;
      final match = confidentLyricsMatch(track, _candidates);
      if (match != null) await _save(match.document, automaticMatch: match);
      return;
    }
    if (retryAfter != null) {
      _notice = '歌词服务繁忙，稍后可在歌词选项中重试。';
      notifyListeners();
      return;
    }
    final attempted = _attempted[_key];
    if (attempted != null &&
        _now().difference(attempted) < const Duration(minutes: 10)) {
      return;
    }
    _attempted[_key!] = _now();
    while (_attempted.length > 100) {
      _attempted.remove(_attempted.keys.first);
    }
    await _search(
      title: track.title,
      artist: track.artist,
      album: track.album,
      automatic: true,
    );
  }

  void selectTrack(
    Track? track, {
    String source = '',
    String folder = '',
    String sourceIdentity = '',
  }) {
    if (_disposed) return;
    final key = track == null
        ? null
        : jsonEncode([
            source,
            sourceIdentity,
            sourceIdentity.isEmpty ? folder : '',
            track.id,
            track.title,
            track.artist,
            track.album,
          ]);
    final oldDuration = _track?.duration;
    _track = track;
    if (_key == key) {
      if (oldDuration != track?.duration) {
        final previous = _document;
        _document = _cachedForTrack();
        if (previous != null && _document == null) {
          _attempted.remove(_key);
          _notice = '歌曲信息已更新，正在重新核对歌词版本。';
        }
        notifyListeners();
        _scheduleAutomatic();
      }
      return;
    }
    _autoTimer?.cancel();
    _automaticSearch = false;
    _key = key;
    _cacheKey = key == null ? null : _stableCacheKey(key);
    _generation++;
    _busy = false;
    _candidates = const [];
    _error = null;
    _notice = null;
    _document = _cachedForTrack();
    notifyListeners();
    _scheduleAutomatic();
  }

  Future<void> search({
    required String title,
    required String artist,
    required String album,
  }) => _search(title: title, artist: artist, album: album);

  Future<void> _search({
    required String title,
    required String artist,
    required String album,
    bool automatic = false,
  }) async {
    if (_disposed || _key == null || _busy) return;
    _error = null;
    _notice = null;
    if (_searchInFlight) {
      _error = '上一条请求正在结束，请稍后重试。';
      notifyListeners();
      return;
    }
    if (retryAfter != null) {
      _error = '歌词服务请求过于频繁，请在 ${retryAfter!.inSeconds + 1} 秒后重试。';
      notifyListeners();
      return;
    }
    title = title.trim();
    artist = artist.trim();
    album = album.trim();
    if (title.isEmpty) {
      _error = '请输入歌名；补充歌手可提高搜索准确度。';
      notifyListeners();
      return;
    }
    if ([title, artist, album].any((value) => value.length > 300)) {
      _error = '歌名、歌手和专辑各不能超过 300 个字符。';
      notifyListeners();
      return;
    }
    _autoTimer?.cancel();
    final revision = ++_generation;
    _busy = true;
    _searchStage = '正在搜索歌曲信息…';
    _automaticSearch = automatic;
    _searchInFlight = true;
    _candidates = const [];
    final queryTrack = _track!.copyWith(
      title: title,
      artist: artist,
      album: album,
    );
    final collected = <String, LyricsCandidate>{};
    notifyListeners();
    try {
      // 每次最多五次请求：原始标签、去专辑、简/繁字形、手动仅歌名。
      // 不删除歌名中的版本标记，不向其他数据源传送信息。
      final queries =
          <({String title, String artist, String album, String stage})>[
            (title: title, artist: artist, album: album, stage: '正在搜索歌曲信息…'),
            if (album.isNotEmpty)
              (title: title, artist: artist, album: '', stage: '正在忽略专辑标签重试…'),
            (
              title: simplifyChinese(title),
              artist: simplifyChinese(artist),
              album: '',
              stage: '正在尝试简体标签…',
            ),
            (
              title: traditionalChinese(title),
              artist: traditionalChinese(artist),
              album: '',
              stage: '正在尝试繁体标签…',
            ),
            if (!automatic && artist.isNotEmpty)
              (title: title, artist: '', album: '', stage: '正在按歌名扩大搜索，请核对歌手…'),
          ];
      final visited = <String>{};
      var broadened = false;
      for (final query in queries) {
        if (!_isCurrent(revision)) return;
        if (!visited.add(
          jsonEncode([query.title, query.artist, query.album]),
        )) {
          continue;
        }
        _searchStage = query.stage;
        notifyListeners();
        // 监听器可同步取消搜索，取消后绝不再发出后备请求。
        if (!_isCurrent(revision)) return;
        if (visited.length > 1) {
          // LRCLIB 建议相邻请求间隔 200–500ms，不并行轰炸后备查询。
          await Future<void>.delayed(const Duration(milliseconds: 250));
          if (!_isCurrent(revision)) return;
        }
        final batch = await _request(query.title, query.artist, query.album);
        if (!_isCurrent(revision)) return;
        for (final candidate in batch) {
          // 相同 ID 若返回不同时间轴/元数据，仍保留歧义而不是静默覆盖。
          final identity = jsonEncode([
            candidate.id,
            candidate.title,
            candidate.artist,
            candidate.album,
            candidate.duration.inMilliseconds,
            candidate.document.text,
            candidate.document.instrumental,
          ]);
          collected.putIfAbsent(identity, () => candidate);
        }
        broadened = query.artist.isEmpty;
        final values = collected.values.toList();
        if (automatic
            ? confidentLyricsMatch(queryTrack, values) != null
            : values.any(
                (candidate) => lyricsIdentityMatches(queryTrack, candidate),
              )) {
          break;
        }
      }
      final results = rankLyricsCandidates(
        queryTrack,
        collected.values.toList(),
      );
      _candidates = List.unmodifiable(results);
      _notice = results.isEmpty
          ? '没有找到可用歌词。已尝试可用的标签组合；LRCLIB 可能尚未收录。可修改歌名/歌手，或导入本地 LRC / TXT。'
          : broadened
          ? '已扩大到仅按歌名搜索，结果可能包含其他歌手。请先预览并核对版本。'
          : '找到 ${results.length} 个版本，其中 ${results.where((c) => c.document.isSynced).length} 个有逐行时间轴。请选择并预览。';
      if (automatic) {
        final match = confidentLyricsMatch(_track!, results);
        if (match != null) {
          await _save(
            match.document,
            revision: revision,
            automaticMatch: match,
          );
        } else if (results.isNotEmpty) {
          _notice = '找到 ${results.length} 个歌词版本，暂不能可靠确认。请在歌词选项中选择。';
        }
      }
    } catch (error) {
      if (_isCurrent(revision)) {
        _error = _message(error);
        if (collected.isNotEmpty) {
          // 后续标签补全也不得将不完整搜索升级为自动选择。
          _automaticSearch = false;
          _candidates = List.unmodifiable(
            rankLyricsCandidates(queryTrack, collected.values.toList()),
          );
          _notice = '部分搜索未完成，已保留 ${collected.length} 个结果。请预览核对后手动选择，或稍后重试。';
        }
      }
    } finally {
      _searchInFlight = false;
      if (_isCurrent(revision)) {
        _busy = false;
        notifyListeners();
      } else {
        // 旧请求结束后接续当前歌曲，绝不把旧歌词贴到新歌。
        _scheduleAutomatic();
      }
    }
  }

  Future<List<LyricsCandidate>> _request(
    String title,
    String artist,
    String album,
  ) async {
    final response = await _platform
        .get(
          Uri.https('lrclib.net', '/api/search', {
            'track_name': title,
            if (artist.isNotEmpty) 'artist_name': artist,
            if (album.isNotEmpty) 'album_name': album,
          }),
        )
        .timeout(const Duration(seconds: 20));
    if (response.statusCode == 429 || response.statusCode == 503) {
      _retryAt = _now().add(_retryDelay(response.retryAfter));
      throw const LyricsException('歌词服务繁忙或请求过于频繁，请稍后重试。');
    }
    if (response.statusCode != 200) {
      throw LyricsException('歌词服务暂时不可用（${response.statusCode}），请稍后重试或导入本地歌词。');
    }
    if (utf8.encode(response.body).length > maxLyricsResponseBytes) {
      throw const FormatException('返回内容过大');
    }
    final decoded = jsonDecode(response.body);
    if (decoded is! List) throw const FormatException('返回格式错误');
    final results = <LyricsCandidate>[];
    for (final row in decoded.take(50)) {
      try {
        final result = LyricsCandidate.fromJson(row as Map<String, dynamic>);
        if (!result.document.isEmpty) results.add(result);
      } catch (_) {
        /* 跳过损坏记录，不影响有效结果。 */
      }
    }
    return results;
  }

  Future<void> choose(LyricsCandidate candidate) async {
    if (_disposed ||
        _busy ||
        !_candidates.contains(candidate) ||
        _key == null) {
      return;
    }
    await _save(candidate.document);
  }

  Future<void> importFile() async {
    if (_disposed || _busy || _key == null) return;
    final revision = ++_generation;
    _busy = true;
    _searchStage = null;
    _error = null;
    notifyListeners();
    try {
      final text = await _platform.importFile();
      if (_isCurrent(revision) && text != null) {
        await _save(LyricsDocument.parse(text), revision: revision);
      }
    } catch (error) {
      if (_isCurrent(revision)) _error = _message(error);
    } finally {
      if (_isCurrent(revision)) {
        _busy = false;
        notifyListeners();
      }
    }
  }

  Future<void> importText(String text) async {
    if (_disposed || _busy || _key == null) return;
    try {
      await _save(LyricsDocument.parse(text));
    } catch (error) {
      _error = _message(error);
      notifyListeners();
    }
  }

  Future<void> _save(
    LyricsDocument doc, {
    int? revision,
    LyricsCandidate? automaticMatch,
  }) async {
    if (doc.isEmpty) {
      throw const LyricsException('没有可显示的歌词，请选择 UTF-8 的 LRC 或纯文本内容。');
    }
    final current = revision ?? ++_generation;
    final key = _cacheKey!;
    _busy = true;
    _searchStage = null;
    _error = null;
    notifyListeners();
    await initialize();
    if (!_isCurrent(current)) return;
    _cache.remove(key);
    _cache[key] = doc;
    if (automaticMatch == null) {
      _automaticMatches.remove(key);
    } else {
      _automaticMatches[key] = automaticMatch;
    }
    _document = doc;
    _candidates = const [];
    var raw = _serializeCache();
    while ((_cache.length > 100 ||
            utf8.encode(raw).length > maxLyricsCacheBytes - 1024) &&
        _cache.length > 1) {
      _automaticMatches.remove(_cache.keys.first);
      _cache.remove(_cache.keys.first);
      raw = _serializeCache();
    }
    // 串行写入，防止先发起但较慢的保存覆盖后续结果。
    final write = _pendingWrite.then((_) => _platform.writeCache(raw));
    _pendingWrite = write.catchError((Object _) {});
    try {
      await write;
      if (_isCurrent(current)) _notice = '已保存到本机，可离线显示。不会修改原始音乐文件。';
    } catch (_) {
      if (_isCurrent(current)) _notice = '歌词可在本次使用中显示，但保存失败。请检查本机存储或浏览器隐私设置。';
    } finally {
      if (_isCurrent(current)) {
        _busy = false;
        notifyListeners();
      }
    }
  }

  String _serializeCache() => jsonEncode({
    'version': 1,
    'automaticSearch': _automaticEnabled,
    'preferSimplified': _preferSimplified,
    'entries': _cache.map((key, value) => MapEntry(key, value.toJson())),
    'automaticMatches': _automaticMatches.map(
      (key, value) => MapEntry(key, {
        'id': value.id,
        'title': value.title,
        'artist': value.artist,
        'album': value.album,
        'durationMs': value.duration.inMilliseconds,
      }),
    ),
  });

  Duration _retryDelay(String? value) {
    final seconds = int.tryParse(value ?? '');
    if (seconds != null) {
      return Duration(seconds: seconds.clamp(1, 2147483646) + 1);
    }
    final date = DateTime.tryParse(value ?? '') ?? _httpDate(value);
    if (date != null && date.isAfter(_now())) {
      return date.difference(_now()) + const Duration(seconds: 1);
    }
    return const Duration(seconds: 61);
  }

  // Retry-After 的 HTTP 日期采用 RFC 7231，而非 ISO-8601；Web 端避免使用 dart:io。
  DateTime? _httpDate(String? value) {
    final match = RegExp(
      r'^\w{3}, (\d{2}) (\w{3}) (\d{4}) (\d{2}):(\d{2}):(\d{2}) GMT$',
    ).firstMatch(value ?? '');
    if (match == null) return null;
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    final month = months.indexOf(match.group(2)!);
    if (month < 0) return null;
    return DateTime.utc(
      int.parse(match.group(3)!),
      month + 1,
      int.parse(match.group(1)!),
      int.parse(match.group(4)!),
      int.parse(match.group(5)!),
      int.parse(match.group(6)!),
    );
  }

  // 用户编辑查询或本地导入时暂停当前曲目的自动尝试。
  void suspendAutomaticSelection() {
    _autoTimer?.cancel();
    if (_key != null) _attempted[_key!] = _now();
    if (searchingAutomatically) cancelSearch();
    _automaticSearch = false;
  }

  void cancelSearch() {
    if (_disposed) return;
    _autoTimer?.cancel();
    if (_key != null) _attempted[_key!] = _now();
    _generation++;
    _busy = false;
    _candidates = const [];
    _error = null;
    _notice = null;
    notifyListeners();
  }

  void clearError() {
    if (_disposed) return;
    _error = null;
    notifyListeners();
  }

  bool _isCurrent(int revision) => !_disposed && revision == _generation;
  String _message(Object error) => switch (error) {
    LyricsException(:final message) => message,
    PlatformException(:final message) => message ?? '无法读取歌词文件，请重试。',
    FormatException() => '歌词格式无效或内容过大。请使用不超过 256 KB 的 UTF-8 LRC / TXT。',
    _ => '暂时无法获取歌词。请检查网络或浏览器跨域限制，也可导入本地歌词。',
  };

  @override
  void dispose() {
    _disposed = true;
    _autoTimer?.cancel();
    _generation++;
    _platform.dispose();
    super.dispose();
  }
}

class LyricsException implements Exception {
  const LyricsException(this.message);
  final String message;
}
