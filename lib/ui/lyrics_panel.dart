import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';

import '../lyrics/lyrics_controller.dart';
import '../lyrics/lyrics_models.dart';
import '../lyrics/lyrics_matching.dart';
import '../lyrics/lyrics_script.dart';

Future<T?> _showLyricsDialog<T>({
  required BuildContext context,
  required WidgetBuilder builder,
}) {
  final theme = CupertinoTheme.of(context);
  return showCupertinoDialog<T>(
    context: context,
    builder: (dialogContext) => CupertinoTheme(
      data: theme,
      child: DefaultTextStyle(
        style: theme.textTheme.textStyle,
        child: Builder(builder: builder),
      ),
    ),
  );
}

/// 仅在局部重建的歌词视图；自动联网状态由用户的一次性授权控制。
class LyricsPanel extends StatefulWidget {
  const LyricsPanel({
    super.key,
    required this.controller,
    required this.position,
    required this.onSeek,
    this.immersive = false,
  });

  final bool immersive;
  final LyricsController controller;
  final Duration position;
  final ValueChanged<Duration> onSeek;

  @override
  State<LyricsPanel> createState() => _LyricsPanelState();
}

class _LyricsPanelState extends State<LyricsPanel> {
  final _scroll = ScrollController();
  LyricsDocument? _shownDocument;
  List<GlobalKey> _lineKeys = [];
  int _lastActive = -2;
  Object? _lastLayout;
  bool _follow = true;
  bool _dialogOpen = false;
  bool _optionsOpen = false;
  bool _syncedOnly = false;
  List<String>? _lastQuery;
  Object? _querySelection;
  StateSetter? _refreshSheet;

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _prepareDocument(LyricsDocument? document) {
    if (!identical(document, _shownDocument)) {
      _shownDocument = document;
      _lineKeys = List.generate(
        document?.lines.length ?? 0,
        (_) => GlobalKey(),
      );
      _lastActive = -2;
      _follow = true;
    }
  }

  void _scheduleScroll(LyricsDocument? document, int active, Object layout) {
    final layoutChanged = layout != _lastLayout;
    _lastLayout = layout;
    if (active == _lastActive && !layoutChanged) return;
    _lastActive = active;
    if (!_follow) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted ||
          !_scroll.hasClients ||
          !_follow ||
          !identical(document, _shownDocument) ||
          _lastActive != active) {
        return;
      }
      if (active < 0) {
        if (layoutChanged && document?.isSynced != true) return;
        _scroll.jumpTo(0);
        return;
      }
      if (active >= _lineKeys.length) return;
      final target = _lineKeys[active].currentContext?.findRenderObject();
      if (target != null) {
        // 只滚动本组件的视口，不影响外层播放器路由。
        _scroll.position.ensureVisible(
          target,
          alignment: widget.immersive ? 0.45 : 0.4,
          duration: layoutChanged
              ? Duration.zero
              : const Duration(milliseconds: 420),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _search() async {
    final c = widget.controller;
    final track = c.track;
    final selection = c.selectionIdentity;
    if (_dialogOpen || c.busy || track == null) return;
    c.suspendAutomaticSelection();
    setState(() => _dialogOpen = true);
    _refreshSheet?.call(() {});
    final query = await _showLyricsDialog<List<String>>(
      context: context,
      builder: (_) => _SearchConsentDialog(
        title: _querySelection == selection ? _lastQuery![0] : track.title,
        artist: _querySelection == selection ? _lastQuery![1] : track.artist,
        album: _querySelection == selection ? _lastQuery![2] : track.album,
      ),
    );
    if (!mounted) return;
    setState(() => _dialogOpen = false);
    _refreshSheet?.call(() {});
    if (query == null ||
        c != widget.controller ||
        c.selectionIdentity != selection ||
        c.busy) {
      return;
    }
    _lastQuery = query;
    _querySelection = selection;
    setState(() => _syncedOnly = false);
    await c.search(title: query[0], artist: query[1], album: query[2]);
  }

  Future<void> _toggleAutomatic(bool enabled) async {
    final c = widget.controller;
    if (!enabled) {
      await c.setAutomaticSearch(false);
      return;
    }
    if (_dialogOpen) return;
    setState(() => _dialogOpen = true);
    _refreshSheet?.call(() {});
    final accepted = await _showLyricsDialog<bool>(
      context: context,
      builder: (context) => CupertinoAlertDialog(
        key: const Key('lyrics-auto-consent'),
        title: const Text('开启自动歌词'),
        content: const Text(
          '开启后，播放所选歌曲时会自动向 LRCLIB（lrclib.net）发送歌名、歌手和可选专辑名，包括繁简字形变体；该服务也会看到你的 IP 地址。无结果时会省略专辑再查找。不会上传音频、文件路径或时长，也不会扫描整库联网。\n\n'
          '仅在歌名、歌手、版本和时长匹配可靠时自动保存歌词；不确定时由你选择。歌词仅缓存到本机，版权归原权利人，请仅在获准使用时下载。\n\n'
          '记住本机选择，之后无需逐曲确认。可随时在歌词选项中关闭。',
        ),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('暂不开启'),
          ),
          CupertinoDialogAction(
            key: const Key('lyrics-auto-confirm'),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('同意并开启'),
          ),
        ],
      ),
    );
    if (!mounted) return;
    setState(() => _dialogOpen = false);
    _refreshSheet?.call(() {});
    if (accepted == true && c == widget.controller) {
      await c.setAutomaticSearch(true);
    }
  }

  Future<void> _paste() async {
    final c = widget.controller;
    final track = c.track;
    final selection = c.selectionIdentity;
    if (_dialogOpen || c.busy || track == null) return;
    c.suspendAutomaticSelection();
    setState(() => _dialogOpen = true);
    _refreshSheet?.call(() {});
    final text = await _showLyricsDialog<String>(
      context: context,
      builder: (_) => const _PasteLyricsDialog(),
    );
    if (!mounted) return;
    setState(() => _dialogOpen = false);
    _refreshSheet?.call(() {});
    if (text == null ||
        c != widget.controller ||
        c.selectionIdentity != selection ||
        c.busy) {
      return;
    }
    await c.importText(text);
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: widget.controller,
    builder: (context, _) {
      final c = widget.controller;
      final document = c.document;
      final active = document?.activeLineIndex(widget.position) ?? -1;
      _prepareDocument(document);
      if (widget.immersive) return _immersive(context, document, active);
      return Container(
        key: const Key('lyrics-panel'),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: CupertinoColors.secondarySystemBackground.resolveFrom(context),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              '歌词',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 10),
            ..._management(context),
            const SizedBox(height: 12),
            if (document?.isSynced == true && document?.instrumental != true)
              Align(
                alignment: Alignment.centerLeft,
                child: CupertinoButton(
                  key: const Key('lyrics-follow'),
                  onPressed: () => setState(() {
                    _follow = !_follow;
                    _lastActive = -2;
                  }),
                  child: Text(_follow ? '跟随播放：开 · 点击歌词跳转' : '跟随播放：关 · 点击开启'),
                ),
              ),
            SizedBox(
              height: 280,
              child: _lyricsBody(document, active, c.track != null),
            ),
            if (document != null) ...[
              const SizedBox(height: 8),
              Text(
                '来源：${document.source} · ${c.preferSimplified ? '简体显示' : '原文显示'}',
                key: const Key('lyrics-source'),
                style: const TextStyle(fontSize: 12),
              ),
            ],
            const SizedBox(height: 8),
            const _SelectableLyricsText(
              '在线歌词来源：LRCLIB\nhttps://lrclib.net/docs',
              style: TextStyle(fontSize: 12, color: Color(0xFF9FAABD)),
            ),
          ],
        ),
      );
    },
  );

  Future<void> _preview(LyricsCandidate candidate) async {
    final c = widget.controller;
    final selection = c.selectionIdentity;
    if (_dialogOpen || c.busy) return;
    setState(() => _dialogOpen = true);
    _refreshSheet?.call(() {});
    final accepted = await _showLyricsDialog<bool>(
      context: context,
      builder: (_) => _LyricsPreviewDialog(
        controller: c,
        candidate: candidate,
        selection: selection,
      ),
    );
    if (!mounted) return;
    setState(() => _dialogOpen = false);
    _refreshSheet?.call(() {});
    if (accepted == true &&
        c == widget.controller &&
        c.selectionIdentity == selection &&
        !c.busy) {
      await c.choose(candidate);
    }
  }

  List<Widget> _management(BuildContext context) {
    final c = widget.controller;
    final enabled = c.track != null && !c.busy && !_dialogOpen;
    final primary = CupertinoTheme.of(context).primaryColor;
    final surface = CupertinoColors.tertiarySystemFill.resolveFrom(context);
    final error = CupertinoColors.systemRed.resolveFrom(context);
    final candidates = c.candidates
        .where((candidate) => !_syncedOnly || candidate.document.isSynced)
        .toList();
    return [
      _fontSizeControls(context),
      const SizedBox(height: 20),
      if (c.track != null)
        Container(
          key: const Key('lyrics-track-summary'),
          padding: const EdgeInsets.all(16),
          margin: const EdgeInsets.only(bottom: 16),
          decoration: BoxDecoration(
            color: surface.withValues(alpha: .5),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(CupertinoIcons.music_note, color: primary),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      c.track!.title,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      [
                        c.track!.artist.isEmpty
                            ? '歌手未知，可编辑搜索'
                            : c.track!.artist,
                        if (c.track!.duration > Duration.zero)
                          _duration(c.track!.duration),
                      ].join(' · '),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      c.document == null
                          ? '尚未保存歌词'
                          : '已在本机 · ${_kind(c.document!)}',
                      style: TextStyle(color: primary, fontSize: 12),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          _LyricsActionButton(
            key: const Key('lyrics-search'),
            onPressed: enabled ? _search : null,
            icon: const Icon(CupertinoIcons.search),
            label: Text(c.error == null ? '搜索歌词' : '修改并重试'),
          ),
          _LyricsActionButton(
            key: const Key('lyrics-import'),
            onPressed: enabled ? c.importFile : null,
            icon: const Icon(CupertinoIcons.doc),
            label: const Text('导入 LRC / TXT'),
          ),
          CupertinoButton(
            key: const Key('lyrics-paste'),
            onPressed: enabled ? _paste : null,
            child: const Text('粘贴歌词'),
          ),
          if (c.busy)
            CupertinoButton(
              key: const Key('lyrics-cancel-search'),
              onPressed: c.cancelSearch,
              child: const Text('取消'),
            ),
        ],
      ),
      if (c.busy) ...[
        const SizedBox(height: 12),
        const CupertinoActivityIndicator(key: Key('lyrics-loading')),
        const SizedBox(height: 8),
        Text(c.searchStage ?? '正在保存到本机…'),
      ],
      if (c.error != null)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Text(
            c.error!,
            key: const Key('lyrics-error'),
            style: TextStyle(color: error),
          ),
        ),
      if (c.retryAfter != null)
        Text('服务请求过多，请约 ${c.retryAfter!.inSeconds + 1} 秒后重试。'),
      if (c.notice != null)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Text(c.notice!, key: const Key('lyrics-notice')),
        ),
      if (c.candidates.isNotEmpty) ...[
        const SizedBox(height: 8),
        Text(
          '找到 ${c.candidates.length} 个版本 · 先预览，再保存',
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 8),
        CupertinoSlidingSegmentedControl<bool>(
          groupValue: _syncedOnly,
          children: const {
            false: Text('全部', key: Key('lyrics-filter-all')),
            true: Text('仅逐行同步', key: Key('lyrics-filter-synced')),
          },
          onValueChanged: (value) {
            if (value == null) return;
            setState(() => _syncedOnly = value);
            _refreshSheet?.call(() {});
          },
        ),
        const SizedBox(height: 8),
        if (candidates.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 20),
            child: Text('这些结果没有同步时间轴。选择「全部」可预览纯文本歌词。'),
          )
        else
          ListView.separated(
            key: const Key('lyrics-candidates'),
            primary: false,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: candidates.length,
            separatorBuilder: (_, _) => const SizedBox(height: 8),
            itemBuilder: (context, index) {
              final candidate = candidates[index];
              final warning = _candidateWarning(c, candidate);
              return Container(
                decoration: BoxDecoration(
                  color: surface.withValues(alpha: .4),
                  borderRadius: BorderRadius.circular(14),
                ),
                clipBehavior: Clip.antiAlias,
                child: CupertinoButton(
                  key: ValueKey('lyrics-candidate-${candidate.id}'),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  onPressed: enabled ? () => _preview(candidate) : null,
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              candidate.title,
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            Padding(
                              padding: const EdgeInsets.only(top: 6),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    [
                                      candidate.artist.isEmpty
                                          ? '歌手未知'
                                          : candidate.artist,
                                      if (candidate.album.isNotEmpty)
                                        candidate.album,
                                    ].join(' · '),
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    '${_duration(candidate.duration)} · '
                                    '${_kind(candidate.document)} · LRCLIB',
                                  ),
                                  if (warning != null) ...[
                                    const SizedBox(height: 6),
                                    Text(
                                      warning,
                                      style: TextStyle(color: error),
                                    ),
                                  ],
                                  const SizedBox(height: 6),
                                  Text(
                                    '预览歌词',
                                    style: TextStyle(color: primary),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      const Icon(CupertinoIcons.chevron_right),
                    ],
                  ),
                ),
              );
            },
          ),
      ],
      const SizedBox(height: 20),
      const _LyricsSeparator(),
      const SizedBox(height: 12),
      const Text('歌词文字', style: TextStyle(fontWeight: FontWeight.w600)),
      const SizedBox(height: 8),
      CupertinoSlidingSegmentedControl<bool>(
        groupValue: c.preferSimplified,
        children: const {
          true: Text('简体中文', key: Key('lyrics-script-simplified')),
          false: Text('保留原文', key: Key('lyrics-script-original')),
        },
        onValueChanged: (value) {
          if (value != null) c.setPreferSimplified(value);
        },
      ),
      const SizedBox(height: 6),
      Text('仅在本机转换中文字形，保留原始歌词和时间轴；不是翻译。', style: const TextStyle(fontSize: 12)),
      const SizedBox(height: 12),
      Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('自动搜索歌词'),
                const SizedBox(height: 4),
                Text(
                  c.automaticEnabled
                      ? '已开启 · 可靠匹配后自动保存，不确定时由你选择'
                      : '可选开启 · 只为播放的歌曲查找，不扫描整库',
                  style: const TextStyle(fontSize: 13),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          CupertinoSwitch(
            key: const Key('lyrics-auto-switch'),
            value: c.automaticEnabled,
            onChanged: _dialogOpen ? null : _toggleAutomatic,
          ),
        ],
      ),
    ];
  }

  Widget _fontSizeControls(BuildContext context) {
    final c = widget.controller;
    final size = c.fontSize;
    final smaller = size > LyricsController.minFontSize;
    final larger = size < LyricsController.maxFontSize;
    return Column(
      key: const Key('lyrics-font-size-controls'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 12,
          children: [
            Text(
              '歌词字号 · ${size.toInt()}',
              key: const Key('lyrics-font-size-value'),
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            CupertinoButton(
              key: const Key('lyrics-font-size-reset'),
              padding: const EdgeInsets.symmetric(horizontal: 8),
              onPressed: size == LyricsController.defaultFontSize
                  ? null
                  : () => c.setFontSize(LyricsController.defaultFontSize),
              child: const Text('恢复默认'),
            ),
          ],
        ),
        Row(
          children: [
            CupertinoButton(
              key: const Key('lyrics-font-size-decrease'),
              onPressed: smaller ? () => c.setFontSize(size - 1) : null,
              child: Semantics(
                label: '减小歌词字号',
                excludeSemantics: true,
                child: const Text('A', style: TextStyle(fontSize: 16)),
              ),
            ),
            Expanded(
              child: Semantics(
                key: const Key('lyrics-font-size-semantics'),
                slider: true,
                label: '歌词字号',
                value: '${size.toInt()} 点',
                increasedValue: larger ? '${size.toInt() + 1} 点' : null,
                decreasedValue: smaller ? '${size.toInt() - 1} 点' : null,
                onIncrease: larger ? () => c.setFontSize(size + 1) : null,
                onDecrease: smaller ? () => c.setFontSize(size - 1) : null,
                excludeSemantics: true,
                child: CupertinoSlider(
                  key: const Key('lyrics-font-size-slider'),
                  value: size,
                  min: LyricsController.minFontSize,
                  max: LyricsController.maxFontSize,
                  divisions:
                      (LyricsController.maxFontSize -
                              LyricsController.minFontSize)
                          .toInt(),
                  onChanged: c.setFontSize,
                ),
              ),
            ),
            CupertinoButton(
              key: const Key('lyrics-font-size-increase'),
              onPressed: larger ? () => c.setFontSize(size + 1) : null,
              child: Semantics(
                label: '增大歌词字号',
                excludeSemantics: true,
                child: const Text('A', style: TextStyle(fontSize: 26)),
              ),
            ),
          ],
        ),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: CupertinoColors.tertiarySystemFill.resolveFrom(context),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            '让每一句歌词，刚好看得清',
            key: const Key('lyrics-font-size-preview'),
            style: TextStyle(
              fontSize: size,
              height: 1.4,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        const SizedBox(height: 8),
        const Text(
          '所有歌曲共用，自动记住本机设置；仍跟随系统文字大小。',
          style: TextStyle(fontSize: 12),
        ),
        if (c.fontSizeError != null) ...[
          const SizedBox(height: 12),
          Text(c.fontSizeError!, key: const Key('lyrics-font-size-error')),
        ],
      ],
    );
  }

  Future<void> _showOptions({bool fontSizeOnly = false}) async {
    if (_optionsOpen) return;
    registerLyricsConversionLicense();
    _optionsOpen = true;
    final theme = CupertinoTheme.of(context);
    try {
      await showCupertinoModalPopup<void>(
        context: context,
        semanticsDismissible: true,
        builder: (context) => CupertinoTheme(
          data: theme,
          child: DefaultTextStyle(
            style: theme.textTheme.textStyle,
            child: StatefulBuilder(
              builder: (context, refresh) {
                _refreshSheet = refresh;
                return AnimatedBuilder(
                  animation: widget.controller,
                  builder: (context, _) => Padding(
                    padding: EdgeInsets.only(
                      bottom: MediaQuery.viewInsetsOf(context).bottom,
                    ),
                    child: Container(
                      constraints: const BoxConstraints(maxWidth: 600),
                      color: CupertinoColors.systemBackground.resolveFrom(
                        context,
                      ),
                      child: SafeArea(
                        top: false,
                        child: ConstrainedBox(
                          constraints: BoxConstraints(
                            maxHeight:
                                (MediaQuery.sizeOf(context).height -
                                    MediaQuery.viewInsetsOf(context).bottom) *
                                .8,
                          ),
                          child: SingleChildScrollView(
                            key: const Key('lyrics-options-sheet'),
                            padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Align(
                                  alignment: Alignment.centerRight,
                                  child: CupertinoButton(
                                    onPressed: () => Navigator.pop(context),
                                    child: const Text('完成'),
                                  ),
                                ),
                                Text(
                                  fontSizeOnly ? '歌词字号' : '查找与管理歌词',
                                  style: const TextStyle(
                                    fontSize: 22,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                const SizedBox(height: 16),
                                if (fontSizeOnly) ...[
                                  _fontSizeControls(context),
                                ] else
                                  ..._management(context),
                                if (!fontSizeOnly &&
                                    widget.controller.document != null) ...[
                                  const SizedBox(height: 20),
                                  Text(
                                    '来源：${widget.controller.document!.source}',
                                    key: const Key('lyrics-source'),
                                  ),
                                ],
                                if (!fontSizeOnly) ...[
                                  const SizedBox(height: 16),
                                  const _SelectableLyricsText(
                                    '在线歌词来源：LRCLIB\nhttps://lrclib.net/docs',
                                    style: TextStyle(fontSize: 12),
                                  ),
                                  Align(
                                    alignment: Alignment.centerLeft,
                                    child: CupertinoButton(
                                      key: const Key(
                                        'lyrics-conversion-license',
                                      ),
                                      onPressed: () => Navigator.of(context)
                                          .push(
                                            CupertinoPageRoute<void>(
                                              builder: (_) =>
                                                  const _LyricsLicensesPage(),
                                            ),
                                          ),
                                      child: const Text('字形转换开源许可 · OpenCC'),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      );
    } finally {
      _refreshSheet = null;
      _optionsOpen = false;
    }
  }

  Widget _immersive(
    BuildContext context,
    LyricsDocument? document,
    int active,
  ) {
    final hasTrack = widget.controller.track != null;
    final empty = document == null || document.text.trim().isEmpty;
    return Column(
      key: const Key('lyrics-panel'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            const Expanded(
              child: Text(
                '歌词',
                style: TextStyle(
                  color: Color(0xB3FFFFFF),
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            Semantics(
              label: '调整歌词字号',
              child: CupertinoButton(
                key: const Key('lyrics-font-size'),
                onPressed: () => _showOptions(fontSizeOnly: true),
                child: const Icon(
                  CupertinoIcons.textformat_size,
                  color: CupertinoColors.white,
                ),
              ),
            ),
            Semantics(
              label: '歌词选项',
              child: CupertinoButton(
                key: const Key('lyrics-options'),
                onPressed: _showOptions,
                child: const Icon(
                  CupertinoIcons.ellipsis,
                  color: CupertinoColors.white,
                ),
              ),
            ),
          ],
        ),
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              return ShaderMask(
                shaderCallback: (bounds) => const LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    CupertinoColors.transparent,
                    CupertinoColors.white,
                    CupertinoColors.white,
                    CupertinoColors.transparent,
                  ],
                  stops: [0, .06, .92, 1],
                ).createShader(bounds),
                blendMode: BlendMode.dstIn,
                child: NotificationListener<ScrollStartNotification>(
                  onNotification: (notification) {
                    if (notification.dragDetails != null && _follow) {
                      setState(() => _follow = false);
                    }
                    return false;
                  },
                  child: _lyricsBody(
                    document,
                    active,
                    hasTrack,
                    viewportHeight: constraints.maxHeight,
                  ),
                ),
              );
            },
          ),
        ),
        if (empty && hasTrack && document?.instrumental != true)
          Center(
            child: _LyricsActionButton(
              key: const Key('lyrics-add'),
              onPressed: widget.controller.automaticEnabled
                  ? _showOptions
                  : () => _toggleAutomatic(true),
              icon: const Icon(
                CupertinoIcons.add,
                color: CupertinoColors.white,
              ),
              label: Text(
                widget.controller.automaticEnabled ? '选择版本 / 歌词选项' : '开启自动歌词',
                style: const TextStyle(color: CupertinoColors.white),
              ),
            ),
          ),
        if (!_follow && document?.isSynced == true)
          Center(
            child: _LyricsActionButton(
              key: const Key('lyrics-follow'),
              onPressed: () => setState(() {
                _follow = true;
                _lastActive = -2;
              }),
              icon: const Icon(
                CupertinoIcons.location,
                size: 18,
                color: CupertinoColors.white,
              ),
              label: const Text(
                '回到当前歌词',
                style: TextStyle(color: CupertinoColors.white),
              ),
            ),
          ),
      ],
    );
  }

  Widget _lyricsBody(
    LyricsDocument? document,
    int active,
    bool hasTrack, {
    double viewportHeight = 0,
  }) {
    return LayoutBuilder(
      builder: (context, constraints) {
        _scheduleScroll(document, active, (
          constraints.maxWidth,
          constraints.maxHeight,
          widget.controller.fontSize,
          MediaQuery.textScalerOf(context),
          widget.immersive,
        ));
        return _lyricsContent(
          document,
          active,
          hasTrack,
          viewportHeight: viewportHeight,
        );
      },
    );
  }

  Widget _lyricsContent(
    LyricsDocument? document,
    int active,
    bool hasTrack, {
    double viewportHeight = 0,
  }) {
    if (document == null ||
        document.instrumental ||
        document.text.trim().isEmpty) {
      return SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 32),
          child: Text(
            !hasTrack
                ? '先选择一首歌曲'
                : document?.instrumental == true
                ? '纯音乐 · 无歌词'
                : widget.controller.searchingAutomatically
                ? '正在自动匹配歌词…'
                : widget.controller.error != null
                ? '${widget.controller.error}\n播放不受影响，可在歌词选项中重试。'
                : widget.controller.candidates.isNotEmpty
                ? '找到 ${widget.controller.candidates.length} 个歌词版本\n请在歌词选项中核对选择，避免匹配错误。'
                : widget.controller.automaticEnabled
                ? widget.controller.notice ?? '自动歌词已开启\n正在准备歌曲信息…'
                : '开启自动歌词\n播放时智能匹配，下载后可离线查看。',
            key: const Key('lyrics-empty'),
            textAlign: TextAlign.center,
            style: const TextStyle(color: Color(0xFF9FAABD), height: 1.7),
          ),
        ),
      );
    }
    if (!document.isSynced) {
      return SingleChildScrollView(
        key: const Key('lyrics-plain-scroll'),
        controller: _scroll,
        child: _SelectableLyricsText(
          document.text,
          key: const Key('lyrics-plain'),
          style: TextStyle(
            height: 1.55,
            fontSize: widget.controller.fontSize,
            fontWeight: widget.immersive ? FontWeight.w700 : FontWeight.w400,
            color: widget.immersive ? CupertinoColors.white : null,
          ),
        ),
      );
    }
    return SingleChildScrollView(
      key: const Key('lyrics-synced-scroll'),
      controller: _scroll,
      padding: widget.immersive
          ? EdgeInsets.symmetric(vertical: viewportHeight * .38)
          : EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: List.generate(document.lines.length, (index) {
          final line = document.lines[index];
          final selected = index == active;
          return Padding(
            key: _lineKeys[index],
            padding: const EdgeInsets.symmetric(vertical: 3),
            child: Semantics(
              selected: selected,
              label: '${_duration(line.time)} ${line.text}',
              child: CupertinoButton(
                key: ValueKey('lyrics-line-$index'),
                alignment: Alignment.centerLeft,
                color: selected && !widget.immersive
                    ? const Color(0x22FFB86B)
                    : CupertinoColors.transparent,
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 12,
                ),
                onPressed: () {
                  setState(() {
                    _follow = true;
                    _lastActive = -2;
                  });
                  widget.onSeek(line.time);
                },
                child: Text(
                  line.text.isEmpty ? '♪' : line.text,
                  style: TextStyle(
                    color: widget.immersive
                        ? (selected
                              ? CupertinoColors.white
                              : const Color(0x80FFFFFF))
                        : (selected
                              ? const Color(0xFFFFB86B)
                              : const Color(0xFF9FAABD)),
                    height: widget.immersive ? 1.3 : 1.6,
                    fontSize: widget.controller.fontSize,
                    fontWeight: widget.immersive || selected
                        ? FontWeight.w700
                        : FontWeight.w400,
                  ),
                ),
              ),
            ),
          );
        }),
      ),
    );
  }
}

String _duration(Duration duration) =>
    '${duration.inMinutes}:${(duration.inSeconds % 60).toString().padLeft(2, '0')}';

String _kind(LyricsDocument document) => document.instrumental
    ? '纯音乐'
    : document.isSynced
    ? '逐行同步'
    : '纯文本';

String? _candidateWarning(
  LyricsController controller,
  LyricsCandidate candidate,
) {
  final track = controller.track;
  if (track == null) return null;
  final warnings = <String>[];
  if (normalizeLyricsIdentity(track.title) !=
      normalizeLyricsIdentity(candidate.title)) {
    warnings.add('歌名或版本标记不同');
  }
  if (track.artist.isNotEmpty &&
      normalizeLyricsIdentity(track.artist) !=
          normalizeLyricsIdentity(candidate.artist)) {
    warnings.add('歌手不同');
  }
  if (track.duration > Duration.zero && candidate.duration > Duration.zero) {
    final delta = (candidate.duration - track.duration).inMilliseconds.abs();
    if (delta > 3000) {
      warnings.add('时长相差 ${(delta / 1000).toStringAsFixed(1)} 秒');
    }
  } else {
    warnings.add('时长未知');
  }
  return warnings.isEmpty ? null : '${warnings.join(' · ')}，请核对';
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
      return CupertinoAlertDialog(
        key: const Key('lyrics-preview-dialog'),
        title: const Text('预览歌词'),
        content: SizedBox(
          width: 520,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                candidate.title,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 6),
              Text(
                [
                  candidate.artist,
                  if (candidate.album.isNotEmpty) candidate.album,
                  '${_duration(candidate.duration)} · ${_kind(doc)}',
                ].join(' · '),
              ),
              const SizedBox(height: 8),
              Text(
                '${doc.source} · ${controller.preferSimplified ? '简体显示' : '原文显示'} · 可滚动预览',
                style: const TextStyle(fontSize: 12),
              ),
              if (warning != null) ...[
                const SizedBox(height: 10),
                Text(
                  warning,
                  style: TextStyle(
                    color: CupertinoColors.systemRed.resolveFrom(context),
                  ),
                ),
              ],
              if (!valid) ...[
                const SizedBox(height: 10),
                const Text('当前歌曲或搜索结果已变更，请关闭后重新选择。'),
              ],
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 14),
                child: _LyricsSeparator(),
              ),
              SizedBox(
                height: (MediaQuery.sizeOf(context).height * .34).clamp(
                  120,
                  320,
                ),
                child: doc.instrumental
                    ? const Center(child: Text('此版本标记为纯音乐，无歌词。'))
                    : SingleChildScrollView(
                        key: const Key('lyrics-preview-scroll'),
                        child: _SelectableLyricsText(
                          doc.isSynced
                              ? doc.lines
                                    .map(
                                      (line) =>
                                          '${_duration(line.time)}  ${line.text}',
                                    )
                                    .join('\n\n')
                              : doc.text,
                          style: const TextStyle(height: 1.65),
                        ),
                      ),
              ),
              const SizedBox(height: 12),
              Text(
                controller.originalDocument == null
                    ? '保存到本机后可离线显示。'
                    : '保存后替换这首歌当前的歌词；取消不会修改。',
              ),
            ],
          ),
        ),
        actions: [
          CupertinoDialogAction(
            key: const Key('lyrics-preview-cancel'),
            onPressed: () => Navigator.pop(context, false),
            child: const Text('返回结果'),
          ),
          CupertinoDialogAction(
            key: const Key('lyrics-preview-save'),
            onPressed: valid ? () => Navigator.pop(context, true) : null,
            child: const Text('保存到本机'),
          ),
        ],
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

  @override
  Widget build(BuildContext context) => CupertinoAlertDialog(
    key: const Key('lyrics-consent-dialog'),
    title: const Text('搜索在线歌词'),
    content: SizedBox(
      width: 420,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            '核对歌名和歌手，可编辑搜索词，不会修改音乐标签。会逐步忽略专辑、尝试繁简字形；仍无匹配时按歌名查找，由你预览确认。',
          ),
          const SizedBox(height: 16),
          CupertinoTextField(
            key: const Key('lyrics-query-title'),
            controller: _title,
            placeholder: '歌名（必填）',
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 12),
          CupertinoTextField(
            key: const Key('lyrics-query-artist'),
            controller: _artist,
            onChanged: (_) => setState(() {}),
            placeholder: '歌手（推荐，可留空）',
          ),
          const SizedBox(height: 12),
          CupertinoTextField(
            key: const Key('lyrics-query-album'),
            controller: _album,
            placeholder: '专辑（可选）',
          ),
          const SizedBox(height: 16),
          const Text(
            '搜索会将以上歌曲信息及繁简变体发送至 LRCLIB（lrclib.net），服务可看到你的 IP。音频、文件路径、时长不会上传。',
            style: TextStyle(fontSize: 12),
          ),
          CupertinoButton(
            onPressed: () => setState(() => _showPrivacy = !_showPrivacy),
            child: const Text('来源、隐私与版权说明', style: TextStyle(fontSize: 13)),
          ),
          if (_showPrivacy)
            const Text(
              'LRCLIB 是社区歌词库，可能未收录、存在不同版本或时间轴错误。只有保存后才替换当前歌词，内容仅缓存到本机。版权归原权利人，请仅在获准使用时下载。每次手动搜索均需确认，取消或返回不会发送请求。',
            ),
        ],
      ),
    ),
    actions: [
      CupertinoDialogAction(
        key: const Key('lyrics-consent-cancel'),
        onPressed: () => Navigator.pop(context),
        child: const Text('取消'),
      ),
      CupertinoDialogAction(
        key: const Key('lyrics-consent-confirm'),
        onPressed: _title.text.trim().isEmpty
            ? null
            : () => Navigator.pop(context, [
                _title.text.trim(),
                _artist.text.trim(),
                _album.text.trim(),
              ]),
        child: const Text('同意并搜索'),
      ),
    ],
  );
}

class _PasteLyricsDialog extends StatefulWidget {
  const _PasteLyricsDialog();
  @override
  State<_PasteLyricsDialog> createState() => _PasteLyricsDialogState();
}

class _PasteLyricsDialogState extends State<_PasteLyricsDialog> {
  final _text = TextEditingController();
  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => CupertinoAlertDialog(
    key: const Key('lyrics-paste-dialog'),
    title: const Text('粘贴歌词'),
    content: SizedBox(
      width: 420,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('支持带时间戳的 LRC 或纯文本。仅保存在本机，导入后替换当前歌词。'),
          const SizedBox(height: 12),
          CupertinoTextField(
            key: const Key('lyrics-paste-input'),
            controller: _text,
            minLines: 4,
            maxLines: 8,
            maxLength: 300000,
            placeholder: '歌词文本',
            onChanged: (_) => setState(() {}),
          ),
        ],
      ),
    ),
    actions: [
      CupertinoDialogAction(
        onPressed: () => Navigator.pop(context),
        child: const Text('取消'),
      ),
      CupertinoDialogAction(
        key: const Key('lyrics-paste-confirm'),
        onPressed: _text.text.trim().isEmpty
            ? null
            : () => Navigator.pop(context, _text.text),
        child: const Text('导入'),
      ),
    ],
  );
}

class _LyricsActionButton extends StatelessWidget {
  const _LyricsActionButton({
    super.key,
    required this.icon,
    required this.label,
    required this.onPressed,
  });
  final Widget icon, label;
  final VoidCallback? onPressed;
  @override
  Widget build(BuildContext context) => CupertinoButton(
    onPressed: onPressed,
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        icon,
        const SizedBox(width: 8),
        Flexible(child: label),
      ],
    ),
  );
}

class _LyricsSeparator extends StatelessWidget {
  const _LyricsSeparator();
  @override
  Widget build(BuildContext context) => Container(
    height: .5,
    color: CupertinoColors.separator.resolveFrom(context),
  );
}

/// Selectable lyrics use Cupertino handles and a native context menu.
class _SelectableLyricsText extends StatefulWidget {
  const _SelectableLyricsText(this.data, {super.key, this.style});
  final String data;
  final TextStyle? style;
  @override
  State<_SelectableLyricsText> createState() => _SelectableLyricsTextState();
}

class _SelectableLyricsTextState extends State<_SelectableLyricsText> {
  final _focus = FocusNode();
  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SelectableRegion(
    focusNode: _focus,
    selectionControls: cupertinoTextSelectionHandleControls,
    contextMenuBuilder: (context, state) =>
        CupertinoAdaptiveTextSelectionToolbar.buttonItems(
          anchors: state.contextMenuAnchors,
          buttonItems: state.contextMenuButtonItems,
        ),
    child: Text(widget.data, style: widget.style),
  );
}

class _LyricsLicensesPage extends StatefulWidget {
  const _LyricsLicensesPage();
  @override
  State<_LyricsLicensesPage> createState() => _LyricsLicensesPageState();
}

class _LyricsLicensesPageState extends State<_LyricsLicensesPage> {
  late final _licenses = LicenseRegistry.licenses.toList();
  @override
  Widget build(BuildContext context) => CupertinoPageScaffold(
    navigationBar: const CupertinoNavigationBar(middle: Text('开源许可')),
    child: SafeArea(
      child: FutureBuilder<List<LicenseEntry>>(
        future: _licenses,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return const Center(child: Text('暂时无法加载开源许可。'));
          }
          final entries = snapshot.data;
          if (entries == null) {
            return const Center(child: CupertinoActivityIndicator());
          }
          return ListView.separated(
            padding: const EdgeInsets.all(20),
            itemCount: entries.length,
            separatorBuilder: (_, _) => const Padding(
              padding: EdgeInsets.symmetric(vertical: 20),
              child: _LyricsSeparator(),
            ),
            itemBuilder: (context, index) {
              final entry = entries[index];
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    entry.packages.join(', '),
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 12),
                  _SelectableLyricsText(
                    entry.paragraphs.map((p) => p.text).join('\n\n'),
                    style: const TextStyle(fontSize: 13, height: 1.5),
                  ),
                ],
              );
            },
          );
        },
      ),
    ),
  );
}
