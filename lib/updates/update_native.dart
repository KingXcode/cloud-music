import 'dart:async';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';

import 'release_api.dart';
import 'update_backend.dart';

UpdateBackend createPlatformUpdateBackend() => NativeUpdateBackend();

class NativeUpdateBackend implements UpdateBackend {
  NativeUpdateBackend({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel('dev.cloudmusic/app_updates');
  final MethodChannel _channel;
  HttpClient? _downloadClient;
  Future<void>? _pendingDownload;
  int _generation = 0;
  String? _downloadedPath;

  @override
  Future<InstalledVersion> getInstalledVersion() async {
    if (!Platform.isAndroid && !Platform.isMacOS) {
      return InstalledVersion(
        version: '由安装渠道管理',
        build: '—',
        platform: Platform.operatingSystem,
      );
    }
    final result = await _channel.invokeMapMethod<String, dynamic>('getInfo');
    if (result == null) throw const UpdateException('无法读取当前安装版本。');
    return InstalledVersion(
      version: result['version'] as String,
      build: '${result['build']}',
      platform: result['platform'] as String,
      architecture: result['architecture'] as String,
    );
  }

  @override
  Future<UpdateRelease?> check(InstalledVersion current) =>
      ReleaseApi(_fetch).check(current);

  bool _allowed(Uri uri) {
    if (uri.scheme != 'https' ||
        uri.port != 443 ||
        uri.userInfo.isNotEmpty ||
        uri.fragment.isNotEmpty) {
      return false;
    }
    if (uri.host == 'api.github.com') return uri == releaseApiUrl;
    if (uri.host == 'github.com') {
      return uri.path.startsWith('/$updateRepository/releases/download/');
    }
    return uri.host == 'release-assets.githubusercontent.com';
  }

  Future<HttpClientResponse> _get(HttpClient client, Uri uri) async {
    var next = uri;
    for (var redirects = 0; redirects <= 5; redirects++) {
      if (!_allowed(next)) throw const UpdateException('更新服务器重定向到不受信任的地址。');
      final request = await client
          .getUrl(next)
          .timeout(const Duration(seconds: 20));
      request.followRedirects = false;
      request.headers.set(HttpHeaders.userAgentHeader, 'Cloud-Music-Updater');
      request.headers.set(
        HttpHeaders.acceptHeader,
        next.host == 'api.github.com'
            ? 'application/vnd.github+json'
            : 'application/octet-stream',
      );
      final response = await request.close().timeout(
        const Duration(seconds: 30),
      );
      if (const [301, 302, 303, 307, 308].contains(response.statusCode)) {
        final location = response.headers.value(HttpHeaders.locationHeader);
        if (location == null) throw const UpdateException('下载服务器返回了无效跳转。');
        next = next.resolve(location);
        // Do not drain arbitrary redirect bodies before applying URL policy.
        await response.listen((_) {}).cancel();
        continue;
      }
      if (response.statusCode != 200) {
        final status = response.statusCode;
        await response.listen((_) {}).cancel();
        throw UpdateException(
          status == 403 || status == 429
              ? '版本检查受到 GitHub 频率限制，请稍后重试。'
              : '更新服务器暂时不可用（HTTP $status）。',
        );
      }
      return response;
    }
    throw const UpdateException('下载服务器跳转次数过多。');
  }

  Future<List<int>> _fetch(Uri url, int limit) async {
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 20);
    try {
      final response = await _get(client, url);
      final result = <int>[];
      await for (final chunk in response.timeout(const Duration(seconds: 30))) {
        if (result.length + chunk.length > limit) {
          throw const UpdateException('更新信息超过允许大小。');
        }
        result.addAll(chunk);
      }
      return result;
    } finally {
      client.close(force: true);
    }
  }

  @override
  Future<void> download(
    UpdateRelease release,
    void Function(int, int?) onProgress,
  ) async {
    // A cancelled transfer must finish closing its file before another starts.
    final generation = ++_generation;
    final previous = _pendingDownload;
    if (previous != null) {
      try {
        await previous;
      } catch (_) {}
    }
    if (generation != _generation) throw const UpdateCancelled();
    final work = _download(release, onProgress, generation);
    _pendingDownload = work;
    try {
      await work;
    } finally {
      if (identical(_pendingDownload, work)) _pendingDownload = null;
    }
  }

  Future<void> _download(
    UpdateRelease release,
    void Function(int, int?) onProgress,
    int generation,
  ) async {
    final asset = release.asset;
    if (asset == null || !RegExp(r'^[a-f0-9]{64}$').hasMatch(asset.sha256)) {
      throw const UpdateException('缺少更新包。');
    }
    final directory = await _channel.invokeMethod<String>(
      'getDownloadDirectory',
    );
    if (directory == null) throw const UpdateException('无法创建更新缓存。');
    final ext = Platform.isAndroid ? 'apk' : 'dmg';
    final target = File('$directory/update-${asset.sha256}.$ext');
    final part = File('${target.path}.part');
    _downloadedPath = null;
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 20);
    _downloadClient = client;
    IOSink? sink;
    try {
      if (generation != _generation) throw const UpdateCancelled();
      // Remove only our own previous partial files, never music or user files.
      await for (final entry in Directory(directory).list(followLinks: false)) {
        if (entry is File &&
            RegExp(r'^update-[a-f0-9]{64}\.(apk|dmg)(\.part)?$')
                .hasMatch(entry.uri.pathSegments.last)) {
          await entry.delete();
        }
      }
      final response = await _get(client, asset.url);
      if (response.contentLength >= 0 && response.contentLength != asset.size) {
        throw const UpdateException('更新包大小与清单不一致。');
      }
      sink = part.openWrite();
      var received = 0;
      onProgress(0, asset.size);
      await for (final chunk in response.timeout(const Duration(seconds: 30))) {
        if (generation != _generation) throw const UpdateCancelled();
        received += chunk.length;
        if (received > asset.size) throw const UpdateException('更新包超过清单大小。');
        sink.add(chunk);
        // Flush gives bounded buffering and exposes disk-full errors promptly.
        await sink.flush();
        onProgress(received, asset.size);
      }
      await sink.close();
      sink = null;
      if (generation != _generation) throw const UpdateCancelled();
      await _verifyFile(part, asset);
      if (generation != _generation) throw const UpdateCancelled();
      await part.rename(target.path);
      _downloadedPath = target.path;
    } catch (error) {
      if (generation != _generation) throw const UpdateCancelled();
      if (error is UpdateException) rethrow;
      throw const UpdateException('下载失败，请检查网络及设备剩余空间后重试。');
    } finally {
      try {
        await sink?.close();
      } catch (_) {}
      client.close(force: true);
      if (identical(_downloadClient, client)) _downloadClient = null;
      if (await part.exists()) await part.delete();
    }
  }

  Future<void> _verifyFile(File file, UpdateAsset asset) async {
    if (!await file.exists() ||
        await file.length() != asset.size ||
        (await sha256.bind(file.openRead()).first).toString() != asset.sha256) {
      throw const UpdateException('更新包完整性校验失败，请重新下载。');
    }
  }

  @override
  Future<String> install(UpdateRelease release) async {
    final path = _downloadedPath, asset = release.asset;
    if (path == null || asset == null) {
      throw const UpdateException('更新包已失效，请重新下载。');
    }
    await _verifyFile(File(path), asset);
    try {
      return await _channel.invokeMethod<String>('installDownloaded', {
            'path': path,
          }) ??
          'opened';
    } on PlatformException catch (error) {
      final message = switch (error.code) {
        'signature_mismatch' =>
          '新版 APK 与当前应用的签名不同，不能覆盖安装。请联系发行者提供同一签名的更新；不要为更新自动卸载或清空数据。',
        'version_not_newer' => '安装包的系统版本号不高于当前版本，请重新检查更新。',
        'package_mismatch' => '安装包不属于云听，已拒绝安装。',
        'invalid_package' => '安装包无效或缓存已被清理，请重新下载。',
        'quarantine_failed' => 'macOS 无法为下载包启用安全检查，已停止打开。',
        'install_unavailable' => '系统安装器或安装权限不可用，请检查设备设置。',
        'open_failed' => '系统无法打开安装包，请稍后重试。',
        _ => '无法打开安装程序，请重试。',
      };
      throw UpdateException(message);
    }
  }

  @override
  void cancel() {
    ++_generation;
    _downloadClient?.close(force: true);
  }

  @override
  void dispose() => cancel();
}
