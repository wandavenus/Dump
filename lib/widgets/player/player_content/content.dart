part of '../player_content.dart';

class PlayerContent extends StatefulWidget {
  final LocalSong song;
  final AudioPlaybackState playbackState;
  final String Function(Duration duration) formatTime;
  final bool showLyrics;
  final VoidCallback onLyricsToggle;

  const PlayerContent({
    super.key,
    required this.song,
    required this.playbackState,
    required this.formatTime,
    required this.showLyrics,
    required this.onLyricsToggle,
  });

  @override
  State<PlayerContent> createState() => _PlayerContentState();
}

class _PlayerContentState extends State<PlayerContent> {
  static const _smallCoverSize = 57.0;
  double _lyricsExpand = 0.0;
  static const _animDuration = Duration(milliseconds: 400);
  static const _animCurve = Curves.easeInOutCubic;

  Future<LyricsResult>? _lyricsFuture;
  int? _lastFetchedSongId;

  @override
  void initState() {
    super.initState();
    _fetchLyricsIfNeeded();
  }

  @override
  void didUpdateWidget(PlayerContent old) {
    super.didUpdateWidget(old);
    if (old.song.id != widget.song.id) {
      _fetchLyricsIfNeeded();
    }
  }

  void _fetchLyricsIfNeeded() {
    if (widget.song.id == _lastFetchedSongId) return;
    _lastFetchedSongId = widget.song.id;
    setState(() {
      _lyricsFuture = LyricsService.fetchLyrics(
        title: widget.song.title,
        artist: widget.song.artist,
        filePath: widget.song.path.isNotEmpty ? widget.song.path : null,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final largeCoverSize = (width - 44).clamp(260.0, 390.0).toDouble();
    final showLyrics = widget.showLyrics;

    return Padding(
      padding: const EdgeInsets.only(top: 25),
      child: Column(
        children: [
          // ─── Flexible top area: cover + song info + lyrics ────────────────
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final sw = constraints.maxWidth;
                final sh = constraints.maxHeight;

                // Normal-mode cover position: centred in the available space,
                // leaving ~80 px at the bottom for the song header.
                final coverLeft = (sw - largeCoverSize) / 2;
                final rawTop = (sh - largeCoverSize - 80) / 2 - 5;
                final coverTop = rawTop.clamp(8.0, 60.0);

                // Lyrics area starts just below the small thumbnail.
                const lyricsTop = _smallCoverSize + 30.0;

                return Stack(
                  clipBehavior: Clip.none,
                  children: [
                    // ── Song info — fades out in lyrics mode ──────────────
                    Positioned(
                      bottom: 26,
                      left: 22,
                      right: 22,
                      child: AnimatedOpacity(
                        duration: _animDuration,
                        curve: _animCurve,
                        opacity: showLyrics ? 0.0 : 1.0,
                        child: IgnorePointer(
                          ignoring: showLyrics,
                          child: PlayerSongHeader(song: widget.song),
                        ),
                      ),
                    ),
  
                    // ── Lyrics area — fades in in lyrics mode ─────────────
                    AnimatedPositioned(
  duration: const Duration(milliseconds: 250),
  curve: Curves.easeOut,
  top: lyricsTop,
  left: 0,
  right: 0,

  bottom: _lyricsExpand > 0 ? -250 : 0,

  child: AnimatedOpacity(
                        duration: _animDuration,
                        curve: _animCurve,
                        opacity: showLyrics ? 1.0 : 0.0,
                        child: IgnorePointer(
                          ignoring: !showLyrics,
                          child: _buildLyricsContent(),
                        ),
                      ),
                    ),

                    // ── Appearance button — fades in with lyrics ──────────
                    Positioned(
                      top: 16,
                      right: 22,
                      child: AnimatedOpacity(
                        duration: _animDuration,
                        curve: _animCurve,
                        opacity: showLyrics ? 1.0 : 0.0,
                        child: IgnorePointer(
                          ignoring: !showLyrics,
                          child: const _AppearanceButton(),
                        ),
                      ),
                    ),

                     Positioned(
  top: 14,
  left: 22 + _smallCoverSize + 12,
  right: 70,
  child: AnimatedOpacity(
    duration: _animDuration,
    curve: _animCurve,
    opacity: showLyrics ? 1.0 : 0.0,
    child: IgnorePointer(
      ignoring: !showLyrics,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            widget.song.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 17,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            widget.song.artist,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.55),
              fontSize: 13,
            ),
          ),
        ],
      ),
    ),
  ),
),
                    
                    // ── Album cover — AnimatedPositioned + AnimatedContainer
                    AnimatedPositioned(
                      duration: _animDuration,
                      curve: _animCurve,
                      top: showLyrics ? 8.0 : coverTop,
                      left: showLyrics ? 22.0 : coverLeft,
                      child: AnimatedContainer(
                        duration: _animDuration,
                        curve: _animCurve,
                        width: showLyrics ? _smallCoverSize : largeCoverSize,
                        height: showLyrics ? _smallCoverSize : largeCoverSize,
                        clipBehavior: Clip.antiAlias,
                        decoration: BoxDecoration(
                          borderRadius:
                              BorderRadius.circular(showLyrics ? 8 : 12),
                          color: Colors.black,
                        ),
                        child: FittedBox(
                          fit: BoxFit.cover,
                          child: SizedBox(
                            width: largeCoverSize,
                            height: largeCoverSize,
                            child: SongArtwork(
                              songId: widget.song.id,
                              size: largeCoverSize,
                              borderRadius: BorderRadius.zero,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),

          // ─── Fixed bottom controls ────────────────────────────────────────
 AnimatedOpacity(
  duration: const Duration(milliseconds: 250),
  opacity: 1.0 - _lyricsExpand,
  child: IgnorePointer(
    ignoring: _lyricsExpand > 0.0,
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Transform.translate(
          offset: const Offset(0, -24),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(22, 0, 22, 0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                PlayerProgressSection(
                  formatTime: widget.formatTime,
                ),
                const SizedBox(height: 47),
                PlayerTransportControls(
                  playbackState: widget.playbackState,
                ),
                const SizedBox(height: 40),
                PlayerSecondaryControls(
                  song: widget.song,
                  showLyrics: showLyrics,
                  onLyricsToggle: widget.onLyricsToggle,
                ),
                const SizedBox(height: 01),
              ],
            ),
          ),
        ),

        Container(
          width: double.infinity,
          height: 0.5,
          color: Colors.white.withValues(alpha: 0.08),
        ),
      ],
    ),
  ),
),
        
        ],
      ),
    );
  }

  Widget _buildLyricsContent() {
    return FutureBuilder<LyricsResult>(
      future: _lyricsFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(
            child: CircularProgressIndicator(
              color: Colors.white24,
              strokeWidth: 2,
            ),
          );
        }
        final result =
            snapshot.data ?? const LyricsResult([], LyricsSource.none);
        if (result.isEmpty) {
          return _EmptyLyricsOverlay(song: widget.song);
        }
        return _LyricsOverlayBody(
  result: result,
  onExpandChanged: (expanded) {
    if (_lyricsExpand == (expanded ? 1.0 : 0.0)) return;

    setState(() {
      _lyricsExpand = expanded ? 1.0 : 0.0;
    });
  },
);
      },
    );
  }
}

// ─── Lyrics body ─────────────────────────────────────────────────────────────

class _LyricsOverlayBody extends StatelessWidget {
  final LyricsResult result;
  final ValueChanged<bool> onExpandChanged;

  const _LyricsOverlayBody({
    required this.result,
    required this.onExpandChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        NotificationListener<UserScrollNotification>(
  onNotification: (notification) {
    final offset = notification.metrics.pixels;

    if (offset > 150) {
      onExpandChanged(true);
    } else if (offset < 50) {
      onExpandChanged(false);
    }

    return false;
  },
  child: ShaderMask(
    shaderCallback: (Rect rect) {
      return const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          Colors.transparent,
          Colors.white,
          Colors.white,
          Colors.transparent,
        ],
        stops: [
  0.0,
  0.35,
  0.65,
  1.0,
],
      ).createShader(rect);
    },
    blendMode: BlendMode.dstIn,
    child: SyncedLyricsView(
      lyrics: result.lines,
      padding: const EdgeInsets.fromLTRB(24, 8, 48, 24),
    ),
  ),
),
        ValueListenableBuilder<bool>(
          valueListenable: LyricsSettings.showSource,
          builder: (_, show, _) {
            if (!show || result.source == LyricsSource.none) {
              return const SizedBox.shrink();
            }
            return Positioned(
              bottom: 8,
              left: 24,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.12),
                    width: 0.5,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      result.source == LyricsSource.internet
                          ? CupertinoIcons.globe
                          : CupertinoIcons.doc_text,
                      color: Colors.white.withValues(alpha: 0.45),
                      size: 11,
                    ),
                    const SizedBox(width: 5),
                    Text(
                      result.sourceLabel,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.45),
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ],
    );
  }
}

// ─── Empty lyrics state ───────────────────────────────────────────────────────

class _EmptyLyricsOverlay extends StatelessWidget {
  final LocalSong song;
  const _EmptyLyricsOverlay({required this.song});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(CupertinoIcons.music_note,
                size: 48, color: Colors.white.withValues(alpha: 0.2)),
            const SizedBox(height: 16),
            Text(
              'Lirik tidak ditemukan',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.6),
                fontSize: 17,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '${song.title} · ${song.artist}',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.3),
                fontSize: 13,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Tambahkan file .lrc di folder yang sama\ndengan lagu, atau konfigurasikan folder\nlirik di Pengaturan.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.2),
                fontSize: 12,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Appearance button (circle icon, top-right in lyrics mode) ───────────────

class _AppearanceButton extends StatelessWidget {
  const _AppearanceButton();

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => _show(context),
      child: Container(
        width: 34,
        height: 34,
        decoration: const BoxDecoration(
          shape: BoxShape.circle,
          color: Color.fromARGB(90, 100, 100, 100),
        ),
        child: const Icon(
          Icons.more_vert_rounded,
          color: Colors.white,
          size: 20,
        ),
      ),
    );
  }

  void _show(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => const _LyricsAppearanceOverlay(),
    );
  }
}

// ─── Appearance settings sheet ────────────────────────────────────────────────

class _LyricsAppearanceOverlay extends StatelessWidget {
  const _LyricsAppearanceOverlay();

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
        child: Container(
          color: Colors.black.withValues(alpha: 0.75),
          child: SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 36,
                      height: 4,
                      decoration: BoxDecoration(
                        color: Colors.white24,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'Tampilan Lirik',
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 17,
                        fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 20),
                  _label('Ukuran Teks'),
                  const SizedBox(height: 8),
                  const _FontSizePicker(),
                  const SizedBox(height: 16),
                  _label('Rata Teks'),
                  const SizedBox(height: 8),
                  const _AlignPicker(),
                  const SizedBox(height: 16),
                  _label('Warna Aktif'),
                  const SizedBox(height: 8),
                  const _ColorPicker(),
                  const SizedBox(height: 16),
                  _label('Kegelapan Latar'),
                  const SizedBox(height: 4),
                  const _DimSlider(),
                  const SizedBox(height: 12),
                  _label('Kekuatan Blur'),
                  const SizedBox(height: 4),
                  const _BlurSlider(),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      const Expanded(
                        child: Text('Tampilkan Sumber Lirik',
                            style:
                                TextStyle(color: Colors.white, fontSize: 15)),
                      ),
                      ValueListenableBuilder<bool>(
                        valueListenable: LyricsSettings.showSource,
                        builder: (_, v, _) => CupertinoSwitch(
                          value: v,
                          onChanged: LyricsSettings.setShowSource,
                          activeTrackColor: const Color(0xFFF92D48),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  static Widget _label(String text) => Text(
        text,
        style: const TextStyle(
            color: Color(0xFF8E8E93),
            fontSize: 12,
            fontWeight: FontWeight.w500),
      );
}

// ─── Font size picker ─────────────────────────────────────────────────────────

class _FontSizePicker extends StatelessWidget {
  const _FontSizePicker();

  static const _sizes = [
  (label: 'S', value: 23.0),
  (label: 'M', value: 34.0),
  (label: 'L', value: 48.0),
  (label: 'XL', value: 55.0),
];

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<double>(
      valueListenable: LyricsSettings.fontSize,
      builder: (_, cur, _) => Row(
        children: _sizes.map((s) {
          final active = cur == s.value;
          return Expanded(
            child: GestureDetector(
              onTap: () => LyricsSettings.setFontSize(s.value),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                margin: const EdgeInsets.only(right: 8),
                height: 40,
                decoration: BoxDecoration(
                  color: active
                      ? const Color(0xFFF92D48)
                      : Colors.white.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(10),
                ),
                alignment: Alignment.center,
                child: Text(
                  s.label,
                  style: TextStyle(
                    color: active ? Colors.white : Colors.white54,
                    fontWeight:
                        active ? FontWeight.bold : FontWeight.normal,
                    fontSize: 14,
                  ),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}

// ─── Text-align picker ────────────────────────────────────────────────────────

class _AlignPicker extends StatelessWidget {
  const _AlignPicker();

  static const _opts = [
    (label: 'Kiri', icon: Icons.format_align_left, value: 'left'),
    (label: 'Tengah', icon: Icons.format_align_center, value: 'center'),
    (label: 'Kanan', icon: Icons.format_align_right, value: 'right'),
  ];

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<String>(
      valueListenable: LyricsSettings.textAlign,
      builder: (_, cur, _) => Row(
        children: _opts.map((o) {
          final active = cur == o.value;
          return Expanded(
            child: GestureDetector(
              onTap: () => LyricsSettings.setTextAlign(o.value),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                margin: const EdgeInsets.only(right: 8),
                height: 40,
                decoration: BoxDecoration(
                  color: active
                      ? const Color(0xFFF92D48)
                      : Colors.white.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(10),
                ),
                alignment: Alignment.center,
                child: Icon(o.icon,
                    color: active ? Colors.white : Colors.white54, size: 20),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}

// ─── Active-colour picker ─────────────────────────────────────────────────────

class _ColorPicker extends StatelessWidget {
  const _ColorPicker();

  static const _opts = [
    (label: 'Putih', color: Color(0xFFFFFFFF), value: 'white'),
    (label: 'Merah', color: Color(0xFFF92D48), value: 'accent'),
    (label: 'Kuning', color: Color(0xFFFFD60A), value: 'yellow'),
  ];

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<String>(
      valueListenable: LyricsSettings.activeColor,
      builder: (_, cur, _) => Row(
        children: _opts.map((o) {
          final active = cur == o.value;
          return Expanded(
            child: GestureDetector(
              onTap: () => LyricsSettings.setActiveColor(o.value),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                margin: const EdgeInsets.only(right: 8),
                height: 40,
                decoration: BoxDecoration(
                  color: active
                      ? o.color
                      : Colors.white.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(10),
                  border: active
                      ? null
                      : Border.all(
                          color: o.color.withValues(alpha: 0.4), width: 1),
                ),
                alignment: Alignment.center,
                child: Text(
                  o.label,
                  style: TextStyle(
                    color: active ? Colors.white : Colors.white54,
                    fontSize: 13,
                    fontWeight:
                        active ? FontWeight.bold : FontWeight.normal,
                  ),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}

// ─── Dim slider ───────────────────────────────────────────────────────────────

class _DimSlider extends StatelessWidget {
  const _DimSlider();

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<double>(
      valueListenable: LyricsSettings.bgDim,
      builder: (_, v, _) => Row(
        children: [
          const Icon(Icons.brightness_high, color: Colors.white38, size: 16),
          Expanded(
            child: Slider(
              value: v,
              min: 0.2,
              max: 0.95,
              divisions: 15,
              activeColor: const Color(0xFFF92D48),
              inactiveColor: Colors.white12,
              onChanged: LyricsSettings.setBgDim,
            ),
          ),
          const Icon(Icons.brightness_low, color: Colors.white38, size: 16),
        ],
      ),
    );
  }
}

// ─── Blur slider ──────────────────────────────────────────────────────────────

class _BlurSlider extends StatelessWidget {
  const _BlurSlider();

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<double>(
      valueListenable: LyricsSettings.blurStrength,
      builder: (_, v, _) => Row(
        children: [
          const Icon(CupertinoIcons.photo, color: Colors.white38, size: 16),
          Expanded(
            child: Slider(
              value: v,
              min: 0,
              max: 50,
              divisions: 10,
              activeColor: const Color(0xFFF92D48),
              inactiveColor: Colors.white12,
              onChanged: LyricsSettings.setBlurStrength,
            ),
          ),
          const Icon(Icons.blur_on, color: Colors.white38, size: 16),
        ],
      ),
    );
  }
}
