import 'package:flutter/material.dart';

import '../lyrics/lyrics_controller.dart';
import '../lyrics/lyrics_models.dart';

/// 仅在局部重建的歌词视图，打开此面板不会连接服务器。
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
    setState(() => _dialogOpen = true);
    _refreshSheet?.call(() {});
    final query = await showDialog<List<String>>(
      context: context,
      builder: (_) => _SearchConsentDialog(
        title: track.title,
        artist: track.artist,
        album: track.album,
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
    await c.search(title: query[0], artist: query[1], album: query[2]);
  }

  Future<void> _paste() async {
    final c = widget.controller;
    final track = c.track;
    final selection = c.selectionIdentity;
    if (_dialogOpen || c.busy || track == null) return;
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
                '来源：${document.source}',
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

  List<Widget> _management(BuildContext context) {
    final c = widget.controller;
    final enabled = c.track != null && !c.busy && !_dialogOpen;
    return [
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          OutlinedButton(
            key: const Key('lyrics-search'),
            onPressed: enabled ? _search : null,
            child: Text(c.error == null ? '搜索下载' : '重试搜索'),
          ),
          OutlinedButton(
            key: const Key('lyrics-import'),
            onPressed: enabled ? c.importFile : null,
            child: const Text('导入 LRC / TXT'),
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
        const SizedBox(height: 8),
        const LinearProgressIndicator(key: Key('lyrics-loading')),
        const Text('正在处理歌词…'),
      ],
      if (c.error != null)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Text(
            c.error!,
            key: const Key('lyrics-error'),
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        ),
      if (c.retryAfter != null)
        Text('服务请求过多，请约 ${c.retryAfter!.inSeconds + 1} 秒后重试。'),
      if (c.notice != null)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Text(c.notice!, key: const Key('lyrics-notice')),
        ),
      if (c.candidates.isNotEmpty) ...[
        const SizedBox(height: 8),
        const Text('请选择匹配版本；选中后才会替换当前歌词。'),
        SizedBox(
          height: 220,
          child: ListView.separated(
            key: const Key('lyrics-candidates'),
            primary: false,
            itemCount: c.candidates.length,
            separatorBuilder: (_, _) => const Divider(),
            itemBuilder: (context, index) {
              final candidate = c.candidates[index];
              final trackDuration = c.track?.duration ?? Duration.zero;
              final mismatch =
                  trackDuration > Duration.zero &&
                  candidate.duration > Duration.zero &&
                  (candidate.duration - trackDuration).inMilliseconds.abs() >
                      2000;
              final kind = candidate.document.instrumental
                  ? '纯音乐'
                  : candidate.document.isSynced
                  ? '逐行同步'
                  : '纯文本';
              return Material(
                color: Colors.transparent,
                child: ListTile(
                  key: ValueKey('lyrics-candidate-${candidate.id}'),
                  contentPadding: EdgeInsets.zero,
                  title: Text(candidate.title),
                  subtitle: Text(
                    [
                      candidate.artist.isEmpty ? '歌手未知' : candidate.artist,
                      if (candidate.album.isNotEmpty) candidate.album,
                      '${_duration(candidate.duration)} · $kind',
                      if (mismatch) '时长与当前歌曲相差超过 2 秒，请核对版本',
                    ].join('\n'),
                    style: TextStyle(
                      color: mismatch ? const Color(0xFFFFB86B) : null,
                    ),
                  ),
                  onTap: enabled ? () => c.choose(candidate) : null,
                ),
              );
            },
          ),
        ),
      ],
    ];
  }

  Future<void> _showOptions() async {
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
                      '歌词选项',
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
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
    _refreshSheet = null;
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
              onPressed: _showOptions,
              icon: const Icon(Icons.add, color: Colors.white),
              label: const Text(
                '搜索或导入歌词',
                style: TextStyle(color: Colors.white),
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
                : '暂无歌词\n可搜索下载，或导入本地 .lrc / .txt 文件。',
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
            '同意搜索后，LRCLIB（lrclib.net）将收到下方填写的歌名、歌手和可选专辑名，也会看到你的 IP 地址。不发送音频、文件路径或歌曲时长。\n\n选中的歌词仅缓存到本机；歌词版权归原权利人，请仅在获准使用时下载；内容和时间轴可能不准确。每次搜索均需确认。取消或返回不会发送请求。',
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
            decoration: const InputDecoration(labelText: '歌手（必填，可编辑）'),
          ),
          const SizedBox(height: 12),
          TextField(
            key: const Key('lyrics-query-album'),
            controller: _album,
            decoration: const InputDecoration(labelText: '专辑（可选）'),
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
        onPressed: _title.text.trim().isEmpty || _artist.text.trim().isEmpty
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
