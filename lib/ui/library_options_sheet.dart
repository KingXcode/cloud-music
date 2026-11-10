import 'package:flutter/cupertino.dart';

import 'cupertino_settings.dart';

import '../music_controller.dart';

enum LibraryOption { sources, filter, updates, refresh }

Future<LibraryOption?> showLibraryOptions(
  BuildContext context,
  MusicController controller, {
  required bool hasUpdates,
}) => showSettingsPopup<LibraryOption>(
  context: context,
  builder: (context) => AnimatedBuilder(
    animation: controller,
    builder: (context, _) {
      final s = controller.snapshot;
      final stats = controller.playbackStats;
      final filter = controller.libraryFilter;
      final hidden = s.tracks.where((t) => filter.hides(t)).length;
      final unknown = s.tracks.where((t) => t.duration <= Duration.zero).length;
      final muted = CupertinoColors.secondaryLabel.resolveFrom(context);
      return SafeArea(
        top: false,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(context).height * .8,
          ),
          child: SingleChildScrollView(
            key: const Key('library-options-scroll'),
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    const Expanded(
                      child: Text(
                        '资料库选项',
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    SettingsIconButton(
                      tooltip: '关闭资料库选项',
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(CupertinoIcons.xmark_circle_fill),
                    ),
                  ],
                ),
                Text(
                  s.folderName ?? '添加音乐后，在这里管理资料库',
                  style: TextStyle(color: muted, fontSize: 13),
                ),
                const SizedBox(height: 16),
                SettingsTile(
                  key: const Key('music-sources'),
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(CupertinoIcons.folder),
                  title: const Text('音乐来源'),
                  subtitle: Text(
                    s.sourceKind == 'googleDrive'
                        ? 'Google Drive · 管理已连接来源'
                        : '系统文件、iCloud Drive 与网盘',
                  ),
                  trailing: const Icon(
                    CupertinoIcons.chevron_forward,
                    size: 16,
                  ),
                  onTap: () => Navigator.pop(context, LibraryOption.sources),
                ),
                SettingsTile(
                  key: const Key('refresh-library'),
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(CupertinoIcons.arrow_clockwise),
                  title: Text(s.selectsFiles ? '重新选择音乐文件' : '刷新资料库'),
                  subtitle: Text(
                    s.selectsFiles ? '重新打开选择器，选择要保留的歌曲' : '更新当前资料库，需要时会重新打开选择器',
                  ),
                  enabled: s.folderName != null && !controller.isBusy,
                  onTap: () => Navigator.pop(context, LibraryOption.refresh),
                ),
                const SettingsSeparator(height: 24),
                SettingsTile(
                  key: const Key('library-filter'),
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(CupertinoIcons.slider_horizontal_3),
                  title: const Text('短音频过滤'),
                  subtitle: Text(
                    filter.enabled
                        ? '隐藏不足 ${filter.minimumSeconds} 秒的音频 · $hidden 首已隐藏'
                        : '已关闭 · 显示全部音频',
                  ),
                  trailing: const Icon(
                    CupertinoIcons.chevron_forward,
                    size: 16,
                  ),
                  enabled: controller.initialized,
                  onTap: () => Navigator.pop(context, LibraryOption.filter),
                ),
                if (filter.enabled && unknown > 0)
                  Padding(
                    padding: const EdgeInsets.only(left: 56, bottom: 8),
                    child: Text(
                      '$unknown 首时长未知，暂时保留',
                      key: const Key('library-filter-summary'),
                      style: TextStyle(color: muted, fontSize: 12),
                    ),
                  ),
                if (filter.notice != null)
                  Text(
                    filter.notice!,
                    style: TextStyle(color: muted, fontSize: 12),
                  ),
                const SettingsSeparator(height: 24),
                const Text(
                  '播放统计',
                  style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                ),
                const SizedBox(height: 8),
                Text(
                  switch (stats.storageLocation) {
                    'icloud' => '播放统计保存在 iCloud 应用目录。',
                    'folder' => '播放统计保存在你选择的文件夹。',
                    'browser' => '播放统计保存在当前浏览器。',
                    'local'
                        when s.sourceKind == 'apple' || stats.canPickFolder =>
                      '播放统计暂存本机，可选择个人 iCloud Drive 文件夹。',
                    'local' => '播放统计保存在本机。',
                    _ when stats.notice != null => '播放统计暂未连接缓存。',
                    _ => '正在读取播放统计。',
                  },
                  key: const Key('playback-stats-storage'),
                  style: TextStyle(color: muted, fontSize: 12, height: 1.6),
                ),
                Text(
                  '成功开始播放后计为 1 次，暂停后继续不重复计数。可在列表排序中按播放次数排列。',
                  style: TextStyle(color: muted, fontSize: 12, height: 1.6),
                ),
                if (stats.canPickFolder) ...[
                  SettingsTile(
                    key: const Key('pick-playback-stats-folder'),
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(CupertinoIcons.folder_badge_plus),
                    title: Text(
                      stats.choosingFolder
                          ? '正在选择保存文件夹…'
                          : stats.storageLocation == 'folder'
                          ? '更换统计保存文件夹'
                          : '选择个人 iCloud 文件夹',
                    ),
                    enabled: stats.canPickFolder && !stats.choosingFolder,
                    onTap: () async => stats.pickFolder(),
                  ),
                  Text(
                    '在个人 iCloud Drive 中选择或新建“弦泊”文件夹，统计会保存到这里并由系统同步。',
                    key: const Key('playback-stats-folder-help'),
                    style: TextStyle(color: muted, fontSize: 12, height: 1.6),
                  ),
                ],
                if (stats.notice != null)
                  Text(
                    stats.notice!,
                    key: const Key('playback-stats-notice'),
                    style: TextStyle(color: muted, fontSize: 12, height: 1.6),
                  ),
                if (hasUpdates)
                  SettingsTile(
                    key: const Key('app-updates'),
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(CupertinoIcons.arrow_down_circle),
                    title: const Text('应用更新'),
                    trailing: const Icon(
                      CupertinoIcons.chevron_forward,
                      size: 16,
                    ),
                    onTap: () => Navigator.pop(context, LibraryOption.updates),
                  ),
                if (s.sourceKind == 'web' || s.sourceKind == 'apple') ...[
                  const SettingsSeparator(height: 24),
                  Text(
                    '文件与下载说明',
                    style: TextStyle(
                      color: muted,
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    s.sourceKind == 'web'
                        ? '本页只在播放时读取音频。网页无法判断 iCloud 下载状态；系统可能在选择文件时先下载。'
                        : '先显示文件名和下载状态，点歌才下载。首次列表取决于系统已同步的目录信息。',
                    key: const Key('source-loading-help'),
                    style: TextStyle(color: muted, fontSize: 12, height: 1.6),
                  ),
                ],
                if (s.message != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    s.message!,
                    style: TextStyle(color: muted, fontSize: 12, height: 1.6),
                  ),
                ],
              ],
            ),
          ),
        ),
      );
    },
  ),
);
