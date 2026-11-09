import 'package:flutter/cupertino.dart';

import 'cupertino_settings.dart';

import '../drive/drive_api.dart';
import '../drive/drive_gateway.dart';
import '../music_controller.dart';

Future<void> showMusicSources(
  BuildContext context,
  MusicController controller,
) => showSettingsPopup<void>(
  context: context,
  builder: (context) => MusicSourcesSheet(controller: controller),
);

class MusicSourcesSheet extends StatefulWidget {
  const MusicSourcesSheet({super.key, required this.controller});
  final MusicController controller;
  @override
  State<MusicSourcesSheet> createState() => _MusicSourcesSheetState();
}

class _MusicSourcesSheetState extends State<MusicSourcesSheet> {
  final _setupLink = TextEditingController(
    text:
        '接入说明：github.com/KingXcode/cloud-music/blob/main/docs/GOOGLE_DRIVE.md',
  );
  bool _showDrive = false, _startingImport = false;
  void _startImport(VoidCallback action) {
    if (_startingImport || widget.controller.isBusy || drive?.busy == true) {
      return;
    }
    _startingImport = true;
    Navigator.pop(context);
    action();
  }

  DriveGateway? get drive => widget.controller.drive;

  @override
  void dispose() {
    // 关闭面板使迟到的目录/授权结果失效，不会偷偷替换正在使用的曲库。
    drive?.cancelBrowse(deferNotification: true);
    _setupLink.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final d = drive;
    return AnimatedBuilder(
      animation: d == null
          ? widget.controller
          : Listenable.merge([d, widget.controller]),
      builder: (context, _) => Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 8, 8),
            child: Row(
              children: [
                const Expanded(
                  child: Text(
                    '音乐来源',
                    style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                  ),
                ),
                SettingsIconButton(
                  tooltip: '关闭音乐来源',
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(CupertinoIcons.xmark_circle_fill),
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView(
              key: const Key('music-sources-scroll'),
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
              children: [
                SettingsTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(CupertinoIcons.folder),
                  title: const Text('系统文件'),
                  subtitle: const Text('本地、iCloud、USB 或系统文件提供器'),
                  trailing: !widget.controller.usingDrive
                      ? const Icon(
                          CupertinoIcons.checkmark_circle_fill,
                          color: Color(0xFFE83E59),
                        )
                      : null,
                  onTap: d?.busy == true
                      ? null
                      : () async {
                          await widget.controller.useLocalSource();
                          if (context.mounted) Navigator.pop(context);
                        },
                ),
                if (!widget.controller.selectsFiles)
                  SettingsAction(
                    key: const Key('source-pick-folder'),
                    onPressed: widget.controller.isBusy || d?.busy == true
                        ? null
                        : () => _startImport(widget.controller.pickFolder),
                    icon: const Icon(CupertinoIcons.folder_badge_plus),
                    label: const Text('选择音乐文件夹'),
                  ),
                if (widget.controller.canPickFiles ||
                    widget.controller.selectsFiles)
                  SettingsAction(
                    key: const Key('source-pick-files'),
                    onPressed: widget.controller.isBusy || d?.busy == true
                        ? null
                        : () => _startImport(
                            widget.controller.canPickFiles
                                ? widget.controller.pickFiles
                                : widget.controller.pickFolder,
                          ),
                    icon: const Icon(CupertinoIcons.music_note_list),
                    label: const Text('选择多个音乐文件'),
                  ),
                if (widget.controller.canScanDevice) ...[
                  SettingsAction(
                    key: const Key('source-scan-device'),
                    onPressed: widget.controller.isBusy || d?.busy == true
                        ? null
                        : () => _startImport(widget.controller.scanDevice),
                    icon: const Icon(CupertinoIcons.search),
                    label: const Text('扫描本机音乐'),
                  ),
                  Text(
                    '读取系统媒体库中的音乐，需要音乐读取权限。未收录的音乐或 U 盘可通过选择文件夹导入。',
                    style: TextStyle(
                      fontSize: 12,
                      height: 1.5,
                      color: CupertinoColors.secondaryLabel.resolveFrom(
                        context,
                      ),
                    ),
                  ),
                ],
                const SettingsSeparator(),
                SettingsTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(CupertinoIcons.cloud),
                  title: const Text('Google Drive'),
                  subtitle: Text(
                    d?.connected == true
                        ? '已连接 · 只读音乐来源'
                        : d?.configured == true
                        ? '连接后选择音乐文件夹'
                        : '需要开发者配置 OAuth Client ID',
                  ),
                  trailing: const Icon(CupertinoIcons.chevron_forward),
                  onTap: () => setState(() => _showDrive = !_showDrive),
                ),
                if (_showDrive && d != null) ..._driveContent(context, d),
                if (_showDrive && d == null)
                  const Text('此构建尚未包含 Google Drive 服务。'),
              ],
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _driveContent(BuildContext context, DriveGateway d) => [
    const Text(
      '连接使用 Google 官方授权。为了浏览整个音乐文件夹，应用需要读取你的全部 Google Drive 文件；代码仅列目录和读取音频，不上传、不修改、不删除文件。',
      style: TextStyle(height: 1.5),
    ),
    const SizedBox(height: 10),
    Text(
      d.playbackNotice,
      style: TextStyle(
        fontSize: 13,
        color: CupertinoColors.secondaryLabel.resolveFrom(context),
        height: 1.5,
      ),
    ),
    const SizedBox(height: 10),
    const Text('本次连接和网盘曲库不由云听写入本地存储。网页刷新后需重新连接；原生登录状态由 Google 官方 SDK 管理。'),
    if (!d.configured) ...[
      const SizedBox(height: 12),
      Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: CupertinoColors.tertiarySystemGroupedBackground.resolveFrom(
            context,
          ),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '尚未配置，暂时不能直接登录',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 6),
            Text(d.setupMessage),
            const SizedBox(height: 8),
            CupertinoTextField(
              controller: _setupLink,
              readOnly: true,
              maxLines: null,
              style: CupertinoTheme.of(context).textTheme.textStyle
                  .copyWith(fontSize: 12),
            ),
          ],
        ),
      ),
    ],
    if (d.error != null)
      Padding(
        padding: const EdgeInsets.only(top: 12),
        child: Text(
          d.error!,
          key: const Key('drive-error'),
          style: TextStyle(
            color: CupertinoColors.systemRed.resolveFrom(context),
          ),
        ),
      ),
    const SizedBox(height: 12),
    Wrap(
      spacing: 10,
      runSpacing: 8,
      children: [
        SettingsAction(
          filled: true,
          key: const Key('drive-connect'),
          onPressed: !d.configured || d.busy ? null : d.connect,
          icon: const Icon(CupertinoIcons.person_crop_circle_badge_checkmark),
          label: Text(d.connected ? '重新连接' : '同意只读访问并连接 Google'),
        ),
        if (d.connected)
          CupertinoButton(
            onPressed: d.busy ? null : widget.controller.disconnectDrive,
            child: const Text('断开并撤销授权'),
          ),
      ],
    ),
    if (d.busy) ...[
      const SizedBox(height: 12),
      const SettingsProgress(),
      CupertinoButton(onPressed: d.cancelBrowse, child: const Text('取消读取')),
    ],
    if (d.connected) ...[
      const SizedBox(height: 16),
      Wrap(
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          CupertinoButton(
            onPressed: d.busy
                ? null
                : () => d.openFolder(
                    const DriveFile(
                      id: 'root',
                      name: '我的云端硬盘',
                      mimeType: 'application/vnd.google-apps.folder',
                    ),
                  ),
            child: const Text('我的云端硬盘'),
          ),
          for (final folder in d.path) ...[
            const Icon(CupertinoIcons.chevron_forward, size: 16),
            CupertinoButton(
              onPressed: d.busy ? null : () => d.openFolder(folder),
              child: Text(folder.name),
            ),
          ],
        ],
      ),
      SettingsAction(
        filled: true,
        key: const Key('drive-use-folder'),
        onPressed: d.busy
            ? null
            : () async {
                await widget.controller.useDriveFolder();
                if (context.mounted &&
                    widget.controller.usingDrive &&
                    d.error == null &&
                    !d.busy) {
                  Navigator.pop(context);
                }
              },
        icon: const Icon(CupertinoIcons.music_note_list),
        label: const Text('使用此文件夹（含子文件夹）'),
      ),
      const SizedBox(height: 8),
      Text(
        '只显示文件夹和音频候选；不跟随快捷方式。建议选择专用音乐目录。',
        style: TextStyle(
          fontSize: 12,
          color: CupertinoColors.secondaryLabel.resolveFrom(context),
        ),
      ),
      if (d.entries.isEmpty && !d.busy)
        const Padding(
          padding: EdgeInsets.all(16),
          child: Text('此目录没有可见的文件夹或音频。'),
        ),
      for (final file in d.entries)
        SettingsTile(
          contentPadding: EdgeInsets.zero,
          leading: Icon(
            file.isFolder ? CupertinoIcons.folder : CupertinoIcons.music_note,
          ),
          title: Text(file.name, maxLines: 2, overflow: TextOverflow.ellipsis),
          subtitle: file.isFolder
              ? null
              : Text(file.canDownload ? '加入此文件夹后可播放' : '所有者禁止下载，无法播放'),
          trailing: file.isFolder
              ? const Icon(CupertinoIcons.chevron_forward)
              : null,
          onTap: !file.isFolder || d.busy ? null : () => d.openFolder(file),
        ),
    ],
  ];
}
