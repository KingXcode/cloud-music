import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../music_controller.dart';

/// Invoke the picker in the tap callback, not after awaiting the sheet result:
/// browsers require the original user activation for directory access.
Future<void> showMusicImport(BuildContext context, MusicController controller) {
  var starting = false;
  void start(BuildContext sheetContext, VoidCallback action) {
    if (starting || controller.isBusy) return;
    starting = true;
    Navigator.pop(sheetContext);
    action();
  }

  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    constraints: const BoxConstraints(maxWidth: 560),
    builder: (context) => SafeArea(
      top: false,
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Expanded(
                  child: Text(
                    '添加音乐',
                    style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
                  ),
                ),
                IconButton(
                  tooltip: '关闭添加音乐',
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(CupertinoIcons.xmark_circle_fill),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (controller.canScanDevice)
              ListTile(
                key: const Key('import-scan-device'),
                leading: const Icon(CupertinoIcons.music_note_list),
                contentPadding: EdgeInsets.zero,
                title: const Text('扫描本机音乐'),
                subtitle: const Text('读取系统媒体库中的音乐，需要音乐读取权限'),
                onTap: () => start(context, controller.scanDevice),
              ),
            if (!controller.selectsFiles)
              ListTile(
                key: const Key('import-folder'),
                leading: const Icon(CupertinoIcons.folder),
                contentPadding: EdgeInsets.zero,
                title: const Text('选择音乐文件夹'),
                subtitle: Text(
                  controller.canScanDevice
                      ? '适用于未被系统收录的音乐、U 盘或指定目录'
                      : '导入整个目录，自动查找其中的音频',
                ),
                onTap: () => start(context, controller.pickFolder),
              ),
            if (controller.canPickFiles)
              ListTile(
                key: const Key('import-files'),
                leading: const Icon(CupertinoIcons.doc_on_doc),
                contentPadding: EdgeInsets.zero,
                title: const Text('选择多个音乐文件'),
                subtitle: const Text('在系统选择器中启用多选后，一次导入多首'),
                onTap: () => start(context, controller.pickFiles),
              ),
            const SizedBox(height: 12),
            const Text(
              '选择新的来源会替换当前资料库；不会移动或删除原文件。',
              style: TextStyle(
                color: Color(0xFF6F6F76),
                fontSize: 12,
                height: 1.6,
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
