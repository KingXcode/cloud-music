import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../models.dart';
import 'lyrics_factory.dart';
import 'lyrics_models.dart';
import 'lyrics_platform.dart';

/// 选择或播放歌曲不会发起网络请求。只有用户在知情后主动搜索，
/// 才会发送其填写的字段。
class LyricsController extends ChangeNotifier {
  LyricsController({LyricsPlatform? platform, DateTime Function()? now})
    : _platform = platform ?? createLyricsPlatform(),
      _now = now ?? DateTime.now;

  final LyricsPlatform _platform;
  final DateTime Function() _now;
  final _cache = <String, LyricsDocument>{};
  Track? _track;
  Track? get track => _track;
  String? _key;
  Object? get selectionIdentity => _key;
  LyricsDocument? _document;
  LyricsDocument? get document => _document;
  List<LyricsCandidate> _candidates = const [];
  List<LyricsCandidate> get candidates => _candidates;
  String? _error, _notice;
  String? get error => _error;
  String? get notice => _notice;
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
      final entries = value['entries'] as Map<String, dynamic>;
      for (final entry in entries.entries.take(100)) {
        try {
          final doc = LyricsDocument.fromJson(
            entry.value as Map<String, dynamic>,
          );
          if (!doc.isEmpty) _cache.putIfAbsent(entry.key, () => doc);
        } catch (_) {
          // 无效条目不得阻止其他已下载歌词的加载。
        }
      }
      _document = _cache[_key];
    } catch (_) {
      if (!_disposed) _notice = '无法读取本地歌词缓存。仍可导入或手动下载歌词。';
    } finally {
      if (!_disposed) notifyListeners();
    }
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
    _track = track;
    if (_key == key) return;
    _key = key;
    _generation++;
    _busy = false;
    _candidates = const [];
    _error = null;
    _notice = null;
    _document = _cache[key];
    notifyListeners();
  }

  Future<void> search({
    required String title,
    required String artist,
    required String album,
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
    if (title.isEmpty || artist.isEmpty) {
      _error = '请输入歌名和歌手，以免下载错误版本的歌词。';
      notifyListeners();
      return;
    }
    if ([title, artist, album].any((value) => value.length > 300)) {
      _error = '歌名、歌手和专辑各不能超过 300 个字符。';
      notifyListeners();
      return;
    }
    final revision = ++_generation;
    _busy = true;
    _searchInFlight = true;
    _candidates = const [];
    notifyListeners();
    try {
      final response = await _platform
          .get(
            Uri.https('lrclib.net', '/api/search', {
              'track_name': title,
              'artist_name': artist,
              if (album.isNotEmpty) 'album_name': album,
            }),
          )
          .timeout(const Duration(seconds: 20));
      // 即使所选歌曲已变化，限流仍属于当前服务提供方。
      if (response.statusCode == 429 || response.statusCode == 503) {
        _retryAt = _now().add(_retryDelay(response.retryAfter));
        throw const LyricsException('歌词服务繁忙或请求过于频繁，请稍后重试。');
      }
      if (response.statusCode != 200) {
        throw LyricsException(
          '歌词服务暂时不可用（${response.statusCode}），请稍后重试或导入本地歌词。',
        );
      }
      if (!_isCurrent(revision)) return;
      if (utf8.encode(response.body).length > maxLyricsResponseBytes) {
        throw const FormatException('返回内容过大');
      }
      final decoded = jsonDecode(response.body);
      if (decoded is! List) throw const FormatException('返回格式错误');
      final results = <LyricsCandidate>[];
      for (final row in decoded.take(20)) {
        try {
          final result = LyricsCandidate.fromJson(row as Map<String, dynamic>);
          if (!result.document.isEmpty) results.add(result);
        } catch (_) {
          // 跳过格式错误的记录，避免将其视为有效匹配。
        }
      }
      _candidates = List.unmodifiable(results);
      _notice = results.isEmpty
          ? '没有找到歌词。可修改歌名/歌手、清空专辑后再试，或导入本地 LRC / TXT。'
          : '请选择对应版本。搜索结果可能不准确，请核对歌手、专辑和时长。';
    } catch (error) {
      if (_isCurrent(revision)) _error = _message(error);
    } finally {
      _searchInFlight = false;
      if (_isCurrent(revision)) {
        _busy = false;
        notifyListeners();
      }
    }
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

  Future<void> _save(LyricsDocument doc, {int? revision}) async {
    if (doc.isEmpty) {
      throw const LyricsException('没有可显示的歌词，请选择 UTF-8 的 LRC 或纯文本内容。');
    }
    final current = revision ?? ++_generation;
    final key = _key!;
    _busy = true;
    _error = null;
    notifyListeners();
    await initialize();
    if (!_isCurrent(current)) return;
    _cache.remove(key);
    _cache[key] = doc;
    _document = doc;
    _candidates = const [];
    var raw = _serializeCache();
    while ((_cache.length > 100 ||
            utf8.encode(raw).length > maxLyricsCacheBytes - 1024) &&
        _cache.length > 1) {
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
    'entries': _cache.map((key, value) => MapEntry(key, value.toJson())),
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

  void cancelSearch() {
    if (_disposed) return;
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
    _generation++;
    _platform.dispose();
    super.dispose();
  }
}

class LyricsException implements Exception {
  const LyricsException(this.message);
  final String message;
}
