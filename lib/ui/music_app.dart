import 'dart:typed_data';

import 'package:flutter/material.dart' hide RepeatMode;

import '../models.dart';
import '../music_controller.dart';

const _ink = Color(0xFF111B2E);
const _muted = Color(0xFF9FAABD);
const _accent = Color(0xFFFFB86B);

class MusicApp extends StatelessWidget {
  const MusicApp({super.key, required this.controller});
  final MusicController controller;

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: '云听 · Cloud Music',
    debugShowCheckedModeBanner: false,
    theme: ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      scaffoldBackgroundColor: const Color(0xFF0B1220),
      colorScheme: ColorScheme.fromSeed(
        seedColor: _accent,
        brightness: Brightness.dark,
        primary: _accent,
        surface: _ink,
      ),
      fontFamilyFallback: const [
        'PingFang SC',
        'Microsoft YaHei',
        'sans-serif',
      ],
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      dividerColor: const Color(0xFF263247),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: _ink,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide.none,
        ),
      ),
      sliderTheme: const SliderThemeData(trackHeight: 3),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(minimumSize: const Size(52, 52)),
      ),
    ),
    home: _LibraryPage(controller: controller),
  );
}

class _LibraryPage extends StatefulWidget {
  const _LibraryPage({required this.controller});
  final MusicController controller;
  @override
  State<_LibraryPage> createState() => _LibraryPageState();
}

class _LibraryPageState extends State<_LibraryPage> {
  final _search = TextEditingController();
  String _query = '';
  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  void _openPlayer() => Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => _PlayerPage(controller: widget.controller),
    ),
  );

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: widget.controller,
    builder: (context, _) {
      final c = widget.controller;
      final s = c.snapshot;
      final tracks = s.tracks
          .where(
            (t) => '${t.title} ${t.artist} ${t.album} ${t.relativePath}'
                .toLowerCase()
                .contains(_query.toLowerCase()),
          )
          .toList();
      return Scaffold(
        body: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final wide = constraints.maxWidth >= 980;
              final short = constraints.maxHeight < 500;
              return Column(
                children: [
                  Padding(
                    padding: EdgeInsets.fromLTRB(
                      24,
                      short ? 2 : 16,
                      16,
                      short ? 2 : 12,
                    ),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: _accent,
                            borderRadius: BorderRadius.circular(13),
                          ),
                          child: const Icon(
                            Icons.graphic_eq_rounded,
                            color: _ink,
                          ),
                        ),
                        const SizedBox(width: 12),
                        const Expanded(
                          child: Text(
                            '云听',
                            style: TextStyle(
                              fontSize: 25,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 2,
                            ),
                          ),
                        ),
                        if (constraints.maxWidth >= 520)
                          const Text(
                            'YOUR MUSIC. YOUR SPACE.',
                            style: TextStyle(
                              color: _muted,
                              fontSize: 11,
                              letterSpacing: 2,
                            ),
                          ),
                        IconButton(
                          tooltip: '选择或更换音乐文件夹',
                          onPressed: c.isBusy ? null : c.pickFolder,
                          icon: const Icon(Icons.create_new_folder_outlined),
                        ),
                      ],
                    ),
                  ),
                  if (c.error != null)
                    _Notice(text: c.error!, error: true, onClose: c.clearError),
                  if (s.isLoading)
                    _Notice(
                      text: s.message ?? '正在准备音频，云端文件可能需要下载…',
                      onClose: c.cancelLoading,
                      closeLabel: '取消加载',
                    ),
                  if (!s.isLoading && s.message != null)
                    _Notice(text: s.message!),
                  Expanded(
                    child: Row(
                      children: [
                        Expanded(
                          child: CustomScrollView(
                            slivers: [
                              SliverToBoxAdapter(
                                child: Padding(
                                  padding: EdgeInsets.fromLTRB(
                                    24,
                                    short ? 4 : 20,
                                    24,
                                    short ? 8 : 16,
                                  ),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        '音乐资料库',
                                        style: TextStyle(
                                          fontSize: short ? 20 : 30,
                                          fontWeight: FontWeight.w700,
                                          letterSpacing: -1,
                                        ),
                                      ),
                                      SizedBox(height: short ? 2 : 8),
                                      Text(
                                        s.folderName == null
                                            ? '从你的文件夹开始，让音乐回到身边。'
                                            : '${s.folderName} · ${s.tracks.length} 首歌曲',
                                        style: const TextStyle(color: _muted),
                                      ),
                                      SizedBox(height: short ? 8 : 20),
                                      Row(
                                        children: [
                                          Expanded(
                                            child: TextField(
                                              controller: _search,
                                              onChanged: (value) => setState(
                                                () => _query = value,
                                              ),
                                              decoration: InputDecoration(
                                                hintText: '搜索歌曲、歌手或专辑',
                                                prefixIcon: const Icon(
                                                  Icons.search_rounded,
                                                ),
                                                suffixIcon: _query.isEmpty
                                                    ? null
                                                    : IconButton(
                                                        tooltip: '清除搜索',
                                                        onPressed: () {
                                                          _search.clear();
                                                          setState(
                                                            () => _query = '',
                                                          );
                                                        },
                                                        icon: const Icon(
                                                          Icons.close,
                                                        ),
                                                      ),
                                              ),
                                            ),
                                          ),
                                          const SizedBox(width: 8),
                                          IconButton(
                                            tooltip: '刷新资料库',
                                            onPressed:
                                                s.folderName == null || c.isBusy
                                                ? null
                                                : c.refresh,
                                            icon: const Icon(
                                              Icons.refresh_rounded,
                                            ),
                                          ),
                                        ],
                                      ),
                                      if (s.isScanning)
                                        const Padding(
                                          padding: EdgeInsets.only(top: 16),
                                          child: LinearProgressIndicator(),
                                        ),
                                    ],
                                  ),
                                ),
                              ),
                              if (!c.initialized)
                                const SliverFillRemaining(
                                  hasScrollBody: false,
                                  child: Center(
                                    child: CircularProgressIndicator(),
                                  ),
                                )
                              else if (s.tracks.isEmpty)
                                SliverFillRemaining(
                                  hasScrollBody: false,
                                  child: _EmptyLibrary(
                                    hasFolder: s.folderName != null,
                                    busy: c.isBusy,
                                    onPick: c.pickFolder,
                                    onRefresh: c.refresh,
                                  ),
                                )
                              else if (tracks.isEmpty)
                                const SliverFillRemaining(
                                  hasScrollBody: false,
                                  child: Center(
                                    child: Text(
                                      '没有找到匹配的歌曲',
                                      style: TextStyle(color: _muted),
                                    ),
                                  ),
                                )
                              else
                                SliverPadding(
                                  padding: const EdgeInsets.fromLTRB(
                                    12,
                                    0,
                                    12,
                                    24,
                                  ),
                                  sliver: SliverList.builder(
                                    itemCount: tracks.length,
                                    itemBuilder: (context, i) {
                                      final track = tracks[i];
                                      return _TrackRow(
                                        track: track,
                                        selected: track.id == s.currentTrackId,
                                        playing: s.isPlaying,
                                        onTap: () => c.play(track),
                                      );
                                    },
                                  ),
                                ),
                            ],
                          ),
                        ),
                        if (wide)
                          Container(
                            width: 340,
                            margin: const EdgeInsets.fromLTRB(8, 20, 24, 24),
                            padding: const EdgeInsets.all(24),
                            decoration: BoxDecoration(
                              color: _ink,
                              borderRadius: BorderRadius.circular(28),
                            ),
                            child: SingleChildScrollView(
                              child: Column(
                                children: [
                                  const Row(
                                    children: [
                                      Icon(
                                        Icons.album_outlined,
                                        size: 18,
                                        color: _muted,
                                      ),
                                      SizedBox(width: 8),
                                      Text(
                                        '正在播放',
                                        style: TextStyle(color: _muted),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 28),
                                  _PlayerContents(
                                    controller: c,
                                    artworkSize: 240,
                                    compact: true,
                                  ),
                                ],
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                  _MiniPlayer(controller: c, onOpen: _openPlayer),
                ],
              );
            },
          ),
        ),
      );
    },
  );
}

class _EmptyLibrary extends StatelessWidget {
  const _EmptyLibrary({
    required this.hasFolder,
    required this.busy,
    required this.onPick,
    required this.onRefresh,
  });
  final bool hasFolder, busy;
  final VoidCallback onPick, onRefresh;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(28),
    child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const _Artwork(size: 112),
        const SizedBox(height: 24),
        Text(
          hasFolder ? '这里还没有音乐' : '你的音乐，不必搬家',
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 12),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 390),
          child: Text(
            hasFolder
                ? '将音频放进所选文件夹后刷新，或选择另一个文件夹。'
                : '选择 iCloud Drive 或设备上的音乐文件夹。\n直接聆听原文件，无需重新导入资料库。',
            textAlign: TextAlign.center,
            style: const TextStyle(color: _muted, height: 1.7),
          ),
        ),
        const SizedBox(height: 28),
        FilledButton.icon(
          onPressed: busy ? null : onPick,
          icon: const Icon(Icons.folder_open_rounded),
          label: Text(hasFolder ? '更换音乐文件夹' : '选择音乐文件夹'),
          style: FilledButton.styleFrom(minimumSize: const Size(220, 56)),
        ),
        if (hasFolder)
          TextButton.icon(
            onPressed: busy ? null : onRefresh,
            icon: const Icon(Icons.refresh),
            label: const Text('刷新资料库'),
          ),
        const SizedBox(height: 18),
        const Text(
          '云端文件播放前需要联网下载',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 12, color: _muted),
        ),
      ],
    ),
  );
}

class _TrackRow extends StatelessWidget {
  const _TrackRow({
    required this.track,
    required this.selected,
    required this.playing,
    required this.onTap,
  });
  final Track track;
  final bool selected, playing;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    final status = switch (track.availability) {
      TrackAvailability.ready => ('设备可用', Icons.check_circle_outline),
      TrackAvailability.cloud => ('云端 · 需下载', Icons.cloud_download_outlined),
      TrackAvailability.offline => ('离线不可用', Icons.cloud_off_outlined),
      TrackAvailability.missing => ('文件已移走', Icons.folder_off_outlined),
      TrackAvailability.unsupported => ('格式不支持', Icons.block_outlined),
      TrackAvailability.unknown => ('待检查', Icons.help_outline),
    };
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Material(
        color: selected ? const Color(0xFF263044) : Colors.transparent,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            child: Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: selected ? _accent : _ink,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    selected && playing
                        ? Icons.graphic_eq
                        : Icons.music_note_rounded,
                    color: selected ? _ink : _muted,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        track.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          color: selected ? _accent : Colors.white,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        track.artist.isEmpty ? '未知歌手' : track.artist,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: _muted, fontSize: 12),
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Icon(status.$2, size: 13, color: _muted),
                          const SizedBox(width: 4),
                          Flexible(
                            child: Text(
                              status.$1,
                              style: const TextStyle(
                                color: _muted,
                                fontSize: 11,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  track.duration > Duration.zero ? _time(track.duration) : '—',
                  style: const TextStyle(color: _muted, fontSize: 12),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _MiniPlayer extends StatelessWidget {
  const _MiniPlayer({required this.controller, required this.onOpen});
  final MusicController controller;
  final VoidCallback onOpen;
  @override
  Widget build(BuildContext context) {
    final s = controller.snapshot;
    return Material(
      color: _ink,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          LinearProgressIndicator(
            minHeight: 2,
            value: _fraction(s.position, s.duration),
            backgroundColor: const Color(0xFF263247),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
            child: Row(
              children: [
                Expanded(
                  child: InkWell(
                    onTap: onOpen,
                    borderRadius: BorderRadius.circular(12),
                    child: Padding(
                      padding: const EdgeInsets.all(4),
                      child: Row(
                        children: [
                          _Artwork(size: 46, bytes: s.artwork),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  s.currentTrack?.title ?? '准备好，听一首',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                Text(
                                  s.currentTrack?.artist ?? '选择歌曲开始播放',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontSize: 12,
                                    color: _muted,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                IconButton(
                  tooltip: s.isPlaying ? '暂停' : '播放',
                  onPressed: s.currentTrack == null
                      ? null
                      : controller.togglePlayback,
                  icon: Icon(
                    s.isPlaying
                        ? Icons.pause_rounded
                        : Icons.play_arrow_rounded,
                    size: 32,
                  ),
                ),
                IconButton(
                  tooltip: '下一首',
                  onPressed: s.currentTrack == null ? null : controller.next,
                  icon: const Icon(Icons.skip_next_rounded),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PlayerPage extends StatelessWidget {
  const _PlayerPage({required this.controller});
  final MusicController controller;
  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: controller,
    builder: (context, _) => Scaffold(
      appBar: AppBar(
        leading: IconButton(
          tooltip: '返回资料库',
          onPressed: () => Navigator.pop(context),
          icon: const Icon(Icons.keyboard_arrow_down_rounded),
        ),
        title: const Text('正在播放', style: TextStyle(fontSize: 16)),
        centerTitle: true,
      ),
      body: SafeArea(
        child: Column(
          children: [
            if (controller.snapshot.message != null)
              _Notice(
                text: controller.snapshot.message!,
                onClose: controller.snapshot.isLoading
                    ? controller.cancelLoading
                    : null,
                closeLabel: '取消加载',
              ),
            Expanded(
              child: LayoutBuilder(
                builder: (context, size) => Center(
                  child: SingleChildScrollView(
                    padding: EdgeInsets.all(
                      size.maxWidth >= 720 && size.maxHeight < 650 ? 12 : 24,
                    ),
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 960),
                      child: _PlayerContents(
                        controller: controller,
                        artworkSize: size.maxWidth < 600
                            ? (size.maxWidth - 80).clamp(140.0, 330.0)
                            : (size.maxHeight - 32).clamp(140.0, 320.0),
                        horizontal:
                            size.maxWidth >= 720 && size.maxHeight < 650,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class _PlayerContents extends StatelessWidget {
  const _PlayerContents({
    required this.controller,
    required this.artworkSize,
    this.compact = false,
    this.horizontal = false,
  });
  final MusicController controller;
  final double artworkSize;
  final bool compact, horizontal;
  @override
  Widget build(BuildContext context) {
    final s = controller.snapshot;
    final enabled = s.currentTrack != null;
    final details = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          s.currentTrack?.title ?? '此刻，留给音乐',
          textAlign: TextAlign.center,
          maxLines: horizontal ? 1 : 3,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: compact || horizontal ? 23 : 28,
            fontWeight: FontWeight.w700,
          ),
        ),
        SizedBox(height: horizontal ? 2 : 8),
        Text(
          s.currentTrack?.artist ?? '从资料库选择一首歌',
          textAlign: TextAlign.center,
          style: const TextStyle(color: _muted),
        ),
        if (!horizontal && (s.currentTrack?.album.isNotEmpty ?? false))
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              s.currentTrack!.album,
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12, color: _muted),
            ),
          ),
        SizedBox(height: horizontal ? 4 : 24),
        _SeekBar(
          position: s.position,
          duration: s.duration,
          onSeek: enabled && !s.isLoading ? controller.seek : null,
        ),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              _time(s.position),
              style: const TextStyle(color: _muted, fontSize: 12),
            ),
            Text(
              _time(s.duration),
              style: const TextStyle(color: _muted, fontSize: 12),
            ),
          ],
        ),
        SizedBox(height: horizontal ? 4 : 16),
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              IconButton(
                tooltip: s.shuffle ? '关闭随机播放' : '随机播放',
                onPressed: () => controller.setShuffle(!s.shuffle),
                color: s.shuffle ? _accent : _muted,
                icon: const Icon(Icons.shuffle_rounded),
              ),
              IconButton(
                tooltip: '上一首',
                onPressed: enabled ? controller.previous : null,
                icon: const Icon(Icons.skip_previous_rounded, size: 36),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 72,
                height: 72,
                child: FilledButton(
                  style: FilledButton.styleFrom(
                    padding: EdgeInsets.zero,
                    shape: const CircleBorder(),
                  ),
                  onPressed: enabled ? controller.togglePlayback : null,
                  child: Icon(
                    s.isPlaying
                        ? Icons.pause_rounded
                        : Icons.play_arrow_rounded,
                    size: 38,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                tooltip: '下一首',
                onPressed: enabled ? controller.next : null,
                icon: const Icon(Icons.skip_next_rounded, size: 36),
              ),
              IconButton(
                tooltip: switch (s.repeatMode) {
                  RepeatMode.off => '顺序播放，点击切换列表循环',
                  RepeatMode.all => '列表循环，点击切换单曲循环',
                  RepeatMode.one => '单曲循环，点击关闭循环',
                },
                onPressed: () => controller.setRepeat(
                  RepeatMode.values[(s.repeatMode.index + 1) %
                      RepeatMode.values.length],
                ),
                color: s.repeatMode == RepeatMode.off ? _muted : _accent,
                icon: Icon(
                  s.repeatMode == RepeatMode.one
                      ? Icons.repeat_one_rounded
                      : Icons.repeat_rounded,
                ),
              ),
            ],
          ),
        ),
        SizedBox(height: horizontal ? 4 : 24),
        Row(
          children: [
            const Icon(Icons.volume_down_rounded, color: _muted, size: 20),
            Expanded(
              child: Slider(
                value: s.volume.clamp(0, 1),
                onChanged: controller.setVolume,
                semanticFormatterCallback: (v) => '音量 ${(v * 100).round()}%',
              ),
            ),
            const Icon(Icons.volume_up_rounded, color: _muted, size: 20),
          ],
        ),
        if (s.isLoading)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Column(
              children: [
                const LinearProgressIndicator(),
                TextButton(
                  onPressed: controller.cancelLoading,
                  child: const Text('取消加载'),
                ),
              ],
            ),
          ),
        if (controller.error != null)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Text(
              controller.error!,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Color(0xFFFFACA6)),
            ),
          ),
      ],
    );
    final artwork = _Artwork(size: artworkSize, bytes: s.artwork);
    if (horizontal) {
      return Row(
        children: [
          Expanded(child: Center(child: artwork)),
          const SizedBox(width: 40),
          Expanded(child: details),
        ],
      );
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        artwork,
        const SizedBox(height: 32),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 440),
          child: details,
        ),
      ],
    );
  }
}

class _SeekBar extends StatefulWidget {
  const _SeekBar({
    required this.position,
    required this.duration,
    required this.onSeek,
  });
  final Duration position, duration;
  final ValueChanged<Duration>? onSeek;
  @override
  State<_SeekBar> createState() => _SeekBarState();
}

class _SeekBarState extends State<_SeekBar> {
  double? _drag;
  @override
  Widget build(BuildContext context) => Slider(
    value: _drag ?? _fraction(widget.position, widget.duration),
    onChanged: widget.onSeek == null || widget.duration <= Duration.zero
        ? null
        : (v) => setState(() => _drag = v),
    onChangeEnd: (v) {
      widget.onSeek?.call(
        Duration(milliseconds: (widget.duration.inMilliseconds * v).round()),
      );
      setState(() => _drag = null);
    },
    semanticFormatterCallback: (v) => _time(
      Duration(milliseconds: (widget.duration.inMilliseconds * v).round()),
    ),
  );
}

class _Artwork extends StatelessWidget {
  const _Artwork({required this.size, this.bytes});
  final double size;
  final Uint8List? bytes;
  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    clipBehavior: Clip.antiAlias,
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(size * .09),
      gradient: const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0xFF3E526D), Color(0xFF1B2943), Color(0xFF76574C)],
      ),
    ),
    child: bytes == null
        ? _fallback()
        : Image.memory(
            bytes!,
            fit: BoxFit.cover,
            gaplessPlayback: true,
            errorBuilder: (_, error, stack) => _fallback(),
          ),
  );
  Widget _fallback() => Center(
    child: Container(
      width: size * .65,
      height: size * .65,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(
          color: Colors.white.withValues(alpha: .12),
          width: size * .07,
        ),
      ),
      child: Icon(Icons.graphic_eq_rounded, size: size * .32, color: _accent),
    ),
  );
}

class _Notice extends StatelessWidget {
  const _Notice({
    required this.text,
    this.error = false,
    this.onClose,
    this.closeLabel = '关闭提示',
  });
  final String text, closeLabel;
  final bool error;
  final VoidCallback? onClose;
  @override
  Widget build(BuildContext context) => Container(
    color: error ? const Color(0xFF492C30) : const Color(0xFF243348),
    padding: const EdgeInsets.only(left: 20, right: 8),
    child: Row(
      children: [
        Icon(error ? Icons.info_outline : Icons.cloud_outlined, size: 20),
        const SizedBox(width: 12),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Text(
              text,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 13),
            ),
          ),
        ),
        if (onClose != null)
          IconButton(
            tooltip: closeLabel,
            onPressed: onClose,
            icon: const Icon(Icons.close, size: 20),
          ),
      ],
    ),
  );
}

double _fraction(Duration position, Duration duration) =>
    duration.inMilliseconds <= 0
    ? 0
    : (position.inMilliseconds / duration.inMilliseconds).clamp(0.0, 1.0);
String _time(Duration time) {
  final seconds = time.inSeconds.clamp(0, 999999);
  return '${seconds ~/ 60}:${(seconds % 60).toString().padLeft(2, '0')}';
}
