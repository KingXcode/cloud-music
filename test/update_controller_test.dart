import 'dart:async';

import 'package:cloud_music/updates/update_backend.dart';
import 'package:cloud_music/updates/update_controller.dart';
import 'package:flutter_test/flutter_test.dart';

UpdateRelease updateTestRelease({bool withAsset = true}) => UpdateRelease(
  version: '0.7.0',
  build: '9',
  notes: '更新下载进度与安全校验。',
  releasePage: Uri.parse(
    'https://github.com/KingXcode/cloud-music/releases/tag/v0.7.0-preview',
  ),
  asset: withAsset
      ? UpdateAsset(
          name: 'cloud-music-android-test-signed.apk',
          url: Uri.parse(
            'https://github.com/KingXcode/cloud-music/releases/download/v0.7.0-preview/cloud-music-android-test-signed.apk',
          ),
          size: 2048,
          sha256: '0' * 64,
        )
      : null,
);

class ControlledUpdateBackend implements UpdateBackend {
  ControlledUpdateBackend({this.platform = 'android'});
  final String platform;
  int getInfoCalls = 0;
  int checkCalls = 0;
  int downloadCalls = 0;
  int installCalls = 0;
  int cancelCalls = 0;
  int disposeCalls = 0;
  Completer<UpdateRelease?>? checkResult;
  Completer<String>? installResult;
  String installedResult = 'opened';
  UpdateRelease? next = updateTestRelease();
  final downloads = <Completer<void>>[];
  final progressCallbacks = <void Function(int, int?)>[];

  @override
  Future<InstalledVersion> getInstalledVersion() async {
    getInfoCalls++;
    return InstalledVersion(
      version: '0.6.0',
      build: '8',
      platform: platform,
      architecture: 'arm64-v8a',
    );
  }

  @override
  Future<UpdateRelease?> check(InstalledVersion current) async {
    checkCalls++;
    return checkResult == null ? next : checkResult!.future;
  }

  @override
  Future<void> download(
    UpdateRelease release,
    void Function(int, int?) onProgress,
  ) {
    downloadCalls++;
    final completion = Completer<void>();
    downloads.add(completion);
    progressCallbacks.add(onProgress);
    return completion.future;
  }

  @override
  Future<String> install(UpdateRelease release) async {
    installCalls++;
    return installResult == null ? installedResult : installResult!.future;
  }

  @override
  void cancel() => cancelCalls++;
  @override
  void dispose() => disposeCalls++;
}

void main() {
  late ControlledUpdateBackend backend;
  late UpdateController controller;
  setUp(() {
    backend = ControlledUpdateBackend();
    controller = UpdateController(backend);
  });
  tearDown(() => controller.dispose());

  test(
    'checking never downloads or installs and ignores repeated clicks',
    () async {
      backend.checkResult = Completer<UpdateRelease?>();
      final first = controller.check();
      await controller.check();
      await Future<void>.delayed(Duration.zero);
      expect(controller.phase, UpdatePhase.checking);
      expect(backend.checkCalls, 1);
      backend.checkResult!.complete(updateTestRelease());
      await first;
      expect(controller.phase, UpdatePhase.available);
      expect(backend.downloadCalls, 0);
      expect(backend.installCalls, 0);
    },
  );

  test(
    'no compatible release is a current state, not an install prompt',
    () async {
      backend.next = null;
      await controller.check();
      expect(controller.phase, UpdatePhase.current);
      expect(controller.release, isNull);
      await controller.download();
      await controller.install();
      expect(backend.downloadCalls, 0);
      expect(backend.installCalls, 0);
    },
  );

  test(
    'download is single-flight and installation requires an explicit call',
    () async {
      await controller.check();
      final first = controller.download();
      await controller.download();
      await controller.check();
      await controller.install();
      expect(backend.downloadCalls, 1);
      expect(backend.checkCalls, 1);
      expect(backend.installCalls, 0);
      backend.progressCallbacks.single(1024, 2048);
      expect(controller.progress, .5);
      backend.downloads.single.complete();
      await first;
      expect(controller.phase, UpdatePhase.ready);
      expect(backend.installCalls, 0);
      await controller.check();
      await controller.download();
      expect(controller.phase, UpdatePhase.ready);
      expect(backend.downloadCalls, 1);
      await controller.install();
      expect(backend.installCalls, 1);
      expect(controller.phase, UpdatePhase.ready);
    },
  );

  test(
    'unknown totals stay indeterminate and invalid ratios are clamped',
    () async {
      await controller.check();
      final transfer = controller.download();
      for (final total in [null, 0, -1]) {
        backend.progressCallbacks.single(1024, total);
        expect(controller.progress, isNull);
      }
      backend.progressCallbacks.single(4096, 2048);
      expect(controller.progress, 1);
      backend.progressCallbacks.single(-1, 2048);
      expect(controller.progress, 0);
      backend.downloads.single.complete();
      await transfer;
    },
  );

  test('cancel immediately returns to available and ignores stale progress/success', () async {
    await controller.check();
    final old = controller.download();
    controller.cancelDownload();
    controller.cancelDownload();
    expect(backend.cancelCalls, 1);
    expect(controller.phase, UpdatePhase.available);
    expect(controller.received, 0);
    expect(controller.total, isNull);
    backend.progressCallbacks.first(2048, 2048);
    backend.downloads.first.complete();
    await old;
    expect(controller.phase, UpdatePhase.available);
    expect(controller.received, 0);
    expect(backend.installCalls, 0);
  });

  test('stale cancelled transfer cannot overwrite a newer download', () async {
    await controller.check();
    final old = controller.download();
    controller.cancelDownload();
    final current = controller.download();
    backend.progressCallbacks.last(512, 2048);
    backend.progressCallbacks.first(2048, 2048);
    backend.downloads.first.completeError(const UpdateException('旧下载失败'));
    await old;
    expect(controller.phase, UpdatePhase.downloading);
    expect(controller.received, 512);
    expect(controller.message, isNull);
    backend.downloads.last.complete();
    await current;
    expect(controller.phase, UpdatePhase.ready);
  });

  test(
    'verification/download failure cannot enable installation and can retry',
    () async {
      await controller.check();
      final failed = controller.download();
      backend.downloads.first.completeError(const UpdateException('校验失败'));
      await failed;
      expect(controller.phase, UpdatePhase.failed);
      expect(controller.message, '校验失败');
      await controller.install();
      expect(backend.installCalls, 0);
      final retry = controller.download();
      backend.downloads.last.complete();
      await retry;
      expect(controller.phase, UpdatePhase.ready);
    },
  );

  test(
    'backend cancellation does not become a failed or ready download',
    () async {
      await controller.check();
      final transfer = controller.download();
      backend.downloads.single.completeError(const UpdateCancelled());
      await transfer;
      expect(controller.phase, UpdatePhase.available);
      expect(controller.message, contains('取消'));
    },
  );

  test(
    'installation is single-flight and preserves package after failure',
    () async {
      await controller.check();
      final transfer = controller.download();
      backend.downloads.single.complete();
      await transfer;
      backend.installResult = Completer<String>();
      final first = controller.install();
      await controller.install();
      expect(backend.installCalls, 1);
      backend.installResult!.completeError(const UpdateException('系统未允许安装'));
      await first;
      expect(controller.phase, UpdatePhase.ready);
      expect(controller.message, '系统未允许安装');
      backend.installResult = null;
      backend.installedResult = 'permissionRequired';
      await controller.install();
      expect(backend.installCalls, 2);
      expect(controller.phase, UpdatePhase.ready);
      expect(controller.message, contains('系统设置'));
    },
  );

  test(
    'check failure is retryable and does not expose raw exception details',
    () async {
      backend.checkResult = Completer<UpdateRelease?>();
      final first = controller.check();
      backend.checkResult!.completeError(StateError('private-debug-data'));
      await first;
      expect(controller.phase, UpdatePhase.failed);
      expect(controller.message, isNot(contains('private-debug-data')));
      backend.checkResult = null;
      await controller.check();
      expect(controller.phase, UpdatePhase.available);
    },
  );

  test('unsupported iOS does not query releases or offer a sideload', () async {
    final ios = ControlledUpdateBackend(platform: 'ios');
    final c = UpdateController(ios);
    await c.check();
    expect(c.phase, UpdatePhase.unsupported);
    expect(c.message, contains('App Store'));
    expect(ios.checkCalls, 0);
    c.dispose();
  });

  test(
    'ready packages can be explicitly redownloaded without installing',
    () async {
      await controller.check();
      final first = controller.download();
      backend.downloads.first.complete();
      await first;
      final retry = controller.redownload();
      await controller.redownload();
      expect(controller.phase, UpdatePhase.downloading);
      expect(backend.downloadCalls, 2);
      expect(backend.installCalls, 0);
      backend.downloads.last.complete();
      await retry;
      expect(controller.phase, UpdatePhase.ready);
    },
  );

  testWidgets('automatic checks never download and preserve a ready package', (
    tester,
  ) async {
    final backend = ControlledUpdateBackend();
    final controller = UpdateController(backend);
    await controller.initialize();
    expect(backend.checkCalls, 1);
    await tester.pump(const Duration(hours: 6));
    expect(backend.checkCalls, 2);
    expect(backend.downloadCalls, 0);
    expect(backend.installCalls, 0);
    final transfer = controller.download();
    await tester.pump(const Duration(hours: 6));
    expect(backend.checkCalls, 2);
    backend.downloads.single.complete();
    await transfer;
    await tester.pump(const Duration(hours: 6));
    expect(backend.checkCalls, 2);
    expect(controller.phase, UpdatePhase.ready);
    controller.dispose();
  });

  test(
    'disposed controller ignores late completion and future operations',
    () async {
      final b = ControlledUpdateBackend();
      final c = UpdateController(b);
      var notifications = 0;
      c.addListener(() => notifications++);
      await c.check();
      final transfer = c.download();
      c.dispose();
      final atDisposal = notifications;
      b.progressCallbacks.single(2048, 2048);
      b.downloads.single.complete();
      await transfer;
      await c.check();
      await c.download();
      await c.install();
      expect(notifications, atDisposal);
      expect(b.disposeCalls, 1);
      expect(b.downloadCalls, 1);
      expect(b.installCalls, 0);
    },
  );
}
