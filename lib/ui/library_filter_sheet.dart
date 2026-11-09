import 'package:flutter/cupertino.dart';

import 'cupertino_settings.dart';

import 'package:flutter/services.dart';

import '../music_controller.dart';

Future<void> showLibraryFilter(
  BuildContext context,
  MusicController controller,
) => showSettingsPopup<void>(
  context: context,
  builder: (_) => _FilterDialog(controller: controller),
);

class _FilterDialog extends StatefulWidget {
  const _FilterDialog({required this.controller});
  final MusicController controller;
  @override
  State<_FilterDialog> createState() => _FilterDialogState();
}

class _FilterDialogState extends State<_FilterDialog> {
  String? _error;
  late final _seconds = TextEditingController(
    text: '${widget.controller.libraryFilter.minimumSeconds}',
  );
  late bool _enabled = widget.controller.libraryFilter.enabled;

  @override
  void dispose() {
    _seconds.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    padding: const EdgeInsets.all(20),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            const Expanded(
              child: Text(
                '短音频过滤',
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
              ),
            ),
            SettingsIconButton(
              tooltip: '关闭短音频过滤',
              onPressed: () => Navigator.pop(context),
              icon: const Icon(CupertinoIcons.xmark_circle_fill),
            ),
          ],
        ),
        CupertinoListSection.insetGrouped(
          margin: const EdgeInsets.symmetric(vertical: 16),
          children: [
            CupertinoListTile(
              title: const Text('隐藏短音频', maxLines: 4),
              trailing: Semantics(
                label: '隐藏短音频',
                child: CupertinoSwitch(
                  key: const Key('short-audio-switch'),
                  value: _enabled,
                  onChanged: (value) => setState(() {
                    _enabled = value;
                    _error = null;
                  }),
                ),
              ),
            ),
          ],
        ),
        const Text('最短时长（秒）'),
        const SizedBox(height: 8),
        Semantics(
          label: '最短时长（秒）',
          child: CupertinoTextField(
            key: const Key('short-audio-minimum'),
            controller: _seconds,
            enabled: _enabled,
            placeholder: '1–600 秒，默认 30 秒',
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            padding: const EdgeInsets.all(12),
            onChanged: (_) {
              if (_error != null) setState(() => _error = null);
            },
          ),
        ),
        const SizedBox(height: 6),
        Text(
          '1–600 秒，默认 30 秒',
          style: TextStyle(
            color: CupertinoColors.secondaryLabel.resolveFrom(context),
            fontSize: 13,
          ),
        ),
        if (_error != null)
          Semantics(
            liveRegion: true,
            child: Text(
              _error!,
              style: const TextStyle(color: CupertinoColors.systemRed),
            ),
          ),
        const SizedBox(height: 18),
        const Text('只隐藏已知时长小于设定值的歌曲，等于设定值的仍会显示。歌曲、专辑、歌手与搜索共用此设置。'),
        const SizedBox(height: 12),
        Text(
          '未知时长暂时保留，通常播放后才会补全。不会为测量时长下载云端音频，不删除源文件，也不改变当前播放或待播清单。设置只保存在本机。',
          style: TextStyle(
            color: CupertinoColors.secondaryLabel.resolveFrom(context),
            height: 1.5,
          ),
        ),
        const SizedBox(height: 20),
        CupertinoButton.filled(
          key: const Key('short-audio-apply'),
          onPressed: () {
            final parsed = int.tryParse(_seconds.text);
            if (_enabled && (parsed == null || parsed < 1 || parsed > 600)) {
              setState(() => _error = '请输入 1–600 之间的整数');
              return;
            }
            final seconds = parsed != null && parsed >= 1 && parsed <= 600
                ? parsed
                : widget.controller.libraryFilter.minimumSeconds;
            widget.controller.libraryFilter.update(
              enabled: _enabled,
              minimumSeconds: seconds,
            );
            Navigator.pop(context);
          },
          child: const Text('应用'),
        ),
        CupertinoButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
      ],
    ),
  );
}
