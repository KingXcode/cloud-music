part of 'lyrics_panel.dart';

/// A bounded, keyboard-aware Cupertino sheet. Long content scrolls independently
/// of the dismissal and confirmation controls, including at large text sizes.
class _LyricsSheetSurface extends StatelessWidget {
  const _LyricsSheetSurface({
    super.key,
    required this.title,
    required this.closeLabel,
    required this.onClose,
    required this.child,
    this.closeKey,
    this.scrollKey,
    this.footer,
    this.bottomSheet = false,
  });

  final String title, closeLabel;
  final VoidCallback onClose;
  final Widget child;
  final Widget? footer;
  final Key? closeKey, scrollKey;
  final bool bottomSheet;

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
    child: SafeArea(
      bottom: !bottomSheet,
      child: LayoutBuilder(
        builder: (context, constraints) => Align(
          alignment: bottomSheet ? Alignment.bottomCenter : Alignment.center,
          child: Container(
            margin: EdgeInsets.symmetric(
              horizontal: constraints.maxWidth < 600 ? 8 : 24,
            ),
            constraints: BoxConstraints(
              maxWidth: 640,
              maxHeight: constraints.maxHeight * (bottomSheet ? .94 : .92),
            ),
            decoration: BoxDecoration(
              color: CupertinoColors.systemGroupedBackground.resolveFrom(
                context,
              ),
              borderRadius: BorderRadius.circular(26),
              border: Border.all(
                color: CupertinoColors.separator
                    .resolveFrom(context)
                    .withValues(alpha: .12),
              ),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x22000000),
                  blurRadius: 40,
                  offset: Offset(0, 12),
                ),
              ],
            ),
            clipBehavior: Clip.antiAlias,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 10, 8, 8),
                  child: Row(
                    children: [
                      Expanded(
                        child: Semantics(
                          header: true,
                          child: Text(
                            title,
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      CupertinoButton(
                        key: closeKey,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                        onPressed: onClose,
                        child: Text(
                          closeLabel,
                          style: const TextStyle(fontSize: 15),
                        ),
                      ),
                    ],
                  ),
                ),
                const _LyricsSeparator(),
                Flexible(
                  child: SingleChildScrollView(
                    key: scrollKey,
                    padding: const EdgeInsets.fromLTRB(20, 22, 20, 24),
                    child: child,
                  ),
                ),
                if (footer != null) ...[
                  const _LyricsSeparator(),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 14, 20, 16),
                    child: footer!,
                  ),
                ],
                if (bottomSheet)
                  SizedBox(height: MediaQuery.paddingOf(context).bottom),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

class _LyricsCard extends StatelessWidget {
  const _LyricsCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(18),
  });
  final Widget child;
  final EdgeInsets padding;
  @override
  Widget build(BuildContext context) => Container(
    padding: padding,
    decoration: BoxDecoration(
      color: CupertinoColors.secondarySystemGroupedBackground.resolveFrom(
        context,
      ),
      borderRadius: BorderRadius.circular(20),
    ),
    child: child,
  );
}

class _LyricsSymbol extends StatelessWidget {
  const _LyricsSymbol(this.icon);
  final IconData icon;
  @override
  Widget build(BuildContext context) {
    final primary = CupertinoTheme.of(context).primaryColor;
    return Container(
      width: 48,
      height: 48,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            primary.withValues(alpha: .16),
            primary.withValues(alpha: .06),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Icon(icon, size: 24, color: primary),
    );
  }
}

class _LyricsBadge extends StatelessWidget {
  const _LyricsBadge(this.label, {this.icon, this.accent = false});
  final String label;
  final IconData? icon;
  final bool accent;
  @override
  Widget build(BuildContext context) {
    final color = accent
        ? CupertinoTheme.of(context).primaryColor
        : CupertinoColors.secondaryLabel.resolveFrom(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .09),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 13, color: color),
            const SizedBox(width: 5),
          ],
          Flexible(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: color,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _LyricsStatus extends StatelessWidget {
  const _LyricsStatus({
    required this.icon,
    required this.child,
    this.warning = false,
  });
  final IconData icon;
  final Widget child;
  final bool warning;
  @override
  Widget build(BuildContext context) {
    final color = warning
        ? CupertinoColors.systemOrange.resolveFrom(context)
        : CupertinoColors.secondaryLabel.resolveFrom(context);
    return Semantics(
      liveRegion: true,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: color.withValues(alpha: .08),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 18, color: color),
            const SizedBox(width: 10),
            Expanded(
              child: DefaultTextStyle(
                style: CupertinoTheme.of(context).textTheme.textStyle.copyWith(
                  fontSize: 13,
                  height: 1.5,
                  color: CupertinoColors.secondaryLabel.resolveFrom(context),
                ),
                child: child,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LyricsLocalAction extends StatelessWidget {
  const _LyricsLocalAction({
    super.key,
    required this.icon,
    required this.title,
    required this.detail,
    this.onPressed,
  });
  final IconData icon;
  final String title, detail;
  final VoidCallback? onPressed;
  @override
  Widget build(BuildContext context) => CupertinoButton(
    onPressed: onPressed,
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 14),
    child: Row(
      children: [
        Icon(icon, size: 22),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: CupertinoColors.label.resolveFrom(context),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                detail,
                style: TextStyle(
                  fontSize: 12,
                  color: CupertinoColors.secondaryLabel.resolveFrom(context),
                ),
              ),
            ],
          ),
        ),
        Icon(
          CupertinoIcons.chevron_right,
          size: 13,
          color: CupertinoColors.tertiaryLabel.resolveFrom(context),
        ),
      ],
    ),
  );
}

class _LyricsCandidateTile extends StatelessWidget {
  const _LyricsCandidateTile({
    required this.candidate,
    required this.controller,
    required this.onPressed,
  });
  final LyricsCandidate candidate;
  final LyricsController controller;
  final VoidCallback? onPressed;
  @override
  Widget build(BuildContext context) {
    final warning = _candidateWarning(controller, candidate);
    final doc = controller.preferSimplified
        ? candidate.document.simplified()
        : candidate.document;
    final excerpt = doc.isSynced
        ? doc.lines
              .map((line) => line.text)
              .where((line) => line.trim().isNotEmpty)
              .take(2)
              .join('\n')
        : doc.text.trim();
    final secondary = CupertinoColors.secondaryLabel.resolveFrom(context);
    return _LyricsCard(
      padding: EdgeInsets.zero,
      child: CupertinoButton(
        key: ValueKey('lyrics-candidate-${candidate.id}'),
        padding: const EdgeInsets.all(18),
        onPressed: onPressed,
        child: DefaultTextStyle(
          style: CupertinoTheme.of(context).textTheme.textStyle,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text(
                      candidate.title,
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                        height: 1.3,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Icon(
                      CupertinoIcons.chevron_right,
                      size: 14,
                      color: secondary,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                [
                  candidate.artist.isEmpty ? '歌手未知' : candidate.artist,
                  if (candidate.album.isNotEmpty) candidate.album,
                ].join(' · '),
                style: TextStyle(fontSize: 13, height: 1.4, color: secondary),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  _LyricsBadge(
                    _kind(doc),
                    accent: doc.isSynced,
                    icon: doc.isSynced
                        ? CupertinoIcons.waveform
                        : CupertinoIcons.text_alignleft,
                  ),
                  _LyricsBadge(
                    candidate.duration > Duration.zero
                        ? _duration(candidate.duration)
                        : '来源未提供时长',
                  ),
                  const _LyricsBadge('LRCLIB'),
                ],
              ),
              if (warning != null) ...[
                const SizedBox(height: 12),
                _LyricsStatus(
                  icon: CupertinoIcons.exclamationmark_circle,
                  warning: true,
                  child: Text(warning),
                ),
              ],
              if (excerpt.isNotEmpty && !doc.instrumental) ...[
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.only(left: 12),
                  decoration: BoxDecoration(
                    border: Border(
                      left: BorderSide(
                        width: 2,
                        color: CupertinoTheme.of(context).primaryColor
                            .withValues(alpha: .3),
                      ),
                    ),
                  ),
                  child: Text(
                    excerpt,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 14,
                      height: 1.6,
                      color: secondary,
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 14),
              Text(
                '预览歌词',
                style: TextStyle(
                  color: CupertinoTheme.of(context).primaryColor,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LyricsPreviewDialog extends StatelessWidget {
  const _LyricsPreviewDialog({
    required this.controller,
    required this.candidate,
    required this.selection,
  });
  final LyricsController controller;
  final LyricsCandidate candidate;
  final Object? selection;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: controller,
    builder: (context, _) {
      final valid =
          controller.selectionIdentity == selection &&
          controller.candidates.contains(candidate) &&
          !controller.busy;
      final doc = controller.preferSimplified
          ? candidate.document.simplified()
          : candidate.document;
      final warning = _candidateWarning(controller, candidate);
      final secondary = CupertinoColors.secondaryLabel.resolveFrom(context);
      return _LyricsSheetSurface(
        key: const Key('lyrics-preview-dialog'),
        title: '预览歌词',
        closeLabel: '返回结果',
        closeKey: const Key('lyrics-preview-cancel'),
        onClose: () => Navigator.pop(context, false),
        scrollKey: const Key('lyrics-preview-scroll'),
        footer: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              controller.originalDocument == null
                  ? '仅保存到本机，可离线查看'
                  : '保存后替换当前歌词，返回不会修改',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: secondary),
            ),
            const SizedBox(height: 10),
            CupertinoButton.filled(
              key: const Key('lyrics-preview-save'),
              borderRadius: BorderRadius.circular(14),
              onPressed: valid ? () => Navigator.pop(context, true) : null,
              child: const Text(
                '保存到本机',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              candidate.title,
              style: const TextStyle(
                fontSize: 25,
                fontWeight: FontWeight.w700,
                height: 1.25,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              [
                candidate.artist.isEmpty ? '歌手未知' : candidate.artist,
                if (candidate.album.isNotEmpty) candidate.album,
              ].join(' · '),
              style: TextStyle(fontSize: 14, color: secondary, height: 1.5),
            ),
            const SizedBox(height: 14),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                _LyricsBadge(_kind(doc), accent: true),
                _LyricsBadge(
                  candidate.duration > Duration.zero
                      ? _duration(candidate.duration)
                      : '来源未提供时长',
                ),
                _LyricsBadge(controller.preferSimplified ? '简体显示' : '原文显示'),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              doc.instrumental
                  ? '此版本标记为纯音乐。'
                  : doc.isSynced
                  ? '带逐行时间轴，保存后可跟随播放。'
                  : '纯文本没有时间轴，播放时不会自动滚动。',
              style: TextStyle(fontSize: 13, height: 1.5, color: secondary),
            ),
            if (warning != null) ...[
              const SizedBox(height: 16),
              _LyricsStatus(
                icon: CupertinoIcons.exclamationmark_circle,
                warning: true,
                child: Text(warning),
              ),
            ],
            if (!valid) ...[
              const SizedBox(height: 16),
              const _LyricsStatus(
                icon: CupertinoIcons.info_circle,
                warning: true,
                child: Text('当前歌曲或搜索结果已变更，请关闭后重新选择。'),
              ),
            ],
            const SizedBox(height: 24),
            _LyricsCard(
              child: doc.instrumental
                  ? const Padding(
                      padding: EdgeInsets.symmetric(vertical: 24),
                      child: Text(
                        '此版本标记为纯音乐，无歌词。',
                        textAlign: TextAlign.center,
                      ),
                    )
                  : _SelectableLyricsText(
                      doc.isSynced
                          ? doc.lines
                                .map(
                                  (line) =>
                                      '${_duration(line.time)}  ${line.text}',
                                )
                                .join('\n\n')
                          : doc.text,
                      style: TextStyle(
                        fontSize: 17,
                        height: 1.8,
                        fontWeight: FontWeight.w500,
                        color: CupertinoColors.label.resolveFrom(context),
                      ),
                    ),
            ),
            const SizedBox(height: 16),
            Text(
              '${doc.source} · 完整歌词可滚动预览',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: secondary),
            ),
          ],
        ),
      );
    },
  );
}

class _SearchConsentDialog extends StatefulWidget {
  const _SearchConsentDialog({
    required this.title,
    required this.artist,
    required this.album,
  });
  final String title, artist, album;
  @override
  State<_SearchConsentDialog> createState() => _SearchConsentDialogState();
}

class _SearchConsentDialogState extends State<_SearchConsentDialog> {
  late final _title = TextEditingController(text: widget.title);
  late final _artist = TextEditingController(text: widget.artist);
  late final _album = TextEditingController(text: widget.album);
  bool _showPrivacy = false;
  @override
  void dispose() {
    _title.dispose();
    _artist.dispose();
    _album.dispose();
    super.dispose();
  }

  Widget _field(
    String label,
    String hint,
    String key,
    TextEditingController controller, {
    bool required = false,
    bool last = false,
  }) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 9),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: CupertinoColors.secondaryLabel.resolveFrom(context),
          ),
        ),
        const SizedBox(height: 8),
        Semantics(
          label: label,
          child: CupertinoTextField(
            key: Key(key),
            controller: controller,
            placeholder: hint,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
            style: const TextStyle(fontSize: 16),
            decoration: BoxDecoration(
              color: CupertinoColors.tertiarySystemFill.resolveFrom(context),
              borderRadius: BorderRadius.circular(12),
            ),
            clearButtonMode: OverlayVisibilityMode.editing,
            textInputAction: last ? TextInputAction.done : TextInputAction.next,
            onEditingComplete: () => last
                ? FocusScope.of(context).unfocus()
                : FocusScope.of(context).nextFocus(),
            onChanged: required ? (_) => setState(() {}) : null,
          ),
        ),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) {
    final secondary = CupertinoColors.secondaryLabel.resolveFrom(context);
    return _LyricsSheetSurface(
      key: const Key('lyrics-consent-dialog'),
      title: '搜索在线歌词',
      closeLabel: '取消',
      closeKey: const Key('lyrics-consent-cancel'),
      onClose: () => Navigator.pop(context),
      scrollKey: const Key('lyrics-consent-scroll'),
      footer: CupertinoButton.filled(
        key: const Key('lyrics-consent-confirm'),
        borderRadius: BorderRadius.circular(14),
        onPressed: _title.text.trim().isEmpty
            ? null
            : () => Navigator.pop(context, [
                _title.text.trim(),
                _artist.text.trim(),
                _album.text.trim(),
              ]),
        child: const Text(
          '同意并搜索',
          style: TextStyle(fontWeight: FontWeight.w600),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const _LyricsSymbol(CupertinoIcons.search),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      '找到对的歌词',
                      style: TextStyle(
                        fontSize: 25,
                        fontWeight: FontWeight.w700,
                        height: 1.25,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '核对歌名和歌手，结果会更准确。',
                      style: TextStyle(
                        fontSize: 14,
                        height: 1.5,
                        color: secondary,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 22),
          _LyricsCard(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _field(
                  '歌名 · 必填',
                  '输入歌曲名称',
                  'lyrics-query-title',
                  _title,
                  required: true,
                ),
                _field('歌手 · 推荐填写', '未知时可留空', 'lyrics-query-artist', _artist),
                _field(
                  '专辑 · 可选',
                  '输入专辑名称',
                  'lyrics-query-album',
                  _album,
                  last: true,
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          Text(
            '只修改本次搜索，不会更改音乐标签。',
            style: TextStyle(fontSize: 12, color: secondary),
          ),
          const SizedBox(height: 22),
          const _LyricsStatus(
            icon: CupertinoIcons.lock_shield,
            child: Text(
              '点击「同意并搜索」，将以上歌曲信息及繁简变体发送至 LRCLIB（lrclib.net）；服务可看到你的 IP。不会上传音频、文件路径或时长。',
            ),
          ),
          CupertinoButton(
            padding: const EdgeInsets.symmetric(vertical: 14),
            onPressed: () => setState(() => _showPrivacy = !_showPrivacy),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Flexible(
                  child: Text('来源、隐私与版权说明', style: TextStyle(fontSize: 12)),
                ),
                const SizedBox(width: 6),
                Icon(
                  _showPrivacy
                      ? CupertinoIcons.chevron_up
                      : CupertinoIcons.chevron_down,
                  size: 12,
                ),
              ],
            ),
          ),
          if (_showPrivacy)
            Text(
              'LRCLIB 是社区歌词库，可能未收录、存在不同版本或时间轴错误。无匹配时会逐步忽略专辑、尝试繁简字形，仍无匹配时仅按歌名查找。只有保存后才替换当前歌词，内容仅缓存到本机。版权归原权利人，请仅在获准使用时下载。每次手动搜索均需确认，取消或返回不会发送请求。',
              style: TextStyle(fontSize: 13, height: 1.6, color: secondary),
            ),
        ],
      ),
    );
  }
}
