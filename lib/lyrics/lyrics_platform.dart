class LyricsHttpResponse {
  const LyricsHttpResponse(this.statusCode, this.body, {this.retryAfter});
  final int statusCode;
  final String body;
  final String? retryAfter;
}

abstract interface class LyricsPlatform {
  Future<LyricsHttpResponse> get(Uri uri);
  Future<String?> readCache();
  Future<void> writeCache(String value);
  Future<String?> importFile();
  void dispose();
}

const lyricsClientIdentity =
    'CloudMusic/0.2.0 (https://github.com/KingXcode/cloud-music)';
const maxLyricsCacheBytes = 2 * 1024 * 1024;
const maxLyricsResponseBytes = 4 * 1024 * 1024;
