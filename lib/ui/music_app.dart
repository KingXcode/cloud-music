import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/cupertino.dart' hide RepeatMode;
import 'package:flutter_localizations/flutter_localizations.dart';

import 'cupertino_controls.dart';

import '../models.dart';
import '../music_controller.dart';
import 'lyrics_panel.dart';
import 'macos_window_chrome.dart';
import 'player_scroll_area.dart';
import 'music_sources_sheet.dart';
import '../updates/update_controller.dart';
import 'update_panel.dart';
import 'library_filter_sheet.dart';
import 'library_options_sheet.dart';
import 'music_import_sheet.dart';

const _accent = Color(0xFFD92E4B);
const _ink = Color(0xFF202024);
const _muted = Color(0xFF6F6F76);
const _canvas = Color(0xFFF9F9FB);
const _line = Color(0xFFE8E8ED);
const _playerMuted = Color(0xFFCDC3C5);

class MusicApp extends StatelessWidget {
  const MusicApp({super.key, required this.controller, this.updates});
  final MusicController controller;
  final UpdateController? updates;

  @override
  Widget build(BuildContext context) => CupertinoApp(
    title: '弦泊 · Xianbo',
    locale: const Locale('zh', 'CN'),
    supportedLocales: const [Locale('zh', 'CN'), Locale('en')],
    localizationsDelegates: const [
      GlobalCupertinoLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
    ],
    debugShowCheckedModeBanner: false,
    builder: (context, child) => MacosWindowChrome(child: child!),
    theme: const CupertinoThemeData(
      brightness: Brightness.light,
      primaryColor: _accent,
      scaffoldBackgroundColor: CupertinoColors.white,
      textTheme: CupertinoTextThemeData(
        textStyle: TextStyle(
          fontFamily: '.SF Pro Text',
          fontFamilyFallback: ['PingFang SC', 'Microsoft YaHei', 'sans-serif'],
          fontSize: 16,
          color: _ink,
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
  final _scroll = ScrollController();
  double _savedOffset = 0;
  String _query = '';
  _LibrarySection _section = _LibrarySection.songs;
  String? _group;
  bool _openingPlayer = false, _openingFilter = false, _openingOptions = false;
  _LibrarySection _savedSection = _LibrarySection.songs;
  String? _savedGroup;
  String? _dismissedMessage;
  bool _openingImport = false, _openingSources = false;

  @override
  void dispose() {
    _search.dispose();
    _searchFocus.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _openPlayer() async {
    if (_openingPlayer) return;
    _openingPlayer = true;
    _searchFocus.unfocus();
    await Navigator.of(context).push(
      CupertinoPageRoute<void>(
        fullscreenDialog: true,
        builder: (_) => _PlayerPage(controller: widget.controller),
      ),
    );
    _openingPlayer = false;
  }

  Future<void> _openFilter() async {
    if (_openingFilter) return;
    _openingFilter = true;
    _searchFocus.unfocus();
    try {
      await showLibraryFilter(context, widget.controller);
    } finally {
      _openingFilter = false;
    }
  }

  Future<void> _addMusic() async {
    final c = widget.controller;
    if (c.isBusy || _openingImport) return;
    if (!c.canScanDevice && (!c.canPickFiles || c.selectsFiles)) {
      // Keep a direct user-gesture path for single-capability browsers.
      await c.pickFolder();
      return;
    }
    _openingImport = true;
    _searchFocus.unfocus();
    try {
      await showMusicImport(context, c);
    } finally {
      _openingImport = false;
    }
  }

  Future<void> _openSources() async {
    if (_openingSources) return;
    _openingSources = true;
    try {
      await showMusicSources(context, widget.controller);
    } finally {
      _openingSources = false;
    }
  }

  Future<void> _openOptions() async {
    if (_openingOptions) return;
    _openingOptions = true;
    _searchFocus.unfocus();
    try {
      final action = await showLibraryOptions(
        context,
        widget.controller,
        hasUpdates: widget.updates != null,
      );
      if (!mounted || action == null) return;
      switch (action) {
        case LibraryOption.sources:
          await _openSources();
        case LibraryOption.filter:
          await _openFilter();
        case LibraryOption.updates:
          if (widget.updates != null) {
            await showAppUpdates(context, widget.updates!);
          }
        case LibraryOption.refresh:
          await widget.controller.refresh();
      }
    } finally {
      _openingOptions = false;
    }
  }

  void _select(_LibrarySection section) {
    setState(() {
      if (section == _LibrarySection.search &&
          _section != _LibrarySection.search) {
        _savedOffset = _scroll.hasClients ? _scroll.offset : 0;
        _savedSection = _section;
        _savedGroup = _group;
      }
      _section = section;
      _group = null;
      if (section != _LibrarySection.search) {
        _query = '';
        _search.clear();
      }
    });
    _scrollTo(0);
    if (section == _LibrarySection.search) {
      _searchFocus.requestFocus();
    } else {
      _searchFocus.unfocus();
    }
  }

  void _returnToLibrary() {
    if (_section != _LibrarySection.search) return;
    _select(_savedSection);
    setState(() => _group = _savedGroup);
    _scrollTo(_savedOffset);
  }

  void _scrollTo(double offset) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _scroll.hasClients) {
        _scroll.jumpTo(offset.clamp(0, _scroll.position.maxScrollExtent));
      }
    });
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: widget.controller,
    builder: (context, _) {
      final c = widget.controller;
      final s = c.snapshot;
      final visible = c.libraryFilter.visibleTracks(s.tracks);
      final hidden = s.tracks.length - visible.length;
      final tracks = visible.where((t) {
        final matches = '${t.title} ${t.artist} ${t.album} ${t.relativePath}'
            .toLowerCase()
            .contains(_query.toLowerCase());
        return matches &&
            (_group == null ||
                (_section == _LibrarySection.albums ? _album(t) : _artist(t)) ==
                    _group);
      }).toList();
      return PopScope(
        canPop: _section != _LibrarySection.search && _group == null,
        onPopInvokedWithResult: (didPop, result) {
          if (didPop) return;
          if (_section == _LibrarySection.search) {
            _returnToLibrary();
          } else if (_group != null) {
            setState(() => _group = null);
          }
        },
        child: CupertinoPageScaffold(
          child: SafeArea(
            top: !usesMacosWindowChrome,
            child: LayoutBuilder(
              builder: (context, constraints) {
                final topInset = usesMacosWindowChrome
                    ? MediaQuery.paddingOf(context).top
                    : 0.0;
                final wide = constraints.maxWidth >= 750;
                final short = constraints.maxHeight - topInset < 500;
                return Row(
                  children: [
                    if (wide) _sidebar(s, short, topInset: topInset),
                    Expanded(
                      child: Column(
                        children: [
                          SizedBox(height: topInset),
                          if (widget.updates != null)
                            UpdateBanner(controller: widget.updates!),
                          if (c.usingDrive && c.isLocalImportScanning)
                            Container(
                              key: const Key('staged-import-progress'),
                              color: _canvas,
                              padding: const EdgeInsets.only(
                                left: 20,
                                right: 8,
                              ),
                              child: Row(
                                children: [
                                  const SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CupertinoActivityIndicator(
                                      radius: 8,
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Text(
                                      c.localImportMessage ?? '正在导入音乐…',
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        fontSize: 12,
                                        color: _muted,
                                      ),
                                    ),
                                  ),
                                  CupertinoButton(
                                    key: const Key('cancel-local-import'),
                                    onPressed: c.cancelLocalImport,
                                    child: const Text('取消'),
                                  ),
                                ],
                              ),
                            ),
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
                          if (!s.isLoading &&
                              s.message != null &&
                              s.message != _dismissedMessage)
                            _LibraryStatus(
                              message: s.message!,
                              onDismiss: () =>
                                  setState(() => _dismissedMessage = s.message),
                            ),
                          Expanded(
                            child: CustomScrollView(
                              key: const Key('library-scroll'),
                              controller: _scroll,
                              slivers: [
                                SliverToBoxAdapter(
                                  child: Padding(
                                    padding: EdgeInsets.fromLTRB(
                                      wide ? 40 : 22,
                                      short ? 8 : 18,
                                      wide ? 32 : 14,
                                      8,
                                    ),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          children: [
                                            Expanded(
                                              child: Text(
                                                _section ==
                                                        _LibrarySection.search
                                                    ? '搜索'
                                                    : '音乐资料库',
                                                style: TextStyle(
                                                  fontSize: short ? 25 : 30,
                                                  fontWeight: FontWeight.w800,
                                                  letterSpacing: -1,
                                                ),
                                              ),
                                            ),
                                            if (_section !=
                                                _LibrarySection.search)
                                              CupertinoIconControl(
                                                label: c.selectsFiles
                                                    ? '选择或更换音乐文件'
                                                    : '选择或更换音乐文件夹',
                                                onPressed: c.isBusy
                                                    ? null
                                                    : _addMusic,
                                                foregroundColor: _accent,
                                                icon: const Icon(
                                                  CupertinoIcons.add,
                                                  size: 26,
                                                ),
                                              ),
                                            CupertinoIconControl(
                                              key: const Key('library-options'),
                                              label: '资料库选项',
                                              onPressed: _openOptions,
                                              foregroundColor: _accent,
                                              icon: const Icon(
                                                CupertinoIcons.ellipsis_circle,
                                                size: 25,
                                              ),
                                            ),
                                          ],
                                        ),
                                        if (_section ==
                                            _LibrarySection.search) ...[
                                          const SizedBox(height: 14),
                                          CupertinoSearchTextField(
                                            key: const Key('library-search'),
                                            controller: _search,
                                            focusNode: _searchFocus,
                                            placeholder: '歌曲、歌手或专辑',
                                            onSubmitted: (_) =>
                                                _searchFocus.unfocus(),
                                            onChanged: (value) => setState(() {
                                              _query = value;
                                              _group = null;
                                            }),
                                            onSuffixTap: () {
                                              _search.clear();
                                              setState(() => _query = '');
                                              _searchFocus.requestFocus();
                                            },
                                          ),
                                        ],
                                        if (!wide &&
                                            s.tracks.isNotEmpty &&
                                            _section != _LibrarySection.search)
                                          Padding(
                                            padding: const EdgeInsets.only(
                                              top: 12,
                                            ),
                                            child: SizedBox(
                                              width: double.infinity,
                                              child:
                                                  CupertinoSlidingSegmentedControl<
                                                    _LibrarySection
                                                  >(
                                                    groupValue: _section,
                                                    onValueChanged: (value) {
                                                      if (value != null) {
                                                        _select(value);
                                                      }
                                                    },
                                                    children: {
                                                      for (final section in [
                                                        _LibrarySection.songs,
                                                        _LibrarySection.albums,
                                                        _LibrarySection.artists,
                                                      ])
                                                        section: Padding(
                                                          padding:
                                                              const EdgeInsets.symmetric(
                                                                vertical: 10,
                                                              ),
                                                          child: Text(
                                                            _label(section),
                                                            style:
                                                                const TextStyle(
                                                                  fontSize: 14,
                                                                ),
                                                          ),
                                                        ),
                                                    },
                                                  ),
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
                                                const CupertinoProgress(),
                                                const SizedBox(height: 6),
                                                Text(
                                                  '正在列出歌曲 · 已显示 ${visible.length} 首',
                                                  style: const TextStyle(
                                                    color: _muted,
                                                    fontSize: 12,
                                                  ),
                                                ),
                                                if (s.sourceKind == 'android')
                                                  CupertinoButton(
                                                    key: const Key(
                                                      'cancel-library-scan',
                                                    ),
                                                    onPressed: c.cancelLoading,
                                                    child: const Text('取消扫描'),
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
                                      child: CupertinoActivityIndicator(),
                                    ),
                                  )
                                else if (s.tracks.isEmpty)
                                  SliverFillRemaining(
                                    hasScrollBody: false,
                                    child: _EmptyLibrary(
                                      hasFolder: s.folderName != null,
                                      scanning: s.isScanning,
                                      filesOnly: c.selectsFiles,
                                      busy: c.isBusy,
                                      onPick: c.pickFolder,
                                      onRefresh: c.refresh,
                                      onSources: _openSources,
                                      onScan: c.canScanDevice
                                          ? c.scanDevice
                                          : null,
                                      onPickFiles:
                                          c.canPickFiles && !c.selectsFiles
                                          ? c.pickFiles
                                          : null,
                                    ),
                                  )
                                else ...[
                                  SliverToBoxAdapter(
                                    child: Padding(
                                      padding: EdgeInsets.fromLTRB(
                                        wide ? 40 : 22,
                                        0,
                                        wide ? 40 : 22,
                                        4,
                                      ),
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.stretch,
                                        children: [
                                          if (_group != null)
                                            Align(
                                              alignment: Alignment.centerLeft,
                                              child: CupertinoActionButton(
                                                onPressed: () => setState(
                                                  () => _group = null,
                                                ),
                                                icon: const Icon(
                                                  CupertinoIcons.chevron_back,
                                                  size: 15,
                                                ),
                                                label: Text(_label(_section)),
                                              ),
                                            ),
                                          if (_group != null)
                                            Text(
                                              _group!,
                                              style: const TextStyle(
                                                fontSize: 24,
                                                fontWeight: FontWeight.w700,
                                              ),
                                            ),
                                          Row(
                                            children: [
                                              Expanded(
                                                child: Text(
                                                  _section ==
                                                          _LibrarySection.search
                                                      ? '搜索结果 · ${tracks.length} 首'
                                                      : '${tracks.length} 首歌曲',
                                                  key: const Key(
                                                    'library-count',
                                                  ),
                                                  style: const TextStyle(
                                                    color: _muted,
                                                    fontSize: 13,
                                                  ),
                                                ),
                                              ),
                                              if (hidden > 0)
                                                CupertinoIconControl(
                                                  key: const Key(
                                                    'hidden-tracks-shortcut',
                                                  ),
                                                  label:
                                                      '已隐藏 $hidden 首短音频，调整过滤',
                                                  onPressed: _openFilter,
                                                  foregroundColor: _muted,
                                                  icon: const Icon(
                                                    CupertinoIcons
                                                        .line_horizontal_3_decrease,
                                                    size: 20,
                                                  ),
                                                ),
                                              if (tracks.isNotEmpty &&
                                                  (_section ==
                                                          _LibrarySection
                                                              .songs ||
                                                      _group != null)) ...[
                                                CupertinoIconControl(
                                                  label: '播放全部',
                                                  foregroundColor: _accent,
                                                  onPressed: () async {
                                                    await c.setShuffle(false);
                                                    await c.play(tracks.first);
                                                  },
                                                  icon: const Icon(
                                                    CupertinoIcons.play_fill,
                                                    size: 22,
                                                  ),
                                                ),
                                                CupertinoIconControl(
                                                  label: '随机播放',
                                                  foregroundColor: _accent,
                                                  onPressed: () async {
                                                    await c.setShuffle(true);
                                                    await c.play(
                                                      tracks[math.Random()
                                                          .nextInt(
                                                            tracks.length,
                                                          )],
                                                    );
                                                  },
                                                  icon: const Icon(
                                                    CupertinoIcons.shuffle,
                                                    size: 24,
                                                  ),
                                                ),
                                              ],
                                            ],
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                  if (tracks.isEmpty)
                                    SliverFillRemaining(
                                      hasScrollBody: false,
                                      child: Center(
                                        child: Column(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Text(
                                              visible.isEmpty && hidden > 0
                                                  ? '短音频已隐藏'
                                                  : '没有找到匹配的歌曲',
                                              style: const TextStyle(
                                                color: _muted,
                                              ),
                                            ),
                                            if (hidden > 0)
                                              CupertinoButton(
                                                onPressed: _openFilter,
                                                child: const Text('调整过滤条件'),
                                              ),
                                          ],
                                        ),
                                      ),
                                    )
                                  else if ((_section ==
                                              _LibrarySection.albums ||
                                          _section ==
                                              _LibrarySection.artists) &&
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
                          if (s.currentTrack != null)
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
        ),
      );
    },
  );

  Widget _sidebar(
    LibrarySnapshot s,
    bool short, {
    double topInset = 0,
  }) => Container(
    width: short ? 180 : 224,
    decoration: const BoxDecoration(
      color: _canvas,
      border: Border(right: BorderSide(color: _line)),
    ),
    padding: EdgeInsets.fromLTRB(
      20,
      topInset + (short ? 14 : 32),
      20,
      short ? 8 : 24,
    ),
    child: LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: constraints.maxHeight),
          child: IntrinsicHeight(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: Image.asset(
                        'assets/branding/xianbo-icon.png',
                        width: 32,
                        height: 32,
                        excludeFromSemantics: true,
                      ),
                    ),
                    const SizedBox(width: 10),
                    const Flexible(
                      child: Text(
                        '弦泊',
                        style: TextStyle(
                          fontSize: 25,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -1,
                        ),
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
                    child: Semantics(
                      selected: _section == section,
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(10),
                        child: CupertinoButton(
                          padding: EdgeInsets.zero,
                          onPressed: () => _select(section),
                          child: CupertinoListTile(
                            backgroundColor: _section == section
                                ? const Color(0xFFFCE8ED)
                                : CupertinoColors.transparent,
                            leading: Icon(
                              _icon(section),
                              color: _accent,
                              size: 23,
                            ),
                            title: Text(
                              _label(section),
                              style: TextStyle(
                                color: _section == section ? _accent : _ink,
                                fontWeight: _section == section
                                    ? FontWeight.w700
                                    : FontWeight.w500,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                const Spacer(),
                if (!short) ...[
                  const SizedBox(height: 1, child: ColoredBox(color: _line)),
                  const SizedBox(height: 16),
                  const Icon(CupertinoIcons.folder, size: 22, color: _muted),
                  const SizedBox(height: 10),
                  Text(
                    s.folderName ?? '属于你的音乐',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                    ),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    '原文件播放 · 音频不上传',
                    style: TextStyle(color: _muted, fontSize: 11, height: 1.6),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    ),
  );

  Widget _bottomNavigation(bool short) => CupertinoTabBar(
    currentIndex: _section == _LibrarySection.search ? 1 : 0,
    height: short ? 48 : 54,
    backgroundColor: _canvas,
    activeColor: _accent,
    inactiveColor: _muted,
    onTap: (index) =>
        index == 0 ? _returnToLibrary() : _select(_LibrarySection.search),
    items: const [
      BottomNavigationBarItem(
        icon: Icon(CupertinoIcons.music_albums),
        label: '资料库',
      ),
      BottomNavigationBarItem(icon: Icon(CupertinoIcons.search), label: '搜索'),
    ],
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
        itemBuilder: (context, i) => CupertinoButton(
          padding: EdgeInsets.zero,
          onPressed: () {
            setState(() => _group = names[i]);
            _scrollTo(0);
          },
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

class _EmptyLibrary extends StatelessWidget {
  const _EmptyLibrary({
    required this.hasFolder,
    this.scanning = false,
    required this.filesOnly,
    required this.busy,
    required this.onPick,
    required this.onRefresh,
    required this.onSources,
    this.onScan,
    this.onPickFiles,
  });
  final bool hasFolder, filesOnly, busy, scanning;
  final VoidCallback onPick, onRefresh, onSources;
  final VoidCallback? onScan, onPickFiles;
  @override
  Widget build(BuildContext context) {
    final largeText = MediaQuery.textScalerOf(context).scale(14) > 20;
    final compact = largeText || MediaQuery.sizeOf(context).height < 700;
    return Padding(
      padding: EdgeInsets.symmetric(
        horizontal: 28,
        vertical: compact ? 16 : 28,
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (!largeText)
            Container(
              width: compact ? 80 : 112,
              height: compact ? 80 : 112,
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
          if (!largeText) SizedBox(height: compact ? 16 : 24),
          Text(
            scanning
                ? '正在读取目录'
                : hasFolder
                ? '这里还没有音乐'
                : '你的音乐，不必搬家',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: compact ? 22 : 24,
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
                  : compact && !hasFolder
                  ? (filesOnly ? '多选音乐文件，开始聆听。' : '选择音乐文件夹，开始聆听。')
                  : onScan != null && !hasFolder
                  ? '扫描本机音乐，或选择设备、U 盘上的音乐文件夹。'
                  : filesOnly
                  ? '在“文件”中打开音乐所在位置，可多选歌曲。\n刷新网页后需重新选择，音频不会上传。'
                  : hasFolder
                  ? '将音频放进所选文件夹后刷新，或选择另一个文件夹。'
                  : '连接 iCloud Drive 或设备上的音乐文件夹。\n聆听原文件，把空间留给喜欢的音乐。',
              textAlign: TextAlign.center,
              style: const TextStyle(color: _muted, height: 1.5, fontSize: 14),
            ),
          ),
          SizedBox(height: compact ? 16 : 24),
          CupertinoActionButton(
            filled: true,
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
          ),
          if (hasFolder)
            CupertinoActionButton(
              onPressed: busy ? null : onRefresh,
              icon: const Icon(CupertinoIcons.arrow_clockwise, size: 18),
              label: Text(filesOnly ? '重新选择音乐文件' : '刷新资料库'),
            ),
          if (onScan != null)
            CupertinoActionButton(
              key: const Key('empty-scan-device'),
              onPressed: busy ? null : onScan,
              icon: const Icon(CupertinoIcons.music_note_list, size: 20),
              label: const Text('扫描本机音乐'),
            ),
          if (onPickFiles != null)
            CupertinoButton(
              key: const Key('empty-pick-files'),
              onPressed: busy ? null : onPickFiles,
              child: const Text('或选择多个音乐文件'),
            ),
          CupertinoButton(
            key: const Key('empty-music-sources'),
            onPressed: busy ? null : onSources,
            child: const Text('连接其他音乐来源'),
          ),
          const SizedBox(height: 8),
          const Text(
            '原文件播放 · 音频不上传',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 11, color: _muted),
          ),
        ],
      ),
    );
  }
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
    return Container(
      decoration: BoxDecoration(
        color: selected
            ? (dark
                  ? CupertinoColors.white.withValues(alpha: .1)
                  : const Color(0xFFFCEEF1))
            : CupertinoColors.transparent,
        borderRadius: BorderRadius.circular(12),
      ),
      child: CupertinoButton(
        padding: EdgeInsets.zero,
        onPressed: onTap,
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
                        color: CupertinoColors.black.withValues(alpha: .35),
                        borderRadius: BorderRadius.circular(7),
                      ),
                      child: const Icon(
                        CupertinoIcons.waveform,
                        color: CupertinoColors.white,
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
                            ? CupertinoColors.white
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
      child: Container(
        decoration: BoxDecoration(
          color: const Color(0xFFF4F4F7),
          borderRadius: BorderRadius.circular(16),
          boxShadow: const [
            BoxShadow(
              color: Color(0x14000000),
              blurRadius: 12,
              offset: Offset(0, 3),
            ),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 5, 6, 5),
              child: Row(
                children: [
                  Expanded(
                    child: CupertinoButton(
                      foregroundColor: _ink,
                      padding: EdgeInsets.zero,
                      key: const Key('open-player'),
                      onPressed: onOpen,
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
                  CupertinoIconControl(
                    label: s.isPlaying ? '暂停' : '播放',
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
                  CupertinoIconControl(
                    label: '下一首',
                    onPressed: s.currentTrack == null ? null : controller.next,
                    icon: const Icon(CupertinoIcons.forward_end_fill, size: 23),
                  ),
                ],
              ),
            ),
            CupertinoProgress(
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
  final _detailsScroll = ScrollController();
  _PlayerView _view = _PlayerView.artwork;
  bool _viewInitialized = false;

  @override
  void dispose() {
    _detailsScroll.dispose();
    super.dispose();
  }

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

  Widget _details(
    LibrarySnapshot snapshot,
    Widget controls, {
    required bool compact,
    required bool largeText,
  }) => LayoutBuilder(
    key: const Key('player-details-layout'),
    builder: (context, area) {
      Widget artwork(double size) => _Artwork(
        size: size,
        bytes: snapshot.artwork,
        seed: snapshot.currentTrack?.album ?? '',
        shadow: true,
      );
      final gap = compact ? 12.0 : 24.0;
      // 封面使用剩余高度，避免少量溢出产生贯穿播放区的滚动条。
      if (!largeText && area.maxHeight >= (compact ? 330 : 480)) {
        return Padding(
          padding: const EdgeInsets.only(right: 24),
          child: Column(
            children: [
              Expanded(
                child: LayoutBuilder(
                  builder: (context, cover) => Center(
                    child: artwork(
                      math.max(
                        0,
                        math.min(
                          370,
                          math.min(cover.maxWidth - 32, cover.maxHeight),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              SizedBox(height: gap),
              controls,
            ],
          ),
        );
      }
      final artSize = math.min(
        area.maxWidth - 56,
        math.max(80.0, area.maxHeight - (compact ? 226 : 330)),
      );
      return PlayerScrollArea(
        key: const Key('player-details-scroll-area'),
        controller: _detailsScroll,
        child: SingleChildScrollView(
          key: const Key('player-details-scroll'),
          controller: _detailsScroll,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              artwork(artSize.clamp(80.0, 370.0)),
              SizedBox(height: gap),
              controls,
            ],
          ),
        ),
      );
    },
  );

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: widget.controller,
    builder: (context, _) {
      final c = widget.controller;
      final s = c.snapshot;
      return CupertinoTheme(
        data: const CupertinoThemeData(
          brightness: Brightness.dark,
          primaryColor: CupertinoColors.white,
          scaffoldBackgroundColor: Color(0xFF2C2431),
          textTheme: CupertinoTextThemeData(
            textStyle: TextStyle(
              fontFamily: '.SF Pro Text',
              fontFamilyFallback: [
                'PingFang SC',
                'Microsoft YaHei',
                'sans-serif',
              ],
              fontSize: 16,
              color: CupertinoColors.white,
            ),
          ),
        ),
        child: Builder(
          builder: (context) => DefaultTextStyle(
            style: CupertinoTheme.of(context).textTheme.textStyle,
            child: CupertinoPageScaffold(
              backgroundColor: const Color(0xFF2C2431),
              child: Stack(
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
                                CupertinoIconControl(
                                  label: '返回资料库',
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
                                        margin: const EdgeInsets.only(
                                          bottom: 7,
                                        ),
                                        decoration: BoxDecoration(
                                          color: const Color(0x3DFFFFFF),
                                          borderRadius: BorderRadius.circular(
                                            4,
                                          ),
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
                                CupertinoIconControl(
                                  label: '查看歌词',
                                  onPressed: () => setState(
                                    () => _view = _PlayerView.lyrics,
                                  ),
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
                                  MediaQuery.textScalerOf(context).scale(16) >
                                  23;
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
                                            child: _details(
                                              s,
                                              controls,
                                              compact: short,
                                              largeText: largeText,
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
                                          size: math.min(
                                            size.maxWidth - 80,
                                            210,
                                          ),
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
                                                          s
                                                              .currentTrack
                                                              ?.album ??
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
            CupertinoIconControl(
              label: '上一首',
              onPressed: enabled ? controller.previous : null,
              icon: const Icon(CupertinoIcons.backward_end_fill, size: 30),
            ),
            CupertinoIconControl(
              key: const Key('player-play-pause'),
              label: s.isPlaying ? '暂停' : '播放',
              onPressed: enabled ? controller.togglePlayback : null,
              minimumSize: Size(72, compact ? 56 : 76),
              icon: Icon(
                s.isPlaying
                    ? CupertinoIcons.pause_fill
                    : CupertinoIcons.play_fill,
                size: compact ? 38 : 46,
              ),
            ),
            CupertinoIconControl(
              label: '下一首',
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
                child: CupertinoValueSlider(
                  label: '音量',
                  value: s.volume.clamp(0, 1),
                  onChanged: controller.setVolume,
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
              CupertinoIconControl(
                label: '音量',
                icon: const Icon(CupertinoIcons.speaker_2_fill, size: 22),
                onPressed: () async {
                  final theme = CupertinoTheme.of(context);
                  await showCupertinoModalPopup<void>(
                    context: context,
                    semanticsDismissible: true,
                    builder: (context) => CupertinoTheme(
                      data: theme,
                      child: CupertinoActionSheet(
                        title: const Text('音量'),
                        message: AnimatedBuilder(
                          animation: controller,
                          builder: (context, _) => CupertinoValueSlider(
                            label: '音量',
                            value: controller.snapshot.volume.clamp(0, 1),
                            onChanged: controller.setVolume,
                          ),
                        ),
                        cancelButton: CupertinoActionSheetAction(
                          onPressed: () => Navigator.pop(context),
                          child: const Text('完成'),
                        ),
                      ),
                    ),
                  );
                },
              ),
            _PlayerToggle(
              label: '歌词视图',
              icon: CupertinoIcons.quote_bubble,
              selected: view == _PlayerView.lyrics,
              onPressed: onLyrics,
            ),
            _PlayerToggle(
              label: s.shuffle ? '关闭随机播放' : '随机播放',
              icon: CupertinoIcons.shuffle,
              selected: s.shuffle,
              onPressed: () => controller.setShuffle(!s.shuffle),
            ),
            _PlayerToggle(
              label: switch (s.repeatMode) {
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
              label: '待播清单',
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
    required this.label,
    required this.icon,
    required this.selected,
    required this.onPressed,
  });
  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onPressed;
  @override
  Widget build(BuildContext context) => Semantics(
    selected: selected,
    child: CupertinoIconControl(
      label: label,
      onPressed: onPressed,
      backgroundColor: selected
          ? CupertinoColors.white.withValues(alpha: .16)
          : null,
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
    height: 44,
    child: CupertinoValueSlider(
      label: '播放进度',
      formatValue: (value) => _time(
        Duration(
          milliseconds: (widget.duration.inMilliseconds * value).round(),
        ),
      ),
      value: _drag ?? _fraction(widget.position, widget.duration),
      activeColor: CupertinoColors.white,
      onChanged: widget.onSeek == null || widget.duration <= Duration.zero
          ? null
          : (v) => setState(() => _drag = v),
      onChangeEnd: (v) {
        widget.onSeek?.call(
          Duration(milliseconds: (widget.duration.inMilliseconds * v).round()),
        );
        setState(() => _drag = null);
      },
    ),
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
                  color: CupertinoColors.black.withValues(alpha: .24),
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
                CupertinoColors.white.withValues(alpha: .18),
                CupertinoColors.white.withValues(alpha: 0),
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
              color: CupertinoColors.white.withValues(alpha: .08),
              width: size * .16,
            ),
          ),
        ),
      ),
      Center(
        child: Icon(
          CupertinoIcons.music_note,
          size: size * .39,
          color: CupertinoColors.white.withValues(alpha: .82),
        ),
      ),
      if (size >= 160)
        Positioned(
          bottom: size * .1,
          left: 0,
          right: 0,
          child: Text(
            '弦 泊  ·  原 声',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: size * .032,
              color: CupertinoColors.white.withValues(alpha: .65),
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

class _LibraryStatus extends StatelessWidget {
  const _LibraryStatus({required this.message, required this.onDismiss});
  final String message;
  final VoidCallback onDismiss;
  @override
  Widget build(BuildContext context) => ColoredBox(
    color: _canvas,
    child: Row(
      children: [
        Expanded(
          child: CupertinoButton(
            padding: EdgeInsets.zero,
            key: const Key('library-status-details'),
            onPressed: () => showCupertinoDialog<void>(
              context: context,
              builder: (context) => CupertinoAlertDialog(
                title: const Text('资料库提示'),
                content: SingleChildScrollView(child: Text(message)),
                actions: [
                  CupertinoDialogAction(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('知道了'),
                  ),
                ],
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 4, 12),
              child: Row(
                children: [
                  const Icon(
                    CupertinoIcons.info_circle,
                    size: 18,
                    color: _muted,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      message,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 12, color: _muted),
                    ),
                  ),
                  const SizedBox(width: 8),
                  const Text(
                    '详情',
                    style: TextStyle(fontSize: 12, color: _accent),
                  ),
                ],
              ),
            ),
          ),
        ),
        CupertinoIconControl(
          label: '关闭资料库提示',
          onPressed: onDismiss,
          icon: const Icon(CupertinoIcons.xmark, size: 16),
        ),
      ],
    ),
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
        ? CupertinoColors.white.withValues(alpha: .1)
        : error
        ? const Color(0xFFFFEFF1)
        : const Color(0xFFF1F1F5),
    padding: const EdgeInsets.only(left: 20, right: 8),
    child: Row(
      children: [
        Icon(
          error ? CupertinoIcons.exclamationmark_circle : CupertinoIcons.cloud,
          size: 19,
          color: dark ? CupertinoColors.white : _accent,
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: Text(
              text,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12,
                color: dark ? CupertinoColors.white : _ink,
              ),
            ),
          ),
        ),
        if (onClose != null)
          CupertinoIconControl(
            label: closeLabel,
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
