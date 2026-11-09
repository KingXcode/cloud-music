import 'package:flutter/material.dart';

import '../lyrics/lyrics_controller.dart';
import '../lyrics/lyrics_models.dart';
import '../lyrics/lyrics_matching.dart';
import '../lyrics/lyrics_script.dart';

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

  void _scheduleScroll(LyricsDocument? document, int active) {
    if (!identical(document, _shownDocument)) {
      _shownDocument = document;
      _lineKeys = List.generate(
        document?.lines.length ?? 0,
        (_) => GlobalKey(),
      );
      _lastActive = -2;
      _follow = true;
    }
    if (active == _lastActive) return;
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
          duration: const Duration(milliseconds: 420),
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
    final query = await showDialog<List<String>>(
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
    final accepted = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        key: const Key('lyrics-auto-consent'),
        title: const Text('开启自动歌词'),
        scrollable: true,
        content: const Text(
          '开启后，播放所选歌曲时会自动向 LRCLIB（lrclib.net）发送歌名、歌手和可选专辑名，包括繁简字形变体；该服务也会看到你的 IP 地址。无结果时会省略专辑再查找。不会上传音频、文件路径或时长，也不会扫描整库联网。\n\n'
          '仅在歌名、歌手、版本和时长匹配可靠时自动保存歌词；不确定时由你选择。歌词仅缓存到本机，版权归原权利人，请仅在获准使用时下载。\n\n'
          '记住本机选择，之后无需逐曲确认。可随时在歌词选项中关闭。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('暂不开启'),
          ),
          FilledButton(
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
    final text = await showDialog<String>(
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
      _scheduleScroll(document, active);
      if (widget.immersive) return _immersive(context, document, active);
      return Container(
        key: const Key('lyrics-panel'),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: const Color(0xFF111B2E),
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
                child: TextButton(
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
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
            const SizedBox(height: 8),
            const SelectableText(
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
    final accepted = await showDialog<bool>(
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
    final colors = Theme.of(context).colorScheme;
    final candidates = c.candidates
        .where((candidate) => !_syncedOnly || candidate.document.isSynced)
        .toList();
    return [
      if (c.track != null)
        Container(
          key: const Key('lyrics-track-summary'),
          padding: const EdgeInsets.all(16),
          margin: const EdgeInsets.only(bottom: 16),
          decoration: BoxDecoration(
            color: colors.surfaceContainerHighest.withValues(alpha: .5),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.music_note_rounded, color: colors.primary),
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
                      style: TextStyle(color: colors.primary, fontSize: 12),
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
          FilledButton.icon(
            key: const Key('lyrics-search'),
            onPressed: enabled ? _search : null,
            icon: const Icon(Icons.search),
            label: Text(c.error == null ? '搜索歌词' : '修改并重试'),
          ),
          OutlinedButton.icon(
            key: const Key('lyrics-import'),
            onPressed: enabled ? c.importFile : null,
            icon: const Icon(Icons.file_open_outlined),
            label: const Text('导入 LRC / TXT'),
          ),
          TextButton(
            key: const Key('lyrics-paste'),
            onPressed: enabled ? _paste : null,
            child: const Text('粘贴歌词'),
          ),
          if (c.busy)
            TextButton(
              key: const Key('lyrics-cancel-search'),
              onPressed: c.cancelSearch,
              child: const Text('取消'),
            ),
        ],
      ),
      if (c.busy) ...[
        const SizedBox(height: 12),
        const LinearProgressIndicator(key: Key('lyrics-loading')),
        const SizedBox(height: 8),
        Text(c.searchStage ?? '正在保存到本机…'),
      ],
      if (c.error != null)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Text(
            c.error!,
            key: const Key('lyrics-error'),
            style: TextStyle(color: colors.error),
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
        Wrap(
          spacing: 8,
          runSpacing: 4,
          children: [
            ChoiceChip(
              key: const Key('lyrics-filter-all'),
              label: const Text('全部'),
              selected: !_syncedOnly,
              onSelected: (_) {
                setState(() => _syncedOnly = false);
                _refreshSheet?.call(() {});
              },
            ),
            ChoiceChip(
              key: const Key('lyrics-filter-synced'),
              label: const Text('仅逐行同步'),
              selected: _syncedOnly,
              onSelected: (_) {
                setState(() => _syncedOnly = true);
                _refreshSheet?.call(() {});
              },
            ),
          ],
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
              return Material(
                color: colors.surfaceContainerHighest.withValues(alpha: .4),
                borderRadius: BorderRadius.circular(14),
                clipBehavior: Clip.antiAlias,
                child: ListTile(
                  key: ValueKey('lyrics-candidate-${candidate.id}'),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  title: Text(
                    candidate.title,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  subtitle: Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          [
                            candidate.artist.isEmpty
                                ? '歌手未知'
                                : candidate.artist,
                            if (candidate.album.isNotEmpty) candidate.album,
                          ].join(' · '),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          '${_duration(candidate.duration)} · '
                          '${_kind(candidate.document)} · LRCLIB',
                        ),
                        if (warning != null) ...[
                          const SizedBox(height: 6),
                          Text(warning, style: TextStyle(color: colors.error)),
                        ],
                        const SizedBox(height: 6),
                        Text('预览歌词', style: TextStyle(color: colors.primary)),
                      ],
                    ),
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: enabled ? () => _preview(candidate) : null,
                ),
              );
            },
          ),
      ],
      const SizedBox(height: 20),
      const Divider(),
      const SizedBox(height: 12),
      const Text('歌词文字', style: TextStyle(fontWeight: FontWeight.w600)),
      const SizedBox(height: 8),
      Wrap(
        spacing: 8,
        runSpacing: 4,
        children: [
          ChoiceChip(
            key: const Key('lyrics-script-simplified'),
            label: const Text('简体中文'),
            selected: c.preferSimplified,
            onSelected: (_) => c.setPreferSimplified(true),
          ),
          ChoiceChip(
            key: const Key('lyrics-script-original'),
            label: const Text('保留原文'),
            selected: !c.preferSimplified,
            onSelected: (_) => c.setPreferSimplified(false),
          ),
        ],
      ),
      const SizedBox(height: 6),
      Text(
        '仅在本机转换中文字形，保留原始歌词和时间轴；不是翻译。',
        style: Theme.of(context).textTheme.bodySmall,
      ),
      const SizedBox(height: 12),
      Material(
        color: Colors.transparent,
        child: SwitchListTile.adaptive(
          key: const Key('lyrics-auto-switch'),
          contentPadding: EdgeInsets.zero,
          title: const Text('自动搜索歌词'),
          subtitle: Text(
            c.automaticEnabled
                ? '已开启 · 可靠匹配后自动保存，不确定时由你选择'
                : '可选开启 · 只为播放的歌曲查找，不扫描整库',
          ),
          value: c.automaticEnabled,
          onChanged: _dialogOpen ? null : _toggleAutomatic,
        ),
      ),
    ];
  }

  Future<void> _showOptions() async {
    if (_optionsOpen) return;
    registerLyricsConversionLicense();
    _optionsOpen = true;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      useSafeArea: true,
      builder: (context) => StatefulBuilder(
        builder: (context, refresh) {
          _refreshSheet = refresh;
          return AnimatedBuilder(
            animation: widget.controller,
            builder: (context, _) => ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.sizeOf(context).height * .8,
              ),
              child: SingleChildScrollView(
                key: const Key('lyrics-options-sheet'),
                padding: const EdgeInsets.fromLTRB(24, 0, 24, 32),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      '查找与管理歌词',
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 16),
                    ..._management(context),
                    if (widget.controller.document != null) ...[
                      const SizedBox(height: 20),
                      Text(
                        '来源：${widget.controller.document!.source}',
                        key: const Key('lyrics-source'),
                      ),
                    ],
                    const SizedBox(height: 16),
                    const SelectableText(
                      '在线歌词来源：LRCLIB\nhttps://lrclib.net/docs',
                      style: TextStyle(fontSize: 12),
                    ),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton(
                        key: const Key('lyrics-conversion-license'),
                        onPressed: () => showLicensePage(context: context),
                        child: const Text('字形转换开源许可 · OpenCC'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
    _refreshSheet = null;
    _optionsOpen = false;
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
                  color: Colors.white70,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            IconButton(
              key: const Key('lyrics-options'),
              tooltip: '歌词选项',
              onPressed: _showOptions,
              icon: const Icon(Icons.more_horiz, color: Colors.white),
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
                    Colors.transparent,
                    Colors.white,
                    Colors.white,
                    Colors.transparent,
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
            child: TextButton.icon(
              key: const Key('lyrics-add'),
              onPressed: widget.controller.automaticEnabled
                  ? _showOptions
                  : () => _toggleAutomatic(true),
              icon: const Icon(Icons.add, color: Colors.white),
              label: Text(
                widget.controller.automaticEnabled ? '选择版本 / 歌词选项' : '开启自动歌词',
                style: const TextStyle(color: Colors.white),
              ),
            ),
          ),
        if (!_follow && document?.isSynced == true)
          Center(
            child: TextButton.icon(
              key: const Key('lyrics-follow'),
              onPressed: () => setState(() {
                _follow = true;
                _lastActive = -2;
              }),
              icon: const Icon(
                Icons.my_location,
                size: 18,
                color: Colors.white,
              ),
              label: const Text(
                '回到当前歌词',
                style: TextStyle(color: Colors.white),
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
        child: SelectableText(
          document.text,
          key: const Key('lyrics-plain'),
          style: TextStyle(
            height: 1.55,
            fontSize: widget.immersive ? 30 : 14,
            fontWeight: widget.immersive ? FontWeight.w700 : FontWeight.w400,
            color: widget.immersive ? Colors.white : null,
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
              child: TextButton(
                key: ValueKey('lyrics-line-$index'),
                style: TextButton.styleFrom(
                  alignment: Alignment.centerLeft,
                  foregroundColor: widget.immersive
                      ? (selected ? Colors.white : const Color(0x80FFFFFF))
                      : (selected
                            ? const Color(0xFFFFB86B)
                            : const Color(0xFF9FAABD)),
                  backgroundColor: selected && !widget.immersive
                      ? const Color(0x22FFB86B)
                      : Colors.transparent,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 12,
                  ),
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
                    height: widget.immersive ? 1.3 : 1.6,
                    fontSize: widget.immersive ? 32 : 16,
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
      return AlertDialog(
        key: const Key('lyrics-preview-dialog'),
        insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
        title: const Text('预览歌词'),
        scrollable: true,
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
                style: Theme.of(context).textTheme.bodySmall,
              ),
              if (warning != null) ...[
                const SizedBox(height: 10),
                Text(
                  warning,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ],
              if (!valid) ...[
                const SizedBox(height: 10),
                const Text('当前歌曲或搜索结果已变更，请关闭后重新选择。'),
              ],
              const Divider(height: 28),
              SizedBox(
                height: (MediaQuery.sizeOf(context).height * .34).clamp(
                  120,
                  320,
                ),
                child: doc.instrumental
                    ? const Center(child: Text('此版本标记为纯音乐，无歌词。'))
                    : SingleChildScrollView(
                        key: const Key('lyrics-preview-scroll'),
                        child: SelectableText(
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
          TextButton(
            key: const Key('lyrics-preview-cancel'),
            onPressed: () => Navigator.pop(context, false),
            child: const Text('返回结果'),
          ),
          FilledButton.icon(
            key: const Key('lyrics-preview-save'),
            onPressed: valid ? () => Navigator.pop(context, true) : null,
            icon: const Icon(Icons.download_done),
            label: const Text('保存到本机'),
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

  @override
  void dispose() {
    _title.dispose();
    _artist.dispose();
    _album.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    key: const Key('lyrics-consent-dialog'),
    insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
    title: const Text('搜索在线歌词'),
    scrollable: true,
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
          TextField(
            key: const Key('lyrics-query-title'),
            controller: _title,
            decoration: const InputDecoration(labelText: '歌名（必填）'),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 12),
          TextField(
            key: const Key('lyrics-query-artist'),
            controller: _artist,
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(labelText: '歌手（推荐，可留空）'),
          ),
          const SizedBox(height: 12),
          TextField(
            key: const Key('lyrics-query-album'),
            controller: _album,
            decoration: const InputDecoration(labelText: '专辑（可选）'),
          ),
          const SizedBox(height: 16),
          const Text(
            '搜索会将以上歌曲信息及繁简变体发送至 LRCLIB（lrclib.net），服务可看到你的 IP。音频、文件路径、时长不会上传。',
            style: TextStyle(fontSize: 12),
          ),
          const ExpansionTile(
            tilePadding: EdgeInsets.zero,
            title: Text('来源、隐私与版权说明', style: TextStyle(fontSize: 13)),
            children: [
              Text(
                'LRCLIB 是社区歌词库，可能未收录、存在不同版本或时间轴错误。只有保存后才替换当前歌词，内容仅缓存到本机。版权归原权利人，请仅在获准使用时下载。每次手动搜索均需确认，取消或返回不会发送请求。',
              ),
            ],
          ),
        ],
      ),
    ),
    actions: [
      TextButton(
        key: const Key('lyrics-consent-cancel'),
        onPressed: () => Navigator.pop(context),
        child: const Text('取消'),
      ),
      FilledButton(
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
  Widget build(BuildContext context) => AlertDialog(
    key: const Key('lyrics-paste-dialog'),
    insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
    title: const Text('粘贴歌词'),
    scrollable: true,
    content: SizedBox(
      width: 420,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('支持带时间戳的 LRC 或纯文本。仅保存在本机，导入后替换当前歌词。'),
          const SizedBox(height: 12),
          TextField(
            key: const Key('lyrics-paste-input'),
            controller: _text,
            minLines: 4,
            maxLines: 8,
            maxLength: 300000,
            decoration: const InputDecoration(labelText: '歌词文本'),
            onChanged: (_) => setState(() {}),
          ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('取消'),
      ),
      FilledButton(
        key: const Key('lyrics-paste-confirm'),
        onPressed: _text.text.trim().isEmpty
            ? null
            : () => Navigator.pop(context, _text.text),
        child: const Text('导入'),
      ),
    ],
  );
}
