import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/cupertino.dart' hide RepeatMode;
import 'package:flutter/material.dart' hide RepeatMode;

import '../models.dart';
import '../music_controller.dart';
import 'lyrics_panel.dart';
import 'music_sources_sheet.dart';
import '../updates/update_controller.dart';
import 'update_panel.dart';

const _accent = Color(0xFFE83E59);
const _ink = Color(0xFF202024);
const _muted = Color(0xFF78787F);
const _canvas = Color(0xFFF9F9FB);
const _line = Color(0xFFE8E8ED);
const _playerMuted = Color(0xFFCDC3C5);

class MusicApp extends StatelessWidget {
  const MusicApp({super.key, required this.controller, this.updates});
  final MusicController controller;
  final UpdateController? updates;

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: '云听 · Cloud Music',
    debugShowCheckedModeBanner: false,
    theme: ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      scaffoldBackgroundColor: Colors.white,
      colorScheme: ColorScheme.fromSeed(
        seedColor: _accent,
        primary: _accent,
        surface: Colors.white,
      ),
      fontFamilyFallback: const [
        'PingFang SC',
        'Microsoft YaHei',
        'sans-serif',
      ],
      textTheme: ThemeData.light().textTheme.apply(
        bodyColor: _ink,
        displayColor: _ink,
      ),
      dividerColor: _line,
      splashFactory: NoSplash.splashFactory,
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: const Color(0xFFF0F0F3),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 12,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
      ),
      sliderTheme: const SliderThemeData(trackHeight: 4),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(minimumSize: const Size(48, 48)),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(48, 48),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
    ),
    home: _LibraryPage(controller: controller, updates: updates),
  );
}

enum _LibrarySection { songs, albums, artists, search }

class _LibraryPage extends StatefulWidget {
  const _LibraryPage({required this.controller, this.updates});
  final MusicController controller;
  final UpdateController? updates;
  @override
  State<_LibraryPage> createState() => _LibraryPageState();
}

class _LibraryPageState extends State<_LibraryPage> {
  final _search = TextEditingController();
  final _searchFocus = FocusNode();
  String _query = '';
  _LibrarySection _section = _LibrarySection.songs;
  String? _group;
  bool _openingPlayer = false;

  @override
  void dispose() {
    _search.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  Future<void> _openPlayer() async {
    if (_openingPlayer) return;
    _openingPlayer = true;
    _searchFocus.unfocus();
    await Navigator.of(context).push(
      PageRouteBuilder<void>(
        pageBuilder: (_, animation, secondaryAnimation) =>
            _PlayerPage(controller: widget.controller),
        transitionDuration: const Duration(milliseconds: 360),
        reverseTransitionDuration: const Duration(milliseconds: 280),
        transitionsBuilder: (_, animation, secondaryAnimation, child) =>
            SlideTransition(
              position: Tween(begin: const Offset(0, 1), end: Offset.zero)
                  .animate(
                    CurvedAnimation(
                      parent: animation,
                      curve: Curves.easeOutCubic,
                      reverseCurve: Curves.easeInCubic,
                    ),
                  ),
              child: child,
            ),
      ),
    );
    _openingPlayer = false;
  }

  void _select(_LibrarySection section) {
    setState(() {
      _section = section;
      _group = null;
      if (section != _LibrarySection.search) {
        _query = '';
        _search.clear();
      }
    });
    if (section == _LibrarySection.search) {
      _searchFocus.requestFocus();
    } else {
      _searchFocus.unfocus();
    }
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: widget.controller,
    builder: (context, _) {
      final c = widget.controller;
      final s = c.snapshot;
      final tracks = s.tracks.where((t) {
        final matches = '${t.title} ${t.artist} ${t.album} ${t.relativePath}'
            .toLowerCase()
            .contains(_query.toLowerCase());
        return matches &&
            (_group == null ||
                (_section == _LibrarySection.albums ? _album(t) : _artist(t)) ==
                    _group);
      }).toList();
      return Scaffold(
        body: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final wide = constraints.maxWidth >= 750;
              final short = constraints.maxHeight < 500;
              return Row(
                children: [
                  if (wide) _sidebar(s, short),
                  Expanded(
                    child: Column(
                      children: [
                        if (widget.updates != null)
                          UpdateBanner(controller: widget.updates!),
                        if (c.error != null)
                          _Notice(
                            text: c.error!,
                            error: true,
                            onClose: c.clearError,
                          ),
                        if (s.isLoading)
                          _Notice(
                            text: s.message ?? '正在准备音频，云端文件可能需要下载…',
                            onClose: c.cancelLoading,
                            closeLabel: '取消加载',
                          ),
                        if (!s.isLoading && s.message != null)
                          _Notice(text: s.message!),
                        Expanded(
                          child: CustomScrollView(
                            key: const Key('library-scroll'),
                            slivers: [
                              SliverToBoxAdapter(
                                child: Padding(
                                  padding: EdgeInsets.fromLTRB(
                                    wide ? 40 : 22,
                                    short ? 12 : 28,
                                    wide ? 32 : 14,
                                    8,
                                  ),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      if (!short)
                                        const Text(
                                          '云听',
                                          style: TextStyle(
                                            color: _accent,
                                            fontWeight: FontWeight.w600,
                                            fontSize: 14,
                                            letterSpacing: 2,
                                          ),
                                        ),
                                      Row(
                                        children: [
                                          Expanded(
                                            child: Text(
                                              _section == _LibrarySection.search
                                                  ? '搜索'
                                                  : '音乐资料库',
                                              style: TextStyle(
                                                fontSize: short ? 27 : 34,
                                                fontWeight: FontWeight.w800,
                                                letterSpacing: -1.4,
                                              ),
                                            ),
                                          ),
                                          IconButton(
                                            tooltip: s.selectsFiles
                                                ? '选择或更换音乐文件'
                                                : '选择或更换音乐文件夹',
                                            onPressed: c.isBusy
                                                ? null
                                                : c.pickFolder,
                                            color: _accent,
                                            icon: const Icon(
                                              CupertinoIcons.add_circled,
                                              size: 27,
                                            ),
                                          ),
                                          IconButton(
                                            tooltip: s.selectsFiles
                                                ? '重新选择音乐文件'
                                                : '刷新资料库',
                                            onPressed:
                                                s.folderName == null || c.isBusy
                                                ? null
                                                : c.refresh,
                                            color: _accent,
                                            icon: const Icon(
                                              CupertinoIcons.arrow_clockwise,
                                              size: 23,
                                            ),
                                          ),
                                        ],
                                      ),
                                      if (!short)
                                        Padding(
                                          padding: const EdgeInsets.only(
                                            top: 2,
                                            bottom: 20,
                                          ),
                                          child: Text(
                                            s.folderName == null
                                                ? '好音乐，就在你身边。'
                                                : '${s.folderName} · ${s.tracks.length} 首歌曲',
                                            maxLines: 2,
                                            overflow: TextOverflow.ellipsis,
                                            style: const TextStyle(
                                              color: _muted,
                                              fontSize: 14,
                                            ),
                                          ),
                                        ),
                                      Align(
                                        alignment: Alignment.centerLeft,
                                        child: TextButton.icon(
                                          key: const Key('music-sources'),
                                          onPressed: () =>
                                              showMusicSources(context, c),
                                          icon: Icon(
                                            s.sourceKind == 'googleDrive'
                                                ? Icons.cloud_outlined
                                                : Icons.folder_outlined,
                                            size: 18,
                                          ),
                                          label: Text(
                                            s.sourceKind == 'googleDrive'
                                                ? 'Google Drive · 管理音乐来源'
                                                : '系统文件 · 添加网盘来源',
                                          ),
                                        ),
                                      ),
                                      if (widget.updates != null)
                                        Align(
                                          alignment: Alignment.centerLeft,
                                          child: TextButton.icon(
                                            key: const Key('app-updates'),
                                            onPressed: () => showAppUpdates(
                                              context,
                                              widget.updates!,
                                            ),
                                            icon: const Icon(
                                              Icons.system_update_alt,
                                              size: 18,
                                            ),
                                            label: const Text('应用更新'),
                                          ),
                                        ),
                                      if (s.sourceKind == 'web' ||
                                          s.sourceKind == 'apple')
                                        Padding(
                                          padding: const EdgeInsets.only(
                                            bottom: 12,
                                          ),
                                          child: Text(
                                            s.sourceKind == 'web'
                                                ? '本页只在播放时读取音频。网页无法判断 iCloud 下载状态；系统可能在选择文件时先下载。'
                                                : '先显示文件名和下载状态，点歌才下载。首次列表取决于系统已同步的目录信息。',
                                            key: const Key(
                                              'source-loading-help',
                                            ),
                                            style: const TextStyle(
                                              color: _muted,
                                              fontSize: 12,
                                              height: 1.5,
                                            ),
                                          ),
                                        ),
                                      TextField(
                                        key: const Key('library-search'),
                                        controller: _search,
                                        focusNode: _searchFocus,
                                        onChanged: (value) => setState(() {
                                          _query = value;
                                          _group = null;
                                        }),
                                        decoration: InputDecoration(
                                          hintText: '搜索歌曲、歌手或专辑',
                                          prefixIcon: const Icon(
                                            CupertinoIcons.search,
                                            size: 21,
                                          ),
                                          suffixIcon: _query.isEmpty
                                              ? null
                                              : IconButton(
                                                  tooltip: '清除搜索',
                                                  onPressed: () {
                                                    _search.clear();
                                                    setState(() => _query = '');
                                                  },
                                                  icon: const Icon(
                                                    CupertinoIcons
                                                        .clear_circled_solid,
                                                    size: 19,
                                                  ),
                                                ),
                                        ),
                                      ),
                                      if (!wide &&
                                          _section != _LibrarySection.search)
                                        Padding(
                                          padding: const EdgeInsets.only(
                                            top: 14,
                                          ),
                                          child: Row(
                                            children: [
                                              for (final section in [
                                                _LibrarySection.songs,
                                                _LibrarySection.albums,
                                                _LibrarySection.artists,
                                              ])
                                                Expanded(
                                                  child: _CategoryButton(
                                                    label: _label(section),
                                                    selected:
                                                        _section == section,
                                                    onTap: () =>
                                                        _select(section),
                                                  ),
                                                ),
                                            ],
                                          ),
                                        ),
                                      if (s.isScanning)
                                        Padding(
                                          padding: const EdgeInsets.only(
                                            top: 12,
                                          ),
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              const LinearProgressIndicator(),
                                              const SizedBox(height: 6),
                                              Text(
                                                '正在列出歌曲 · 已显示 ${s.tracks.length} 首',
                                                style: const TextStyle(
                                                  color: _muted,
                                                  fontSize: 12,
                                                ),
                                              ),
                                            ],
                                          ),
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
                                    scanning: s.isScanning,
                                    filesOnly: s.selectsFiles,
                                    busy: c.isBusy,
                                    onPick: c.pickFolder,
                                    onRefresh: c.refresh,
                                  ),
                                )
                              else ...[
                                SliverToBoxAdapter(
                                  child: Padding(
                                    padding: EdgeInsets.fromLTRB(
                                      wide ? 40 : 22,
                                      14,
                                      wide ? 40 : 22,
                                      12,
                                    ),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.stretch,
                                      children: [
                                        if (_group != null)
                                          Align(
                                            alignment: Alignment.centerLeft,
                                            child: TextButton.icon(
                                              onPressed: () =>
                                                  setState(() => _group = null),
                                              icon: const Icon(
                                                CupertinoIcons.chevron_back,
                                                size: 15,
                                              ),
                                              label: Text(_label(_section)),
                                            ),
                                          ),
                                        Row(
                                          children: [
                                            Expanded(
                                              child: Text(
                                                _group ??
                                                    (_section ==
                                                            _LibrarySection
                                                                .search
                                                        ? '搜索结果'
                                                        : _label(_section)),
                                                style: const TextStyle(
                                                  fontSize: 22,
                                                  fontWeight: FontWeight.w700,
                                                ),
                                              ),
                                            ),
                                            Text(
                                              '${tracks.length} 首',
                                              style: const TextStyle(
                                                color: _muted,
                                                fontSize: 13,
                                              ),
                                            ),
                                          ],
                                        ),
                                        if (tracks.isNotEmpty &&
                                            (_section ==
                                                    _LibrarySection.songs ||
                                                _group != null)) ...[
                                          const SizedBox(height: 14),
                                          Row(
                                            children: [
                                              Expanded(
                                                child: _LibraryPlayButton(
                                                  icon:
                                                      CupertinoIcons.play_fill,
                                                  label: '播放',
                                                  onPressed: () async {
                                                    await c.setShuffle(false);
                                                    await c.play(tracks.first);
                                                  },
                                                ),
                                              ),
                                              const SizedBox(width: 12),
                                              Expanded(
                                                child: _LibraryPlayButton(
                                                  icon: CupertinoIcons.shuffle,
                                                  label: '随机播放',
                                                  onPressed: () async {
                                                    await c.setShuffle(true);
                                                    await c.play(
                                                      tracks[math.Random()
                                                          .nextInt(
                                                            tracks.length,
                                                          )],
                                                    );
                                                  },
                                                ),
                                              ),
                                            ],
                                          ),
                                        ],
                                      ],
                                    ),
                                  ),
                                ),
                                if (tracks.isEmpty)
                                  const SliverFillRemaining(
                                    hasScrollBody: false,
                                    child: Center(
                                      child: Text(
                                        '没有找到匹配的歌曲',
                                        style: TextStyle(color: _muted),
                                      ),
                                    ),
                                  )
                                else if ((_section == _LibrarySection.albums ||
                                        _section == _LibrarySection.artists) &&
                                    _group == null)
                                  _groups(tracks, wide)
                                else
                                  SliverPadding(
                                    padding: EdgeInsets.fromLTRB(
                                      wide ? 28 : 10,
                                      0,
                                      wide ? 28 : 10,
                                      24,
                                    ),
                                    sliver: SliverList.builder(
                                      itemCount: tracks.length,
                                      itemBuilder: (context, i) => _TrackRow(
                                        track: tracks[i],
                                        selected:
                                            tracks[i].id == s.currentTrackId,
                                        playing: s.isPlaying,
                                        onTap: () => c.play(tracks[i]),
                                      ),
                                    ),
                                  ),
                              ],
                            ],
                          ),
                        ),
                        _MiniPlayer(controller: c, onOpen: _openPlayer),
                        if (!wide) _bottomNavigation(short),
                      ],
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      );
    },
  );

  Widget _sidebar(LibrarySnapshot s, bool short) => Container(
    width: short ? 180 : 224,
    decoration: const BoxDecoration(
      color: _canvas,
      border: Border(right: BorderSide(color: _line)),
    ),
    padding: EdgeInsets.fromLTRB(20, short ? 14 : 32, 20, short ? 8 : 24),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Row(
          children: [
            Icon(CupertinoIcons.music_note_2, color: _accent, size: 30),
            SizedBox(width: 10),
            Text(
              '云听',
              style: TextStyle(
                fontSize: 25,
                fontWeight: FontWeight.w800,
                letterSpacing: -1,
              ),
            ),
          ],
        ),
        SizedBox(height: short ? 16 : 40),
        if (!short)
          const Padding(
            padding: EdgeInsets.only(left: 12, bottom: 12),
            child: Text(
              '资料库',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: _muted,
              ),
            ),
          ),
        for (final section in _LibrarySection.values)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Material(
              color: _section == section
                  ? const Color(0xFFFCE8ED)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(10),
              child: ListTile(
                dense: true,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
                leading: Icon(_icon(section), color: _accent, size: 23),
                title: Text(
                  _label(section),
                  style: TextStyle(
                    color: _section == section ? _accent : _ink,
                    fontWeight: _section == section
                        ? FontWeight.w700
                        : FontWeight.w500,
                  ),
                ),
                onTap: () => _select(section),
              ),
            ),
          ),
        const Spacer(),
        if (!short) ...[
          const Divider(),
          const SizedBox(height: 16),
          const Icon(CupertinoIcons.folder, size: 22, color: _muted),
          const SizedBox(height: 10),
          Text(
            s.folderName ?? '属于你的音乐',
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
          ),
          const SizedBox(height: 6),
          const Text(
            '原文件播放 · 音频不上传',
            style: TextStyle(color: _muted, fontSize: 11, height: 1.6),
          ),
        ],
      ],
    ),
  );

  Widget _bottomNavigation(bool short) => Container(
    decoration: const BoxDecoration(
      color: _canvas,
      border: Border(top: BorderSide(color: _line)),
    ),
    child: Row(
      children: [
        Expanded(
          child: _NavButton(
            label: '资料库',
            icon: CupertinoIcons.music_albums,
            selected: _section != _LibrarySection.search,
            compact: short,
            onTap: () => _select(_LibrarySection.songs),
          ),
        ),
        Expanded(
          child: _NavButton(
            label: '搜索',
            icon: CupertinoIcons.search,
            selected: _section == _LibrarySection.search,
            compact: short,
            onTap: () => _select(_LibrarySection.search),
          ),
        ),
      ],
    ),
  );

  Widget _groups(List<Track> tracks, bool wide) {
    final groups = <String, List<Track>>{};
    for (final track in tracks) {
      groups
          .putIfAbsent(
            _section == _LibrarySection.albums ? _album(track) : _artist(track),
            () => [],
          )
          .add(track);
    }
    final names = groups.keys.toList()..sort();
    return SliverPadding(
      padding: EdgeInsets.fromLTRB(wide ? 40 : 22, 0, wide ? 40 : 22, 24),
      sliver: SliverGrid.builder(
        gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
          maxCrossAxisExtent: 230,
          mainAxisSpacing: 20,
          crossAxisSpacing: 18,
          mainAxisExtent: MediaQuery.textScalerOf(context).scale(36) + 178,
        ),
        itemCount: names.length,
        itemBuilder: (context, i) => InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () => setState(() => _group = names[i]),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Center(
                  child: AspectRatio(
                    aspectRatio: 1,
                    child: LayoutBuilder(
                      builder: (_, size) => _Artwork(
                        size: size.maxWidth,
                        seed: names[i],
                        round: _section == _LibrarySection.artists,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Text(
                names[i],
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              Text(
                '${groups[names[i]]!.length} 首歌曲',
                style: const TextStyle(color: _muted, fontSize: 12),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

String _album(Track t) => t.album.isEmpty ? '未知专辑' : t.album;
String _artist(Track t) => t.artist.isEmpty ? '未知歌手' : t.artist;
String _label(_LibrarySection s) => switch (s) {
  _LibrarySection.songs => '歌曲',
  _LibrarySection.albums => '专辑',
  _LibrarySection.artists => '歌手',
  _LibrarySection.search => '搜索',
};
IconData _icon(_LibrarySection s) => switch (s) {
  _LibrarySection.songs => CupertinoIcons.music_note_2,
  _LibrarySection.albums => CupertinoIcons.square_stack,
  _LibrarySection.artists => CupertinoIcons.person_2,
  _LibrarySection.search => CupertinoIcons.search,
};

class _NavButton extends StatelessWidget {
  const _NavButton({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
    this.compact = false,
  });
  final String label;
  final IconData icon;
  final bool selected, compact;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Semantics(
    selected: selected,
    label: compact ? label : null,
    child: TextButton(
      onPressed: onTap,
      style: TextButton.styleFrom(
        foregroundColor: selected ? _accent : _muted,
        minimumSize: Size(48, compact ? 48 : 62),
        shape: const RoundedRectangleBorder(),
      ),
      child: compact
          ? Icon(icon, size: 23)
          : Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 23),
                const SizedBox(height: 3),
                Text(label, style: const TextStyle(fontSize: 11)),
              ],
            ),
    ),
  );
}

class _CategoryButton extends StatelessWidget {
  const _CategoryButton({
    required this.label,
    required this.selected,
    required this.onTap,
  });
  final String label;
  final bool selected;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Semantics(
    selected: selected,
    child: TextButton(
      onPressed: onTap,
      style: TextButton.styleFrom(
        backgroundColor: selected
            ? const Color(0xFFFCE8ED)
            : Colors.transparent,
        foregroundColor: selected ? _accent : _muted,
        minimumSize: const Size(48, 44),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
      child: Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
    ),
  );
}

class _LibraryPlayButton extends StatelessWidget {
  const _LibraryPlayButton({
    required this.icon,
    required this.label,
    required this.onPressed,
  });
  final IconData icon;
  final String label;
  final VoidCallback onPressed;
  @override
  Widget build(BuildContext context) => TextButton.icon(
    onPressed: onPressed,
    icon: Icon(icon, size: 19),
    label: Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
    style: TextButton.styleFrom(
      backgroundColor: const Color(0xFFF1F1F4),
      minimumSize: const Size(48, 48),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(11)),
    ),
  );
}

class _EmptyLibrary extends StatelessWidget {
  const _EmptyLibrary({
    required this.hasFolder,
    this.scanning = false,
    required this.filesOnly,
    required this.busy,
    required this.onPick,
    required this.onRefresh,
  });
  final bool hasFolder, filesOnly, busy, scanning;
  final VoidCallback onPick, onRefresh;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 28),
    child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Container(
          width: 112,
          height: 112,
          decoration: BoxDecoration(
            color: const Color(0xFFFCE8ED),
            borderRadius: BorderRadius.circular(28),
          ),
          child: const Icon(
            CupertinoIcons.music_note_2,
            size: 56,
            color: _accent,
          ),
        ),
        const SizedBox(height: 24),
        Text(
          scanning
              ? '正在读取目录'
              : hasFolder
              ? '这里还没有音乐'
              : '你的音乐，不必搬家',
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.w700,
            letterSpacing: -.6,
          ),
        ),
        const SizedBox(height: 12),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 390),
          child: Text(
            scanning
                ? '目录信息就绪后会陆续显示歌曲，无需等待音频下载。'
                : filesOnly
                ? '在“文件”中打开音乐所在位置，可多选歌曲。\n刷新网页后需重新选择，音频不会上传。'
                : hasFolder
                ? '将音频放进所选文件夹后刷新，或选择另一个文件夹。'
                : '连接 iCloud Drive 或设备上的音乐文件夹。\n聆听原文件，把空间留给喜欢的音乐。',
            textAlign: TextAlign.center,
            style: const TextStyle(color: _muted, height: 1.7, fontSize: 14),
          ),
        ),
        const SizedBox(height: 24),
        FilledButton.icon(
          onPressed: busy ? null : onPick,
          icon: Icon(
            filesOnly ? CupertinoIcons.music_note : CupertinoIcons.folder,
            size: 20,
          ),
          label: Text(
            filesOnly
                ? '选择音乐文件（可多选）'
                : hasFolder
                ? '更换音乐文件夹'
                : '选择音乐文件夹',
          ),
          style: FilledButton.styleFrom(minimumSize: const Size(220, 52)),
        ),
        if (hasFolder)
          TextButton.icon(
            onPressed: busy ? null : onRefresh,
            icon: const Icon(CupertinoIcons.arrow_clockwise, size: 18),
            label: Text(filesOnly ? '重新选择音乐文件' : '刷新资料库'),
          ),
        const SizedBox(height: 16),
        const Text(
          '云端文件播放前需要联网下载',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 11, color: _muted),
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
    this.dark = false,
  });
  final Track track;
  final bool selected, playing, dark;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    final status = switch (track.availability) {
      TrackAvailability.ready => ('内容可用', CupertinoIcons.checkmark_circle),
      TrackAvailability.cloud => ('未下载 · 播放时下载', CupertinoIcons.cloud_download),
      TrackAvailability.unloaded => ('未读取 · 播放时加载', CupertinoIcons.play_circle),
      TrackAvailability.accessRequired => ('需重新授权或选择', CupertinoIcons.folder),
      TrackAvailability.loading => ('正在准备', CupertinoIcons.hourglass),
      TrackAvailability.offline => ('暂时不可用', CupertinoIcons.wifi_slash),
      TrackAvailability.missing => ('文件已移走', CupertinoIcons.folder),
      TrackAvailability.unsupported => (
        '格式不支持',
        CupertinoIcons.exclamationmark_circle,
      ),
      TrackAvailability.unknown => ('状态待确认', CupertinoIcons.question_circle),
    };
    final secondary = dark ? _playerMuted : _muted;
    return Material(
      color: selected
          ? (dark
                ? Colors.white.withValues(alpha: .1)
                : const Color(0xFFFCEEF1))
          : Colors.transparent,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            children: [
              Stack(
                alignment: Alignment.center,
                children: [
                  _Artwork(
                    size: 50,
                    seed: track.album.isEmpty ? track.title : track.album,
                  ),
                  if (selected && playing)
                    Container(
                      width: 50,
                      height: 50,
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: .35),
                        borderRadius: BorderRadius.circular(7),
                      ),
                      child: const Icon(
                        CupertinoIcons.waveform,
                        color: Colors.white,
                        size: 23,
                      ),
                    ),
                ],
              ),
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      track.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: dark
                            ? Colors.white
                            : selected
                            ? _accent
                            : _ink,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      _artist(track),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: secondary, fontSize: 12),
                    ),
                    const SizedBox(height: 3),
                    Row(
                      children: [
                        Icon(status.$2, size: 11, color: secondary),
                        const SizedBox(width: 4),
                        Flexible(
                          child: Text(
                            status.$1,
                            style: TextStyle(color: secondary, fontSize: 10),
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
                style: TextStyle(color: secondary, fontSize: 12),
              ),
            ],
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
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 0, 10, 8),
      child: Material(
        elevation: 4,
        shadowColor: Colors.black.withValues(alpha: .12),
        color: const Color(0xFFF4F4F7),
        borderRadius: BorderRadius.circular(16),
        clipBehavior: Clip.antiAlias,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 5, 6, 5),
              child: Row(
                children: [
                  Expanded(
                    child: InkWell(
                      key: const Key('open-player'),
                      onTap: onOpen,
                      borderRadius: BorderRadius.circular(12),
                      child: Padding(
                        padding: const EdgeInsets.all(4),
                        child: Row(
                          children: [
                            _Artwork(
                              size: 43,
                              bytes: s.artwork,
                              seed: s.currentTrack?.album ?? '',
                            ),
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
                                      fontSize: 14,
                                    ),
                                  ),
                                  Text(
                                    s.currentTrack == null
                                        ? '选择歌曲开始播放'
                                        : _artist(s.currentTrack!),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontSize: 11,
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
                          ? CupertinoIcons.pause_fill
                          : CupertinoIcons.play_fill,
                      size: 24,
                    ),
                  ),
                  IconButton(
                    tooltip: '下一首',
                    onPressed: s.currentTrack == null ? null : controller.next,
                    icon: const Icon(CupertinoIcons.forward_end_fill, size: 23),
                  ),
                ],
              ),
            ),
            LinearProgressIndicator(
              minHeight: 2,
              value: _fraction(s.position, s.duration),
              backgroundColor: const Color(0xFFE5E5EA),
              color: _accent.withValues(alpha: .7),
            ),
          ],
        ),
      ),
    );
  }
}

enum _PlayerView { artwork, lyrics, queue }

class _PlayerPage extends StatefulWidget {
  const _PlayerPage({required this.controller});
  final MusicController controller;
  @override
  State<_PlayerPage> createState() => _PlayerPageState();
}

class _PlayerPageState extends State<_PlayerPage> {
  _PlayerView _view = _PlayerView.artwork;
  bool _viewInitialized = false;
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_viewInitialized) {
      _view = MediaQuery.sizeOf(context).width >= 750
          ? _PlayerView.lyrics
          : _PlayerView.artwork;
      _viewInitialized = true;
    }
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: widget.controller,
    builder: (context, _) {
      final c = widget.controller;
      final s = c.snapshot;
      return Theme(
        data: Theme.of(context).copyWith(
          brightness: Brightness.dark,
          colorScheme: const ColorScheme.dark(
            primary: Colors.white,
            surface: Color(0xFF342B34),
            secondary: Colors.white,
          ),
          textTheme: Theme.of(context).textTheme
              .apply(bodyColor: Colors.white, displayColor: Colors.white),
          inputDecorationTheme: InputDecorationTheme(
            filled: true,
            fillColor: const Color(0xFF473C49),
            hintStyle: const TextStyle(color: Colors.white60),
            labelStyle: const TextStyle(color: Colors.white70),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide.none,
            ),
          ),
          dialogTheme: const DialogThemeData(
            backgroundColor: Color(0xFF342B34),
          ),
          bottomSheetTheme: const BottomSheetThemeData(
            backgroundColor: Color(0xFF342B34),
            modalBackgroundColor: Color(0xFF342B34),
          ),
          iconTheme: const IconThemeData(color: Colors.white),
          iconButtonTheme: IconButtonThemeData(
            style: IconButton.styleFrom(
              foregroundColor: Colors.white,
              disabledForegroundColor: Colors.white38,
              minimumSize: const Size(48, 48),
            ),
          ),
          textButtonTheme: TextButtonThemeData(
            style: TextButton.styleFrom(foregroundColor: Colors.white),
          ),
          sliderTheme: SliderThemeData(
            trackHeight: 4,
            activeTrackColor: Colors.white.withValues(alpha: .85),
            inactiveTrackColor: Colors.white.withValues(alpha: .18),
            thumbColor: Colors.white,
            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 5),
            overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
            trackShape: const RoundedRectSliderTrackShape(),
          ),
        ),
        child: Builder(
          builder: (context) => Scaffold(
            backgroundColor: const Color(0xFF2C2431),
            body: Stack(
              children: [
                Positioned.fill(child: _PlayerBackdrop(bytes: s.artwork)),
                SafeArea(
                  child: Column(
                    children: [
                      GestureDetector(
                        onVerticalDragEnd: (details) {
                          if ((details.primaryVelocity ?? 0) > 250) {
                            Navigator.pop(context);
                          }
                        },
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 4,
                          ),
                          child: Row(
                            children: [
                              IconButton(
                                tooltip: '返回资料库',
                                onPressed: () => Navigator.pop(context),
                                icon: const Icon(
                                  CupertinoIcons.chevron_down,
                                  size: 25,
                                ),
                              ),
                              Expanded(
                                child: Column(
                                  children: [
                                    Container(
                                      width: 34,
                                      height: 4,
                                      margin: const EdgeInsets.only(bottom: 7),
                                      decoration: BoxDecoration(
                                        color: Colors.white24,
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                    ),
                                    Text(
                                      _view == _PlayerView.queue
                                          ? '待播清单'
                                          : _view == _PlayerView.lyrics
                                          ? '歌词'
                                          : '正在播放',
                                      maxLines: 1,
                                      style: const TextStyle(
                                        fontSize: 12,
                                        color: _playerMuted,
                                        fontWeight: FontWeight.w600,
                                        letterSpacing: 1,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              IconButton(
                                tooltip: '查看歌词',
                                onPressed: () =>
                                    setState(() => _view = _PlayerView.lyrics),
                                icon: const Icon(
                                  CupertinoIcons.quote_bubble,
                                  size: 23,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      if (s.message != null)
                        _Notice(
                          text: s.message!,
                          dark: true,
                          onClose: s.isLoading ? c.cancelLoading : null,
                          closeLabel: '取消加载',
                        ),
                      if (c.error != null)
                        _Notice(
                          text: c.error!,
                          dark: true,
                          error: true,
                          onClose: c.clearError,
                        ),
                      Expanded(
                        child: LayoutBuilder(
                          builder: (context, size) {
                            final wide = size.maxWidth >= 750;
                            final short = size.maxHeight < 480;
                            final largeText =
                                MediaQuery.textScalerOf(context).scale(16) > 23;
                            final controls = _PlayerControls(
                              controller: c,
                              compact: short,
                              onLyrics: () => setState(
                                () => _view = _view == _PlayerView.lyrics
                                    ? _PlayerView.artwork
                                    : _PlayerView.lyrics,
                              ),
                              onQueue: () => setState(
                                () => _view = _view == _PlayerView.queue
                                    ? _PlayerView.artwork
                                    : _PlayerView.queue,
                              ),
                              view: _view,
                            );
                            if (wide && _view != _PlayerView.artwork) {
                              return Center(
                                child: ConstrainedBox(
                                  constraints: const BoxConstraints(
                                    maxWidth: 1280,
                                  ),
                                  child: Padding(
                                    padding: EdgeInsets.fromLTRB(
                                      short ? 24 : 48,
                                      short ? 0 : 22,
                                      short ? 16 : 48,
                                      short ? 8 : 28,
                                    ),
                                    child: Row(
                                      children: [
                                        Expanded(
                                          flex: 5,
                                          child: LayoutBuilder(
                                            builder: (context, left) {
                                              final artSize = math.min(
                                                left.maxWidth - 32,
                                                math.max(
                                                  80.0,
                                                  left.maxHeight -
                                                      (short ? 226 : 330),
                                                ),
                                              );
                                              return SingleChildScrollView(
                                                child: Column(
                                                  mainAxisSize:
                                                      MainAxisSize.min,
                                                  children: [
                                                    _Artwork(
                                                      size: artSize.clamp(
                                                        80.0,
                                                        370.0,
                                                      ),
                                                      bytes: s.artwork,
                                                      seed:
                                                          s
                                                              .currentTrack
                                                              ?.album ??
                                                          '',
                                                      shadow: true,
                                                    ),
                                                    SizedBox(
                                                      height: short ? 12 : 24,
                                                    ),
                                                    controls,
                                                  ],
                                                ),
                                              );
                                            },
                                          ),
                                        ),
                                        SizedBox(width: short ? 24 : 70),
                                        Expanded(
                                          flex: 6,
                                          child: _view == _PlayerView.queue
                                              ? _Queue(controller: c)
                                              : LyricsPanel(
                                                  immersive: true,
                                                  controller: c.lyrics,
                                                  position: s.position,
                                                  onSeek: c.seek,
                                                ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              );
                            }
                            final showArtwork = _view == _PlayerView.artwork;
                            if (largeText || size.maxHeight < 480) {
                              return SingleChildScrollView(
                                padding: const EdgeInsets.fromLTRB(
                                  24,
                                  12,
                                  24,
                                  16,
                                ),
                                child: Column(
                                  children: [
                                    if (showArtwork)
                                      _Artwork(
                                        size: math.min(size.maxWidth - 80, 210),
                                        bytes: s.artwork,
                                        seed: s.currentTrack?.album ?? '',
                                        shadow: true,
                                      )
                                    else
                                      SizedBox(
                                        height: math.max(
                                          230,
                                          size.maxHeight * .55,
                                        ),
                                        child: _view == _PlayerView.queue
                                            ? _Queue(controller: c)
                                            : LyricsPanel(
                                                immersive: true,
                                                controller: c.lyrics,
                                                position: s.position,
                                                onSeek: c.seek,
                                              ),
                                      ),
                                    const SizedBox(height: 24),
                                    controls,
                                  ],
                                ),
                              );
                            }
                            return Center(
                              child: ConstrainedBox(
                                constraints: const BoxConstraints(
                                  maxWidth: 500,
                                ),
                                child: Padding(
                                  padding: const EdgeInsets.fromLTRB(
                                    28,
                                    0,
                                    28,
                                    16,
                                  ),
                                  child: Column(
                                    children: [
                                      Expanded(
                                        child: showArtwork
                                            ? LayoutBuilder(
                                                builder: (_, area) => Center(
                                                  child: _Artwork(
                                                    size: math
                                                        .min(
                                                          area.maxWidth - 10,
                                                          area.maxHeight - 24,
                                                        )
                                                        .clamp(70.0, 370.0),
                                                    bytes: s.artwork,
                                                    seed:
                                                        s.currentTrack?.album ??
                                                        '',
                                                    shadow: true,
                                                  ),
                                                ),
                                              )
                                            : _view == _PlayerView.queue
                                            ? _Queue(controller: c)
                                            : LyricsPanel(
                                                immersive: true,
                                                controller: c.lyrics,
                                                position: s.position,
                                                onSeek: c.seek,
                                              ),
                                      ),
                                      const SizedBox(height: 16),
                                      controls,
                                    ],
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    },
  );
}

class _PlayerControls extends StatelessWidget {
  const _PlayerControls({
    required this.controller,
    required this.compact,
    required this.onLyrics,
    required this.onQueue,
    required this.view,
  });
  final MusicController controller;
  final bool compact;
  final VoidCallback onLyrics, onQueue;
  final _PlayerView view;
  @override
  Widget build(BuildContext context) {
    final s = controller.snapshot;
    final enabled = s.currentTrack != null;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          s.currentTrack?.title ?? '此刻，留给音乐',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: compact ? 20 : 25,
            fontWeight: FontWeight.w700,
            letterSpacing: -.7,
          ),
        ),
        const SizedBox(height: 3),
        Text(
          s.currentTrack == null ? '从资料库选择一首歌' : _artist(s.currentTrack!),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(color: _playerMuted, fontSize: compact ? 14 : 18),
        ),
        SizedBox(height: compact ? 0 : 14),
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
              style: const TextStyle(color: _playerMuted, fontSize: 11),
            ),
            Text(
              '-${_time(s.duration > s.position ? s.duration - s.position : Duration.zero)}',
              style: const TextStyle(color: _playerMuted, fontSize: 11),
            ),
          ],
        ),
        SizedBox(height: compact ? 0 : 10),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            IconButton(
              tooltip: '上一首',
              onPressed: enabled ? controller.previous : null,
              icon: const Icon(CupertinoIcons.backward_end_fill, size: 30),
            ),
            IconButton(
              key: const Key('player-play-pause'),
              tooltip: s.isPlaying ? '暂停' : '播放',
              onPressed: enabled ? controller.togglePlayback : null,
              style: IconButton.styleFrom(
                minimumSize: Size(72, compact ? 56 : 76),
              ),
              icon: Icon(
                s.isPlaying
                    ? CupertinoIcons.pause_fill
                    : CupertinoIcons.play_fill,
                size: compact ? 38 : 46,
              ),
            ),
            IconButton(
              tooltip: '下一首',
              onPressed: enabled ? controller.next : null,
              icon: const Icon(CupertinoIcons.forward_end_fill, size: 30),
            ),
          ],
        ),
        if (!compact)
          Row(
            children: [
              const Icon(
                CupertinoIcons.speaker_fill,
                size: 17,
                color: _playerMuted,
              ),
              Expanded(
                child: Slider(
                  value: s.volume.clamp(0, 1),
                  onChanged: controller.setVolume,
                  semanticFormatterCallback: (v) => '音量 ${(v * 100).round()}%',
                ),
              ),
              const Icon(
                CupertinoIcons.speaker_3_fill,
                size: 17,
                color: _playerMuted,
              ),
            ],
          ),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            if (compact)
              IconButton(
                tooltip: '音量',
                icon: const Icon(CupertinoIcons.speaker_2_fill, size: 22),
                onPressed: () => showModalBottomSheet<void>(
                  context: context,
                  showDragHandle: true,
                  useSafeArea: true,
                  builder: (_) => AnimatedBuilder(
                    animation: controller,
                    builder: (context, _) => Padding(
                      padding: const EdgeInsets.fromLTRB(24, 8, 24, 30),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Text(
                            '音量',
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          Slider(
                            value: controller.snapshot.volume.clamp(0, 1),
                            onChanged: controller.setVolume,
                            semanticFormatterCallback: (v) =>
                                '音量 ${(v * 100).round()}%',
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            _PlayerToggle(
              tooltip: '歌词视图',
              icon: CupertinoIcons.quote_bubble,
              selected: view == _PlayerView.lyrics,
              onPressed: onLyrics,
            ),
            _PlayerToggle(
              tooltip: s.shuffle ? '关闭随机播放' : '随机播放',
              icon: CupertinoIcons.shuffle,
              selected: s.shuffle,
              onPressed: () => controller.setShuffle(!s.shuffle),
            ),
            _PlayerToggle(
              tooltip: switch (s.repeatMode) {
                RepeatMode.off => '顺序播放，点击切换列表循环',
                RepeatMode.all => '列表循环，点击切换单曲循环',
                RepeatMode.one => '单曲循环，点击关闭循环',
              },
              icon: s.repeatMode == RepeatMode.one
                  ? CupertinoIcons.repeat_1
                  : CupertinoIcons.repeat,
              selected: s.repeatMode != RepeatMode.off,
              onPressed: () => controller.setRepeat(
                RepeatMode.values[(s.repeatMode.index + 1) %
                    RepeatMode.values.length],
              ),
            ),
            _PlayerToggle(
              tooltip: '待播清单',
              icon: CupertinoIcons.list_bullet,
              selected: view == _PlayerView.queue,
              onPressed: onQueue,
            ),
          ],
        ),
      ],
    );
  }
}

class _PlayerToggle extends StatelessWidget {
  const _PlayerToggle({
    required this.tooltip,
    required this.icon,
    required this.selected,
    required this.onPressed,
  });
  final String tooltip;
  final IconData icon;
  final bool selected;
  final VoidCallback onPressed;
  @override
  Widget build(BuildContext context) => Semantics(
    selected: selected,
    child: IconButton(
      tooltip: tooltip,
      onPressed: onPressed,
      style: IconButton.styleFrom(
        backgroundColor: selected
            ? Colors.white.withValues(alpha: .16)
            : Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      icon: Icon(icon, size: 22),
    ),
  );
}

class _Queue extends StatelessWidget {
  const _Queue({required this.controller});
  final MusicController controller;
  @override
  Widget build(BuildContext context) {
    final s = controller.snapshot;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(12, 16, 12, 6),
          child: Text(
            '待播清单',
            style: TextStyle(fontSize: 26, fontWeight: FontWeight.w700),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          child: Text(
            s.shuffle
                ? '随机播放已开启 · 列表显示资料库顺序'
                : '来自音乐资料库 · ${s.tracks.length} 首',
            style: const TextStyle(color: _playerMuted, fontSize: 12),
          ),
        ),
        Expanded(
          child: s.tracks.isEmpty
              ? const Center(
                  child: Text(
                    '从资料库选择歌曲开始播放',
                    style: TextStyle(color: _playerMuted),
                  ),
                )
              : ListView.builder(
                  key: const Key('player-queue'),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  itemCount: s.tracks.length,
                  itemBuilder: (context, i) => _TrackRow(
                    track: s.tracks[i],
                    selected: s.tracks[i].id == s.currentTrackId,
                    playing: s.isPlaying,
                    dark: true,
                    onTap: () => controller.play(s.tracks[i]),
                  ),
                ),
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
  Widget build(BuildContext context) => SizedBox(
    height: 32,
    child: SliderTheme(
      data: SliderTheme.of(context)
          .copyWith(trackShape: const _FullWidthTrack()),
      child: Slider(
        value: _drag ?? _fraction(widget.position, widget.duration),
        onChanged: widget.onSeek == null || widget.duration <= Duration.zero
            ? null
            : (v) => setState(() => _drag = v),
        onChangeEnd: (v) {
          widget.onSeek?.call(
            Duration(
              milliseconds: (widget.duration.inMilliseconds * v).round(),
            ),
          );
          setState(() => _drag = null);
        },
        semanticFormatterCallback: (v) => _time(
          Duration(milliseconds: (widget.duration.inMilliseconds * v).round()),
        ),
      ),
    ),
  );
}

class _FullWidthTrack extends RoundedRectSliderTrackShape {
  const _FullWidthTrack();
  @override
  Rect getPreferredRect({
    required RenderBox parentBox,
    Offset offset = Offset.zero,
    required SliderThemeData sliderTheme,
    bool isEnabled = false,
    bool isDiscrete = false,
  }) => Rect.fromLTWH(
    offset.dx,
    offset.dy + (parentBox.size.height - (sliderTheme.trackHeight ?? 4)) / 2,
    parentBox.size.width,
    sliderTheme.trackHeight ?? 4,
  );
}

class _Artwork extends StatelessWidget {
  const _Artwork({
    required this.size,
    this.bytes,
    this.seed = '',
    this.round = false,
    this.shadow = false,
  });
  final double size;
  final Uint8List? bytes;
  final String seed;
  final bool round, shadow;
  static const _palettes = [
    [Color(0xFFC77C75), Color(0xFF784B66), Color(0xFF384259)],
    [Color(0xFF9EADB4), Color(0xFF526E83), Color(0xFF2C414C)],
    [Color(0xFFD4B08A), Color(0xFF9A7464), Color(0xFF5F4C62)],
    [Color(0xFFAAB1A0), Color(0xFF6A887B), Color(0xFF425963)],
  ];
  @override
  Widget build(BuildContext context) {
    final colors =
        _palettes[seed.codeUnits.fold<int>(0, (a, b) => a + b) %
            _palettes.length];
    final radius = BorderRadius.circular(
      round ? size / 2 : math.max(6, size * .035),
    );
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        borderRadius: radius,
        boxShadow: shadow
            ? [
                BoxShadow(
                  color: Colors.black.withValues(alpha: .24),
                  blurRadius: 30,
                  offset: const Offset(0, 20),
                ),
              ]
            : null,
      ),
      child: ClipRRect(
        borderRadius: radius,
        child: bytes == null
            ? _fallback(colors)
            : Image.memory(
                bytes!,
                width: size,
                height: size,
                fit: BoxFit.cover,
                gaplessPlayback: true,
                errorBuilder: (_, error, stack) => _fallback(colors),
              ),
      ),
    );
  }

  Widget _fallback(List<Color> colors) => Stack(
    fit: StackFit.expand,
    children: [
      DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: colors,
          ),
        ),
      ),
      Positioned(
        left: -size * .15,
        top: -size * .4,
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: RadialGradient(
              colors: [
                Colors.white.withValues(alpha: .18),
                Colors.white.withValues(alpha: 0),
              ],
            ),
          ),
        ),
      ),
      Positioned(
        right: -size * .3,
        bottom: -size * .35,
        child: Container(
          width: size * 1.1,
          height: size * 1.1,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(
              color: Colors.white.withValues(alpha: .08),
              width: size * .16,
            ),
          ),
        ),
      ),
      Center(
        child: Icon(
          CupertinoIcons.music_note,
          size: size * .39,
          color: Colors.white.withValues(alpha: .82),
        ),
      ),
      if (size >= 160)
        Positioned(
          bottom: size * .1,
          left: 0,
          right: 0,
          child: Text(
            '云 听  ·  原 声',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: size * .032,
              color: Colors.white.withValues(alpha: .65),
              letterSpacing: 2,
            ),
          ),
        ),
    ],
  );
}

class _PlayerBackdrop extends StatelessWidget {
  const _PlayerBackdrop({this.bytes});
  final Uint8List? bytes;
  @override
  Widget build(BuildContext context) => Stack(
    fit: StackFit.expand,
    children: [
      const DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF785352), Color(0xFF443646), Color(0xFF222B3D)],
          ),
        ),
      ),
      if (bytes != null)
        ImageFiltered(
          imageFilter: ui.ImageFilter.blur(sigmaX: 80, sigmaY: 80),
          child: Image.memory(
            bytes!,
            fit: BoxFit.cover,
            gaplessPlayback: true,
            errorBuilder: (_, error, stack) => const SizedBox.shrink(),
          ),
        ),
      const DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0x22202130), Color(0xA021202D)],
          ),
        ),
      ),
    ],
  );
}

class _Notice extends StatelessWidget {
  const _Notice({
    required this.text,
    this.error = false,
    this.dark = false,
    this.onClose,
    this.closeLabel = '关闭提示',
  });
  final String text, closeLabel;
  final bool error, dark;
  final VoidCallback? onClose;
  @override
  Widget build(BuildContext context) => Container(
    color: dark
        ? Colors.white.withValues(alpha: .1)
        : error
        ? const Color(0xFFFFEFF1)
        : const Color(0xFFF1F1F5),
    padding: const EdgeInsets.only(left: 20, right: 8),
    child: Row(
      children: [
        Icon(
          error ? CupertinoIcons.exclamationmark_circle : CupertinoIcons.cloud,
          size: 19,
          color: dark ? Colors.white : _accent,
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: Text(
              text,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 12, color: dark ? Colors.white : _ink),
            ),
          ),
        ),
        if (onClose != null)
          IconButton(
            tooltip: closeLabel,
            onPressed: onClose,
            icon: const Icon(CupertinoIcons.xmark, size: 18),
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
