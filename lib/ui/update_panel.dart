import 'package:flutter/cupertino.dart';

import 'cupertino_settings.dart';

import '../updates/update_controller.dart';

String updateBytes(int count) => count < 1024 * 1024
    ? '${(count / 1024).toStringAsFixed(0)} KB'
    : '${(count / (1024 * 1024)).toStringAsFixed(1)} MB';

Future<void> showAppUpdates(
  BuildContext context,
  UpdateController controller,
) => showSettingsPopup<void>(
  context: context,
  builder: (_) => UpdatePanel(controller: controller),
);

/// Stays visible while the sheet is closed; downloads never block music controls.
class UpdateBanner extends StatelessWidget {
  const UpdateBanner({super.key, required this.controller});
  final UpdateController controller;
  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: controller,
    builder: (context, _) {
      final c = controller;
      if (!const [
        UpdatePhase.available,
        UpdatePhase.downloading,
        UpdatePhase.ready,
        UpdatePhase.installing,
      ].contains(c.phase)) {
        return const SizedBox.shrink();
      }
      final downloading = c.phase == UpdatePhase.downloading;
      return ColoredBox(
        color: CupertinoTheme.of(context).primaryColor.withValues(alpha: .08),
        child: CupertinoButton(
          padding: EdgeInsets.zero,
          key: const Key('update-banner'),
          onPressed: () => showAppUpdates(context, c),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(CupertinoIcons.arrow_down_circle, size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        downloading
                            ? '正在下载新版 · ${_progressLabel(c)}'
                            : c.phase == UpdatePhase.available
                            ? '发现弦泊 ${c.release!.version} · 查看更新'
                            : '新版已下载 · 点击安装',
                        style: const TextStyle(fontSize: 13),
                      ),
                    ),
                    const Icon(CupertinoIcons.chevron_forward, size: 18),
                  ],
                ),
                if (downloading) ...[
                  const SizedBox(height: 6),
                  SettingsProgress(value: c.progress, semanticsLabel: '新版下载进度'),
                ],
              ],
            ),
          ),
        ),
      );
    },
  );
}

String _progressLabel(UpdateController c) => c.total != null && c.total! > 0
    ? '${((c.progress ?? 0) * 100).floor()}% · ${updateBytes(c.received)} / ${updateBytes(c.total!)}'
    : '${updateBytes(c.received)}（总大小未知）';

class UpdatePanel extends StatelessWidget {
  const UpdatePanel({super.key, required this.controller});
  final UpdateController controller;
  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: controller,
    builder: (context, _) {
      final c = controller;
      final platform = c.installed?.platform;
      final downloading = c.phase == UpdatePhase.downloading;
      final ready = c.phase == UpdatePhase.ready;
      return ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * .85,
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Expanded(
                    child: Text(
                      '应用更新',
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  SettingsIconButton(
                    tooltip: '关闭更新面板',
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(CupertinoIcons.xmark_circle_fill),
                  ),
                ],
              ),
              Text(
                c.installed == null
                    ? '正在读取版本…'
                    : '当前版本 ${c.installed!.version} (${c.installed!.build})',
              ),
              const SizedBox(height: 12),
              Text(
                platform == 'web'
                    ? '自动检查网站的新版本，下载完成后由你决定何时重载。重载会停止当前播放。浏览器可能要求重新选择音乐目录。'
                    : platform == 'macos'
                    ? '自动检查新版本；点击下方按钮，用浏览器从官方发布页面下载 DMG，再安装到“应用程序”。当前预览版未经过 Apple 公证，首次打开可能需要在“隐私与安全性”中确认。'
                    : platform == 'android'
                    ? '自动检查新版本；下载后交给系统安装器确认。仅接受与当前应用签名一致、版本更高的 APK。'
                    : '按原安装渠道更新。',
                style: TextStyle(
                  color: CupertinoColors.secondaryLabel.resolveFrom(context),
                  height: 1.5,
                ),
              ),
              if (platform != null &&
                  platform != 'web' &&
                  c.installed!.supported) ...[
                const SizedBox(height: 8),
                Text(
                  platform == 'android'
                      ? '来源：KingXcode/cloud-music 的 GitHub 预览发布。当前使用测试签名；不同签名的预览版不能覆盖安装。'
                      : '来源：KingXcode/cloud-music 的 GitHub 预览发布。校验确保下载完整；当前版本未使用 Developer ID 签名或 Apple 公证。',
                  style: const TextStyle(fontSize: 12),
                ),
              ],
              if (c.release != null) ...[
                const SizedBox(height: 20),
                Text(
                  '新版本 ${c.release!.version} (${c.release!.build})',
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (c.release!.notes.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      c.release!.notes,
                      style: const TextStyle(height: 1.4),
                    ),
                  ),
              ],
              if (downloading) ...[
                const SizedBox(height: 20),
                SettingsProgress(value: c.progress, semanticsLabel: '新版下载进度'),
                const SizedBox(height: 8),
                Text(_progressLabel(c), key: const Key('update-progress')),
                if (c.progress == 1) const Text('正在校验完整性，请稍候…'),
              ],
              if (c.message != null)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  child: Text(
                    c.message!,
                    key: const Key('update-message'),
                    style: TextStyle(
                      color: c.phase == UpdatePhase.failed
                          ? CupertinoColors.systemRed.resolveFrom(context)
                          : null,
                    ),
                  ),
                ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 12,
                runSpacing: 10,
                children: [
                  if (downloading)
                    CupertinoButton(
                      onPressed: c.cancelDownload,
                      child: const Text('取消下载'),
                    ),
                  if (!c.busy && !ready && c.phase != UpdatePhase.unsupported)
                    CupertinoButton(
                      onPressed: c.check,
                      child: const Text('检查更新'),
                    ),
                  if (!c.busy && !ready && c.release != null)
                    SettingsAction(
                      filled: true,
                      onPressed: c.download,
                      icon: const Icon(CupertinoIcons.arrow_down),
                      label: Text(
                        platform == 'macos'
                            ? '前往官网下载'
                            : c.phase == UpdatePhase.failed
                            ? '重新下载'
                            : '下载新版',
                      ),
                    ),
                  if (ready)
                    CupertinoButton(
                      onPressed: c.redownload,
                      child: const Text('重新下载'),
                    ),
                  if (ready)
                    SettingsAction(
                      filled: true,
                      key: const Key('install-update'),
                      onPressed: () async {
                        final confirmed = await showCupertinoDialog<bool>(
                          context: context,
                          builder: (context) => CupertinoAlertDialog(
                            title: Text(
                              platform == 'web'
                                  ? '现在重载新版？'
                                  : platform == 'macos'
                                  ? '打开新版安装包？'
                                  : '安装新版？',
                            ),
                            content: Text(
                              platform == 'web'
                                  ? '页面会重载，当前播放将停止。'
                                  : platform == 'macos'
                                  ? '将打开系统 DMG 窗口，由你确认替换应用。当前版本未经过 Apple 公证。'
                                  : '将打开系统安装器。安装期间应用可能退出；如果需要允许此来源，系统会引导你设置。',
                            ),
                            actions: [
                              CupertinoDialogAction(
                                onPressed: () => Navigator.pop(context, false),
                                child: const Text('稍后'),
                              ),
                              CupertinoDialogAction(
                                isDefaultAction: true,
                                onPressed: () => Navigator.pop(context, true),
                                child: const Text('继续'),
                              ),
                            ],
                          ),
                        );
                        if (confirmed == true) await c.install();
                      },
                      icon: const Icon(CupertinoIcons.arrow_down_circle),
                      label: Text(
                        platform == 'web'
                            ? '重载使用新版'
                            : platform == 'macos'
                            ? '打开安装包'
                            : '安装新版',
                      ),
                    ),
                  if (c.busy && !downloading)
                    const Padding(
                      padding: EdgeInsets.all(12),
                      child: SizedBox(
                        width: 24,
                        height: 24,
                        child: CupertinoActivityIndicator(),
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      );
    },
  );
}
