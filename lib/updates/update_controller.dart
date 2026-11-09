import 'dart:async';

import 'package:flutter/foundation.dart';

import 'update_backend.dart';

enum UpdatePhase {
  idle,
  checking,
  current,
  available,
  downloading,
  ready,
  installing,
  unsupported,
  failed,
}

class UpdateController extends ChangeNotifier {
  UpdateController(this.backend);
  final UpdateBackend backend;
  InstalledVersion? installed;
  UpdateRelease? release;
  UpdatePhase phase = UpdatePhase.idle;
  String? message;
  int received = 0;
  int? total;
  int _operation = 0;
  bool _disposed = false;
  Timer? _timer;

  bool get busy => const [
    UpdatePhase.checking,
    UpdatePhase.downloading,
    UpdatePhase.installing,
  ].contains(phase);
  double? get progress =>
      total != null && total! > 0 ? (received / total!).clamp(0.0, 1.0) : null;

  Future<void> initialize() async {
    await check();
    if (_disposed) return;
    // Visible status only: never download, install, or interrupt playback here.
    _timer ??= Timer.periodic(const Duration(hours: 6), (_) {
      if (!busy && phase != UpdatePhase.ready) unawaited(check());
    });
  }

  Future<void> check() async {
    if (busy || phase == UpdatePhase.ready || _disposed) return;
    final op = ++_operation;
    phase = UpdatePhase.checking;
    message = null;
    _notify();
    try {
      installed ??= await backend.getInstalledVersion();
      if (!_live(op)) return;
      if (!installed!.supported) {
        phase = UpdatePhase.unsupported;
        message = '此平台由原安装渠道更新。iPhone / iPad 请使用 App Store 或 TestFlight；当前仓库不提供 iOS 安装包。';
      } else {
        final next = await backend.check(installed!);
        if (!_live(op)) return;
        release = next;
        phase = next == null ? UpdatePhase.current : UpdatePhase.available;
        message = next == null ? '当前没有适用于此设备的更高版本。' : null;
      }
    } catch (error) {
      if (!_live(op)) return;
      phase = UpdatePhase.failed;
      message = _error(error);
    }
    _notify();
  }

  Future<void> download() async {
    if (busy || release == null || phase == UpdatePhase.ready || _disposed) {
      return;
    }
    final op = ++_operation;
    phase = UpdatePhase.downloading;
    message = null;
    received = 0;
    total = release!.asset?.size;
    _notify();
    try {
      await backend.download(release!, (bytes, size) {
        if (!_live(op)) return;
        received = bytes;
        total = size;
        _notify();
      });
      if (!_live(op)) return;
      phase = UpdatePhase.ready;
      message = installed?.platform == 'web'
          ? '新版已下载并校验。点击“重载使用新版”后生效，会停止当前播放。'
          : '下载完成并通过完整性校验，可以安装新版。';
    } on UpdateCancelled {
      if (!_live(op)) return;
      phase = UpdatePhase.available;
      message = '下载已取消，可重新开始。';
    } catch (error) {
      if (!_live(op)) return;
      phase = UpdatePhase.failed;
      message = _error(error);
    }
    _notify();
  }

  Future<void> redownload() async {
    if (phase != UpdatePhase.ready || _disposed) return;
    phase = UpdatePhase.available;
    await download();
  }

  void cancelDownload() {
    if (phase != UpdatePhase.downloading) return;
    ++_operation;
    backend.cancel();
    phase = UpdatePhase.available;
    message = '下载已取消，可重新开始。';
    received = 0;
    total = null;
    _notify();
  }

  Future<void> install() async {
    if (phase != UpdatePhase.ready || release == null || _disposed) return;
    final op = ++_operation;
    phase = UpdatePhase.installing;
    _notify();
    try {
      final result = await backend.install(release!);
      if (!_live(op)) return;
      phase = UpdatePhase.ready;
      message = result == 'permissionRequired'
          ? '请在系统设置中允许此应用安装更新。返回后再次点“安装新版”。'
          : installed?.platform == 'macos'
          ? '已打开 DMG。请在系统窗口中将新版拖入“应用程序”替换，完成后重新打开云听。'
          : '已打开系统安装界面，请在系统界面确认。取消后可再次安装。';
    } catch (error) {
      if (!_live(op)) return;
      phase = UpdatePhase.ready;
      message = _error(error);
    }
    _notify();
  }

  bool _live(int op) => !_disposed && op == _operation;
  void _notify() {
    if (!_disposed) notifyListeners();
  }

  String _error(Object error) =>
      error is UpdateException ? error.message : '更新暂时失败，请检查网络后重试。';
  @override
  void dispose() {
    _disposed = true;
    ++_operation;
    _timer?.cancel();
    backend.dispose();
    super.dispose();
  }
}
