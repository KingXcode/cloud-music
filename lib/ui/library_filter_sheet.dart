import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../music_controller.dart';

Future<void> showLibraryFilter(
  BuildContext context,
  MusicController controller,
) => showDialog<void>(
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
  final _form = GlobalKey<FormState>();
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
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('短音频过滤'),
    scrollable: true,
    content: SizedBox(
      width: 400,
      child: Form(
        key: _form,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            SwitchListTile.adaptive(
              key: const Key('short-audio-switch'),
              contentPadding: EdgeInsets.zero,
              title: const Text('隐藏短音频'),
              value: _enabled,
              onChanged: (value) => setState(() => _enabled = value),
            ),
            const SizedBox(height: 12),
            TextFormField(
              key: const Key('short-audio-minimum'),
              controller: _seconds,
              enabled: _enabled,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: const InputDecoration(
                labelText: '最短时长（秒）',
                helperText: '1–600 秒，默认 30 秒',
              ),
              validator: (raw) {
                if (!_enabled) return null;
                final value = int.tryParse(raw ?? '');
                return value == null || value < 1 || value > 600
                    ? '请输入 1–600 之间的整数'
                    : null;
              },
            ),
            const SizedBox(height: 18),
            const Text('只隐藏已知时长小于设定值的歌曲，等于设定值的仍会显示。歌曲、专辑、歌手与搜索共用此设置。'),
            const SizedBox(height: 12),
            const Text(
              '未知时长暂时保留，通常播放后才会补全。不会为测量时长下载云端音频，不删除源文件，也不改变当前播放或待播清单。设置只保存在本机。',
              style: TextStyle(color: Color(0xFF78787F), height: 1.5),
            ),
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('取消'),
      ),
      FilledButton(
        key: const Key('short-audio-apply'),
        onPressed: () {
          if (!_form.currentState!.validate()) return;
          final parsed = int.tryParse(_seconds.text);
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
    ],
  );
}
