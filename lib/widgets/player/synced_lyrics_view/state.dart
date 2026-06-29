part of '../synced_lyrics_view.dart';

class _SyncedLyricsViewState extends State<SyncedLyricsView>
    with TickerProviderStateMixin {
  final ScrollController _scroll = ScrollController();
  ScrollController get _eff => widget.controller ?? _scroll;
  int _currentIndex = 0;

  // GlobalKey per item untuk centering berbasis render-object.
  final Map<int, GlobalKey> _itemKeys = {};

  // Guard: mencegah scroll callbacks bertumpuk.
  // Tidak memblokir perubahan baris — hanya debounce scroll.
  bool _scrollPending = false;

  // ── AnimationController sebagai value-notifier untuk AnimatedBuilder ────
  // TIDAK pernah dipanggil animateTo() — nilainya di-set langsung setiap
  // vsync frame dari posisi playback yang diinterpolasi. Dengan demikian
  // sweep karaoke 100% mengikuti posisi real-time, tanpa drift sama sekali.
  late final AnimationController _charCtrl;

  // ── Anchor posisi (sumber kebenaran tunggal) ─────────────────────────────
  // Di-update setiap event positionStream (~200 ms dari native ticker).
  // _frameTicker menginterpolasi antara anchor events untuk kelancaran 60 fps.
  Duration _anchorPos   = Duration.zero;
  int      _anchorWallMs = 0;   // DateTime.now().millisecondsSinceEpoch saat anchor di-set
  bool     _isPlaying   = false;
  double   _speed       = 1.0;

  // ── Vsync ticker untuk sweep karaoke 60 fps ──────────────────────────────
  // Membaca _anchorPos + elapsed wall-clock * speed pada setiap frame.
  // Mengeliminasi semua animasi free-running dan drift berbasis timer.
  late final Ticker _frameTicker;

  StreamSubscription<Duration>? _posSub;

  @override
  void initState() {
    super.initState();
    _charCtrl    = AnimationController(vsync: this);
    _frameTicker = createTicker(_onFrameTick);

    // Inisialisasi anchor dari state saat ini sehingga ketika halaman lirik
    // dibuka di tengah lagu, posisi sweep langsung benar (bukan mulai dari 0).
    final s = AudioService.playbackState.value;
    _syncFromPlaybackState(s);
    _anchorPos    = s.position;
    _anchorWallMs = DateTime.now().millisecondsSinceEpoch;

    // Hitung baris aktif awal tanpa setState (belum ada frame build pertama).
    if (widget.lyrics.isNotEmpty) {
      final pos = s.position;
      int lo = 0, hi = widget.lyrics.length - 1;
      while (lo <= hi) {
        final mid = (lo + hi) >> 1;
        if (widget.lyrics[mid].timestamp <= pos) {
          _currentIndex = mid;
          lo = mid + 1;
        } else {
          hi = mid - 1;
        }
      }
    }

    // Mulai ticker langsung jika sedang playing.
    if (_isPlaying) _frameTicker.start();

    // Dengarkan posisi (sumber utama re-anchoring & pergantian baris).
    _posSub = AudioService.positionStream.listen(_onPosition);

    // Dengarkan perubahan playback state untuk isPlaying dan speed.
    AudioService.playbackState.addListener(_onPlaybackState);

    WidgetsBinding.instance.addPostFrameCallback((_) {
  if (!mounted) return;
  _scrollToCenter(_currentIndex);
}); 
  }

  @override
  void didUpdateWidget(SyncedLyricsView old) {
    super.didUpdateWidget(old);
    if (old.lyrics != widget.lyrics) {
      _itemKeys.clear();
      _currentIndex   = 0;
      _scrollPending  = false;
      _charCtrl.value = 0.0;
      // Anchor di-reset; ticker akan kembali ke posisi 0 sampai event berikutnya.
      _anchorPos    = Duration.zero;
      _anchorWallMs = DateTime.now().millisecondsSinceEpoch;
    }
  }

  @override
  void dispose() {
    _posSub?.cancel();
    AudioService.playbackState.removeListener(_onPlaybackState);
    _frameTicker.dispose();
    _charCtrl.dispose();
    if (widget.controller == null) _scroll.dispose();
    super.dispose();
  }

  // ── Sync playback state ───────────────────────────────────────────────────

  void _syncFromPlaybackState(AudioPlaybackState s) {
    _isPlaying = s.isPlaying;
    _speed     = s.speed.clamp(0.1, 4.0);
  }

  void _onPlaybackState() {
    final s = AudioService.playbackState.value;
    final wasPlaying = _isPlaying;
    _syncFromPlaybackState(s);

    if (_isPlaying) {
      // Mulai/lanjutkan ticker jika belum aktif.
      if (!_frameTicker.isActive) _frameTicker.start();
    } else {
      // Pause: hentikan ticker dan bekukan sweep tepat di posisi saat ini.
      if (_frameTicker.isActive) _frameTicker.stop();
      // Re-anchor ke posisi pause sehingga resume dimulai dari titik yang benar.
      if (wasPlaying) {
        _anchorPos    = s.position;
        _anchorWallMs = DateTime.now().millisecondsSinceEpoch;
        // Update sweep karaoke ke posisi freeze.
        _updateKaraokeProgress(s.position);
      }
    }
  }

  // ── Penanganan position stream (sumber kebenaran tunggal) ─────────────────

  void _onPosition(Duration position) {
    // Re-anchor ke posisi nyata setiap ~200 ms.
    _anchorPos    = position;
    _anchorWallMs = DateTime.now().millisecondsSinceEpoch;
    _isPlaying    = true;

    // Pastikan frame ticker berjalan.
    if (!_frameTicker.isActive) _frameTicker.start();

    // Hitung ulang baris aktif langsung dari posisi nyata.
    // Ini memastikan seek/skip/replay/crossfade langsung melompat ke baris yang benar.
    final oldIndex = _currentIndex;
_maybeUpdateCurrentLine(position);

if (oldIndex == _currentIndex && _eff.hasClients && _eff.offset == 0) {
  _scrollToCenter(_currentIndex);
}
  }

  // ── Vsync tick (60 fps) ───────────────────────────────────────────────────

  void _onFrameTick(Duration _) {
    if (!mounted || widget.lyrics.isEmpty) return;
    _updateKaraokeProgress(_interpolatedPosition);
  }

  /// Menginterpolasi posisi playback saat ini dari anchor terakhir dan
  /// wall-clock elapsed, dikalikan playback speed.
  ///
  /// Ini memberi kelancaran 60 fps di antara event positionStream (200 ms),
  /// sekaligus tetap ter-anchor ke posisi nyata — tidak ada drift.
  Duration get _interpolatedPosition {
    if (!_isPlaying) return _anchorPos;
    final wallElapsedMs  = DateTime.now().millisecondsSinceEpoch - _anchorWallMs;
    final audioElapsedMs = (wallElapsedMs * _speed).round();
    return _anchorPos + Duration(milliseconds: audioElapsedMs);
  }

  // ── Perhitungan baris aktif ───────────────────────────────────────────────

  /// Binary-search baris lirik aktif; memanggil setState + scroll ketika
  /// baris berubah. Perubahan baris TIDAK PERNAH diblokir oleh _scrollPending —
  /// hanya scroll yang di-debounce untuk menghindari penumpukan callback.
  void _maybeUpdateCurrentLine(Duration position) {
    if (widget.lyrics.isEmpty) return;

    int lo = 0, hi = widget.lyrics.length - 1, activeIndex = 0;
    while (lo <= hi) {
      final mid = (lo + hi) >> 1;
      if (widget.lyrics[mid].timestamp <= position) {
        activeIndex = mid;
        lo = mid + 1;
      } else {
        hi = mid - 1;
      }
    }

    if (activeIndex == _currentIndex) return;

    // Perbarui baris aktif dan reset sweep karaoke untuk baris baru.
    _currentIndex   = activeIndex;
    _charCtrl.value = 0.0;

    if (mounted) setState(() {});

    // Debounce scroll: kalau scroll sudah dijadwalkan, biarkan callback itu
    // menggunakan _currentIndex terbaru saat ia berjalan.
    if (!_scrollPending) {
      _scrollPending = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _scrollPending = false;
        if (!mounted) return;
        _scrollToCenter(_currentIndex);
      });
    }
  }

  // ── Progress sweep karaoke ────────────────────────────────────────────────

  /// Menghitung progress sweep (0.0 → 1.0) dari posisi playback yang
  /// diinterpolasi dan meng-assign langsung ke _charCtrl.value.
  ///
  /// Tidak ada animateTo(), tidak ada Timer — murni position-driven.
  void _updateKaraokeProgress(Duration position) {
    if (widget.lyrics.isEmpty) return;
    final idx = _currentIndex;
    if (idx >= widget.lyrics.length) return;

    final lineStart = widget.lyrics[idx].timestamp;
    final lineEnd   = (idx + 1 < widget.lyrics.length)
        ? widget.lyrics[idx + 1].timestamp
        : lineStart + const Duration(seconds: 5);

    final double totalMs =
        (lineEnd - lineStart).inMilliseconds.toDouble();
    if (totalMs <= 0) {
      _charCtrl.value = 1.0;
      return;
    }

    final double elapsedMs =
        (position - lineStart).inMilliseconds.toDouble().clamp(0.0, totalMs);
    final double progress = elapsedMs / totalMs;

    // Set langsung — tidak ada free-running animation, tidak ada drift.
    // Threshold kecil (0.5 ms setara dalam skala 0–1) untuk menghindari
    // notifikasi yang tidak perlu saat nilai hampir identik.
    final double threshold = 0.5 / totalMs;
    if ((_charCtrl.value - progress).abs() > threshold) {
      _charCtrl.value = progress;
    }
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<double>(
      valueListenable: LyricsSettings.fontSize,
      builder: (_, fs, _) => ValueListenableBuilder<String>(
        valueListenable: LyricsSettings.textAlign,
        builder: (_, __, _) => ValueListenableBuilder<String>(
          valueListenable: LyricsSettings.activeColor,
          builder: (_, ___, _) {
            final activeColor = LyricsSettings.resolvedActiveColor;
            final textAlign   = LyricsSettings.resolvedTextAlign;
            final dimColor    = Colors.white.withValues(alpha: 0.35);

            return ListView.builder(
              controller: _eff,
              padding: widget.padding,
              dragStartBehavior: DragStartBehavior.down,
              itemCount: widget.lyrics.length,
              itemBuilder: (context, index) {
                final itemKey = _itemKeys.putIfAbsent(index, GlobalKey.new);
                final active  = index == _currentIndex;

                return GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () =>
                      AudioService.seek(widget.lyrics[index].timestamp),
                  child: Padding(
                    key: itemKey,
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    // AnimatedDefaultTextStyle menangani transisi warna saat
                    // baris menjadi tidak aktif. Baris aktif menggunakan
                    // RichText eksplisit (per-karakter), sehingga ADTS tidak
                    // berpengaruh secara visual selama sweep karaoke berjalan.
                    child: AnimatedDefaultTextStyle(
                      duration: const Duration(milliseconds: 380),
                      curve: Curves.easeOutCubic,
                      style: TextStyle(
                        fontSize: fs,
                        fontWeight: FontWeight.bold,
                        color: active ? activeColor : dimColor,
                        height: 1.4,
                      ),
                      child: active
                          // ── Baris aktif: sweep karaoke per-karakter ────────
                          // AnimatedBuilder hanya me-rebuild widget INI di 60 fps.
                          // Semua baris lain tidak tersentuh oleh tick _charCtrl.
                          ? AnimatedBuilder(
                              animation: _charCtrl,
                              builder: (_, __) => _buildKaraokeText(
                                widget.lyrics[index].text,
                                _charCtrl.value,
                                activeColor,
                                dimColor,
                                fs,
                                textAlign,
                              ),
                            )
                          // ── Baris tidak aktif: teks biasa ──────────────────
                          : Text(
                              widget.lyrics[index].text,
                              textAlign: textAlign,
                            ),
                    ),
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }

  // ── Renderer teks karaoke ─────────────────────────────────────────────────

  /// Mengembalikan [RichText] di mana karakter menyala kiri-ke-kanan seiring
  /// [progress] berjalan 0 → 1. Batas antara karakter yang menyala dan redup
  /// bergerak secara sub-karakter: karakter di batas mendapat warna yang
  /// diinterpolasi sehingga sweep terlihat mulus pada frame rate apa pun.
  Widget _buildKaraokeText(
    String text,
    double progress,
    Color activeColor,
    Color dimColor,
    double fontSize,
    TextAlign textAlign,
  ) {
    final chars = text.characters.toList(); // Split Unicode-safe
    final int total = chars.length;
    if (total == 0) return const SizedBox.shrink();

    // Berapa karakter yang "tercakup" oleh sweep (bisa fraksional).
    final double covered = progress * total;

    return RichText(
      textAlign: textAlign,
      text: TextSpan(
        children: List.generate(total, (i) {
          // charProgress: 0 = sepenuhnya redup, 1 = sepenuhnya aktif.
          // Pada karakter batas ini fraksional → tepi yang mulus.
          final double charProgress = (covered - i).clamp(0.0, 1.0);
          return TextSpan(
            text: chars[i],
            style: TextStyle(
              fontSize: fontSize,
              fontWeight: FontWeight.bold,
              color: Color.lerp(dimColor, activeColor, charProgress),
              height: 1.4,
            ),
          );
        }),
      ),
    );
  }

  // ── Centering ─────────────────────────────────────────────────────────────

  /// Scroll agar baris aktif berada di tengah bagian viewport yang *terlihat*.
  /// Menggunakan aritmetika koordinat layar untuk menangani viewport yang
  /// overflow ke bawah layar (misalnya bottom: -200 di overlay player).
  void _scrollToCenter(int index) {
    if (!_eff.hasClients) return;

    final key = _itemKeys[index];

if (key == null || key.currentContext == null) {
  WidgetsBinding.instance.addPostFrameCallback((_) {
    if (!mounted) return;
    _scrollToCenter(index);
  });
  return;
}

    final RenderObject? renderObj = key.currentContext!.findRenderObject();

if (renderObj == null || renderObj is! RenderBox) {
  WidgetsBinding.instance.addPostFrameCallback((_) {
    if (!mounted) return;
    _scrollToCenter(index);
  });
  return;
}
    final RenderAbstractViewport? viewport =
    RenderAbstractViewport.of(renderObj);

if (viewport == null || viewport is! RenderBox) {
  WidgetsBinding.instance.addPostFrameCallback((_) {
    if (!mounted) return;
    _scrollToCenter(index);
  });
  return;
}
    final RenderBox viewportBox = viewport as RenderBox;

    final double itemMidY =
        renderObj.localToGlobal(Offset(0, renderObj.size.height / 2)).dy;

    final double screenH   = MediaQuery.of(context).size.height;
    final double vpTop     = viewportBox.localToGlobal(Offset.zero).dy;
    final double vpBottom  = vpTop + viewportBox.size.height;
    final double visTop    = vpTop.clamp(0.0, screenH);
    final double visBottom = vpBottom.clamp(0.0, screenH);
    final double visCenter = (visTop + visBottom) / 2;

    final double delta  = itemMidY - visCenter;
    final double target = (_eff.offset + delta).clamp(
      _eff.position.minScrollExtent,
      _eff.position.maxScrollExtent,
    );

    if ((target - _eff.offset).abs() < 1.0) return;

    _eff.animateTo(
      target,
      duration: const Duration(milliseconds: 380),
      curve: Curves.easeOutCubic,
    );
  }

  void _scrollToCenterFallback(int index) {
    if (!_eff.hasClients) return;
    final fs = LyricsSettings.fontSize.value;
    final double approxHeight = fs * 1.4 + 12.0;
    final double topPad = widget.padding.resolve(TextDirection.ltr).top;
    final double vpHalf = _eff.position.viewportDimension / 2;
    final double target =
        (index * approxHeight + topPad - vpHalf + approxHeight / 2).clamp(
      _eff.position.minScrollExtent,
      _eff.position.maxScrollExtent,
    );

    if ((target - _eff.offset).abs() < 1.0) return;
    _eff.animateTo(
      target,
      duration: const Duration(milliseconds: 380),
      curve: Curves.easeOutCubic,
    );
  }
}
