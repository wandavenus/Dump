import 'dart:ui';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';

import '../models/local_song.dart';
import '../theme/app_colors.dart';
import '../services/audio_playback_state.dart';
import '../services/audio_service.dart';
import '../services/artwork_repository.dart';
import '../services/player_sheet_controller.dart';
import '../themes/glass_navbar.dart';
import '../themes/theme_controller.dart';
import 'player/now_playing_layout.dart';
import 'player/player_background.dart';
import 'player/player_content.dart';
import 'player/player_hero_tags.dart';
import 'song_artwork.dart';

// Part files (same library — private types shared):
//   unified_morph_player/playback_content.dart   → _PlaybackContent
//   unified_morph_player/bottom_reveal_clipper.dart → _BottomRevealClipper
part 'unified_morph_player/playback_content.dart';
part 'unified_morph_player/bottom_reveal_clipper.dart';

class UnifiedMorphPlayer extends StatefulWidget {
  const UnifiedMorphPlayer({super.key});

  @override
  State<UnifiedMorphPlayer> createState() => _UnifiedMorphPlayerState();
}

class _UnifiedMorphPlayerState extends State<UnifiedMorphPlayer>
    with TickerProviderStateMixin {
  // ── Gesture state ──────────────────────────────────────────────────────────

  // ── Full-player sub-view state ─────────────────────────────────────────────
  bool _showLyrics = false;
  bool _showQueue = false;

  // ── Overlay artwork transition animation ───────────────────────────────────
  // Drives artwork from large full-player position → small thumbnail position.
  // 0.0 = full player, 1.0 = overlay thumbnail
  late final AnimationController _overlayAnim;

  // ── Release animation ──────────────────────────────────────────────────────
  late final AnimationController _releaseAnim;
  double _animStartVal = 0.0;
  double _animTarget = 0.0;

  // ── Entry animation — slide-up when mini player first appears ──────────────
  late final AnimationController _entryAnim;

  // ── Playback-derived state (updated by listener, NOT by VLB in build) ──────
  // Only setState when these values change — not on every position tick.
  LocalSong? _currentSong;
  bool _isPlaying = false;

  // True while the reverse entry animation (session end / notification STOP)
  // is playing. The last song stays rendered until the animation completes
  // (_entryAnim reaches dismissed), then _currentSong is nulled so the widget
  // unmounts. A new song arriving mid-exit cancels it and slides back up.
  bool _exiting = false;

  // ── Lifecycle ──────────────────────────────────────────────────────────────
  @override
  void initState() {
    super.initState();
    _overlayAnim = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 420),
    );
    _releaseAnim = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 380),
    )..addListener(_onReleaseAnimTick);
    _entryAnim = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 420),
    )..addStatusListener(_onEntryStatusChanged);
    PlayerSheetController.expanded.addListener(_onExpandedChanged);
    // Single listener replaces the old _onSongAppeared + playbackState VLB.
    // Only setState when song identity or isPlaying changes — never on position ticks.
    AudioService.playbackState.addListener(_onPlaybackStateChanged);
    // Initialise fields from current state (in case widget mounts mid-playback,
    // e.g. Activity recreation while Media3 is still playing).
    _currentSong = AudioService.playbackState.value.currentSong;
    _isPlaying = AudioService.playbackState.value.isPlaying;
    // If a song is already active on mount (restored session / Activity recreation),
    // play the same slide-up entry animation as when a song first appears during
    // a fresh session. Without this, _entryAnim stays at 0.0 → entrySlide ≈ 120 px
    // → bottom is negative → mini player is hidden below the screen until the next
    // playback event fires (which never comes if nothing changes).
    if (_currentSong != null) {
      final song = _currentSong!;
      unawaited(
        _prewarmEntryArtwork(song).then((_) {
          if (mounted && _currentSong?.id == song.id) {
            unawaited(_entryAnim.forward(from: 0.0));
          }
        }),
      );
    }
  }

  Future<void> _prewarmEntryArtwork(LocalSong song) async {
    final repo = ArtworkRepository.instance;
    final targetPx = repo.resolveTargetPx(46.3);

    final provider = repo.getProviderSync(song.id, targetSizePx: targetPx);

    if (provider == null) return;

    final completer = Completer<void>();
    final stream = provider.resolve(ImageConfiguration.empty);

    late final ImageStreamListener listener;
    listener = ImageStreamListener(
      (_, _) {
        stream.removeListener(listener);
        if (!completer.isCompleted) completer.complete();
      },
      onError: (_, _) {
        stream.removeListener(listener);
        if (!completer.isCompleted) completer.complete();
      },
    );

    stream.addListener(listener);

    await completer.future.timeout(
      const Duration(milliseconds: 3000),
      onTimeout: () {},
    );
  }

  @override
  void dispose() {
    _overlayAnim.dispose();
    _releaseAnim.dispose();
    _entryAnim.dispose();
    AudioService.playbackState.removeListener(_onPlaybackStateChanged);
    PlayerSheetController.expanded.removeListener(_onExpandedChanged);
    super.dispose();
  }

  // ── Playback state listener ────────────────────────────────────────────────
  // Runs on every AudioService.playbackState notification (including position
  // ticks every ~100 ms). Only triggers a setState when song identity or
  // isPlaying actually changes — position ticks are silently ignored.
  void _onPlaybackStateChanged() {
    final state = AudioService.playbackState.value;
    final song = state.currentSong;
    final isPlaying = state.isPlaying;

    var needsRebuild = false;

    // Song identity changed (including null → non-null and vice-versa).
    final songChanged =
        (_currentSong == null) != (song == null) ||
        (_currentSong?.id != song?.id);

    if (songChanged) {
      final hadPreviousSong = _currentSong != null;

      if (hadPreviousSong && song == null) {
        // Session ended (notification STOP): keep the last song rendered while
        // the reverse entry animation plays; _currentSong is nulled on
        // completion so the mini player unmounts cleanly.
        _startExitAnimation();
        needsRebuild = true;
      } else if (!hadPreviousSong && song != null) {
        // First song of a session — cancel any in-progress exit and slide up.
        _cancelExit();
        _currentSong = song;
        needsRebuild = true;
        final appearedSong = song;

        unawaited(
          _prewarmEntryArtwork(appearedSong).then((_) {
            if (mounted && _currentSong?.id == appearedSong.id && !_exiting) {
              unawaited(_entryAnim.forward(from: 0.0));
            }
          }),
        );
      } else {
        // Direct song A → song B switch. Also covers a new song interrupting
        // an in-progress exit — restart the slide-up from zero so the player
        // doesn't stay at a partially-hidden position.
        final wasExiting = _exiting;
        _cancelExit();
        _currentSong = song;
        needsRebuild = true;
        if (wasExiting) {
          unawaited(_entryAnim.forward(from: 0.0));
        }
      }
    }

    // Play / Pause state changed.
    if (_isPlaying != isPlaying) {
      _isPlaying = isPlaying;
      needsRebuild = true;
    }

    if (needsRebuild && mounted) {
      setState(() {});
    }
  }

  void _onReleaseAnimTick() {
    // easeOutCubic applied in listener so we drive the raw controller linearly
    final u = 1.0 - _releaseAnim.value;
    final eased = 1.0 - u * u * u;
    final value = _animStartVal + (_animTarget - _animStartVal) * eased;
    PlayerSheetController.setProgress(value.clamp(0.0, 1.0));
  }

  // ── Exit animation (session end / notification STOP) ───────────────────────

  /// Plays the reverse of the entry slide-up: the mini player slides back down
  /// below the nav bar. The widget unmounts only after the animation completes
  /// (see [_onEntryStatusChanged]).
  void _startExitAnimation() {
    _exiting = true;
    // Collapse any open full player first so the exit is a clean mini-player
    // slide-down, and the next session starts from the collapsed mini state.
    PlayerSheetController.setProgress(0.0);
    unawaited(_entryAnim.reverse());
  }

  /// Aborts an in-progress exit (e.g. a new song starts). The entry controller
  /// keeps its current value; callers restart the slide-up explicitly.
  void _cancelExit() {
    if (_exiting) {
      _exiting = false;
      _entryAnim.stop();
    }
  }

  void _onEntryStatusChanged(AnimationStatus status) {
    // Reverse animation finished → the mini player is fully hidden below the
    // screen; drop the last song so build() unmounts the widget.
    if (status == AnimationStatus.dismissed && _exiting) {
      _exiting = false;
      if (mounted) {
        setState(() => _currentSong = null);
      }
    }
  }

  void _animateTo(double target) {
    // Cancel any timer-based animation running in the controller
    PlayerSheetController.cancelAnimation();
    _releaseAnim.stop();

    _animStartVal = PlayerSheetController.progress.value;
    _animTarget = target;

    final distance = (_animTarget - _animStartVal).abs();
    if (distance < 0.001) {
      PlayerSheetController.setProgress(target);
      return;
    }

    // Duration proportional to remaining travel — feels natural on flings
    // ×1.5 vs original: hero artwork 50% lebih lambat.
    final durationMs = (distance * 600).clamp(120.0, 600.0).toInt();
    _releaseAnim.duration = Duration(milliseconds: durationMs);
    _releaseAnim.value = 0.0;
    unawaited(_releaseAnim.animateTo(1.0, curve: Curves.linear));
  }

  void _onExpandedChanged() {
    if (!PlayerSheetController.expanded.value) {
      if (_showLyrics || _showQueue) {
        setState(() {
          _showLyrics = false;
          _showQueue = false;
        });
      }
      _overlayAnim.value = 0.0;
    }
  }

  // ── Helpers ────────────────────────────────────────────────────────────────
  String _formatTime(Duration d) {
    final m = d.inMinutes;
    final s = d.inSeconds % 60;
    return '$m:${s.toString().padLeft(2, '0')}';
  }

  void _toggleLyrics() {
    final wasOverlay = _showLyrics || _showQueue;
    setState(() {
      _showLyrics = !_showLyrics;
      if (_showLyrics) _showQueue = false;
    });
    final isOverlay = _showLyrics || _showQueue;
    if (!wasOverlay && isOverlay) {
      unawaited(_overlayAnim.forward());
    } else if (wasOverlay && !isOverlay) {
      unawaited(_overlayAnim.reverse());
    }
  }

  void _toggleQueue() {
    final wasOverlay = _showLyrics || _showQueue;
    setState(() {
      _showQueue = !_showQueue;
      if (_showQueue) _showLyrics = false;
    });
    final isOverlay = _showLyrics || _showQueue;
    if (!wasOverlay && isOverlay) {
      unawaited(_overlayAnim.forward());
    } else if (wasOverlay && !isOverlay) {
      unawaited(_overlayAnim.reverse());
    }
  }

  // ── Gesture callbacks ──────────────────────────────────────────────────────
  // Horizontal swipes are intentionally ignored. Vertical dragging still
  // expands/collapses the unified player.
  void _onPanStart(DragStartDetails d) {
    PlayerSheetController.cancelAnimation();
    _releaseAnim.stop();
  }

  void _onPanUpdate(DragUpdateDetails d) {
    if (_showLyrics || _showQueue) return;
    final sh = MediaQuery.sizeOf(context).height;
    final delta = -d.delta.dy / (sh * 0.55);
    PlayerSheetController.setProgress(
      (PlayerSheetController.progress.value + delta).clamp(0.0, 1.0),
    );
  }

  void _onPanEnd(DragEndDetails d) {
    final progress = PlayerSheetController.progress.value;
    if (!(_showLyrics || _showQueue)) {
      final vy = d.velocity.pixelsPerSecond.dy;
      if (vy > 500 || (progress <= 0.35 && vy >= 0)) {
        _animateTo(0.0);
      } else if (progress > 0.35 || vy < -200) {
        _animateTo(1.0);
      } else {
        _animateTo(0.0);
      }
    }
  }

  // ── Build ──────────────────────────────────────────────────────────────────
  // Chain: glassTheme VLB → entryAnim AB → progress VLB → _buildMorph
  //
  // AudioService.playbackState is NO LONGER in the VLB chain.
  // Only song-identity and isPlaying changes trigger setState() here.
  // Position ticks (~100 ms) are absorbed by the listener without rebuilding
  // this widget or any layout geometry.
  @override
  Widget build(BuildContext context) {
    // Guard: no song → nothing to render.
    final song = _currentSong;
    if (song == null) return const SizedBox.shrink();

    return ValueListenableBuilder<bool>(
      valueListenable: ThemeController.glassTheme,
      builder: (context, isGlass, _) {
        return ValueListenableBuilder<NavBarStyle>(
          valueListenable: ThemeController.navBarStyle,
          builder: (context, navStyle, _) {
            return ValueListenableBuilder<PlayerBackgroundStyle>(
              valueListenable: ThemeController.playerBackgroundStyle,
              builder: (context, backgroundStyle, _) {
                return AnimatedBuilder(
                  animation: _entryAnim,
                  builder: (context, _) {
                    return ValueListenableBuilder<double>(
                      valueListenable: PlayerSheetController.progress,
                      builder: (context, progress, _) {
                        return _buildMorph(
                          context,
                          song,
                          progress,
                          isGlass,
                          navStyle,
                          backgroundStyle,
                        );
                      },
                    );
                  },
                );
              },
            );
          },
        );
      },
    );
  }

  Widget _buildMorph(
    BuildContext context,
    LocalSong song,
    double progress,
    bool isGlass,
    NavBarStyle navStyle,
    PlayerBackgroundStyle backgroundStyle,
  ) {
    final mq = MediaQuery.of(context);
    final screenH = mq.size.height;
    final screenW = mq.size.width;
    final safeBottom = mq.padding.bottom;
    final safeTop = mq.padding.top;

    const miniH = kMiniPlayerHeight;
    // Mode pill (iOS 26): mini player ikut berubah menjadi kapsul apung —
    // margin kiri/kanan sama dengan navbar dan mengambang dengan gap di atas
    // kapsul navbar (tidak menempel). Mode lain: full-width, flush di bar.
    final isPill = isGlass && navStyle == NavBarStyle.pill;
    final miniHorizMargin = isPill ? FloatingPillNavBar.horizMargin : 0.0;
    final miniBottomGap = isPill ? FloatingPillNavBar.miniPlayerGap : 0.0;
    // Kapsul penuh saat mini (mode pill); 0 = persegi (mode lain / full player).
    final miniRadius = isPill ? miniH / 2 : 0.0;
    // Default mode has a 1.5px separator strip above the navBar (total column = 71.5px).
    // Glass mode omits the separator (total column = 70px), so navBar top sits 1.5px
    // lower — offset navBarH down by the same amount so mini player stays flush.
    // useGlassNavBar mengikuti state.dart: glass strip HANYA saat gaya != solid.
    // Kalau glassTheme on tapi gaya solid, bar tetap kolom solid 71.5px — pakai
    // navBarH 55.1, kalau tidak mini player menimpa bagian atas bar solid.
    final useGlassNavBar = isGlass && navStyle != NavBarStyle.solid;
    final navBarH = isPill
        ? FloatingPillNavBar.bodyHeight + FloatingPillNavBar.bottomGap
        : (useGlassNavBar ? 53.8 : 55.1);

    // Eased curve for Apple-Music–like deceleration
    final t = Curves.easeOutCubic.transform(progress);

    // ── Entry slide-up animation ─────────────────────────────────────────────
    // Mini player starts fully hidden below the screen's bottom edge (i.e.
    // entirely behind/inside the bottom nav bar, not just at bottom:0 which
    // would still let its top edge peek above the bar) and slides straight up
    // to its resting spot above the nav bar — no fade, pure slide.
    final easedEntry = Curves.easeOutCubic.transform(_entryAnim.value);
    final baseBottom = navBarH + safeBottom + miniBottomGap;
    final entrySlide = (baseBottom + miniH) * (1.0 - easedEntry);

    final bottom =
        lerpDouble(navBarH + safeBottom + miniBottomGap, 0.0, t)! - entrySlide;

    // Reveal boundary: while collapsed (t == 0, i.e. not expanding into the
    // full player), clip away anything at/below the nav bar's top edge so the
    // mini player can only ever be visible above that line — this is what
    // makes it look like it emerges from behind/inside the bar as it slides
    // up, instead of momentarily poking out below the bar's top edge. Fully
    // relaxes to full-screen the moment the user starts expanding the sheet,
    // so it never interferes with the full-player view.
    final clipVisibleHeight = t > 0.0 ? screenH : (screenH - baseBottom);
    final horizMargin = lerpDouble(miniHorizMargin, 0.0, t)!;
    final height = lerpDouble(miniH, screenH, t)!;
    // Border radius: kapsul penuh saat mini (mode pill), menyusut ke 0
    // mengikuti ekspansi sheet (full player = layar penuh persegi).
    final radius = lerpDouble(miniRadius, 0.0, t)!;

    // Cross-fade timing
    final miniAlpha = (1.0 - progress / 0.28).clamp(0.0, 1.0);
    final fullAlpha = ((progress - 0.12) / 0.38).clamp(0.0, 1.0);
    final bgAlpha = (progress / 0.35).clamp(0.0, 1.0);

    // ── Artwork morph positions ──────────────────────────────────────────────
    const miniArtSize = 46.3;
    // Mode pill: artwork digeser 10px ke kanan (12 → 22) agar sejajar dengan
    // judul yang ikut bergeser di _buildMiniOverlay. Mode lain tetap 12.
    final miniArtLeft = isPill ? 22.0 : 12.0;
    const miniArtTop = (miniH - miniArtSize) / 2; // = 9 px

    // ── Full-player artwork target ───────────────────────────────────────────
    // On a wide window the full player switches to its two-column layout
    // (artwork left / controls right) and PlayerContent places its artwork slot
    // via the very same [nowPlayingColumns] geometry, so the morphing artwork
    // lands exactly on that slot. Narrower windows keep the stacked geometry
    // below, unchanged.
    final wideColumns = useTwoColumnNowPlaying(mq.size)
        ? nowPlayingColumns(
            size: mq.size,
            safeTop: safeTop,
            safeBottom: safeBottom,
          )
        : null;

    final isArtworkBlurStyle =
        backgroundStyle == PlayerBackgroundStyle.artworkBlur;

    // Keep the main cover close to the top and nearly edge-to-edge in artwork-blur
    // mode. On shorter portrait screens, cap its size so its fade still ends well
    // above the song title instead of colliding with the header.
    const bottomCtrlH = 244.0;
    final artworkBlurMaxSize =
        (screenH - bottomCtrlH - 32.0)
            .clamp(220.0, 430.0)
            .toDouble();
    final preferredCoverSize =
        (screenW - (isArtworkBlurStyle ? 0.0 : 44.0))
            .clamp(isArtworkBlurStyle ? 220.0 : 260.0, 430.0)
            .toDouble();
    final portraitCoverSize = isArtworkBlurStyle
        ? preferredCoverSize.clamp(220.0, artworkBlurMaxSize).toDouble()
        : preferredCoverSize;
    // Artwork-blur mode intentionally overscales the square cover by 30%.
    // Horizontal overflow is allowed; the cover stays centered on the screen.
    final largeCoverSize = wideColumns?.artwork.width ??
        (isArtworkBlurStyle ? portraitCoverSize * 1.235 : portraitCoverSize);
    final artFullLeft =
        wideColumns?.artwork.left ?? (screenW - largeCoverSize) / 2;

    // Estimate PlayerContent artwork vertical position at full screen.
    // Layout stack: SafeArea.top + Padding(12) + PlayerContent.Padding(25) = topInset
    // Bottom controls ≈ 244 px.
    final topInset = safeTop + 37.0;
    final shFull = screenH - topInset - bottomCtrlH;
    final rawCoverTop = (shFull - largeCoverSize - 80.0) / 2.0 - 10.0;
    final coverTopLocal = rawCoverTop.clamp(8.0, 60.0);
    // Artwork extends behind the status bar, but is clipped at the physical
    // top edge of the screen. Side overflow remains intentional.
    final artFullTop = wideColumns?.artwork.top ??
        (isArtworkBlurStyle ? 0.0 : topInset + coverTopLocal);

    // Quadratic Bézier arc: artwork swings right then curves up to final pos.
    // Control point pulled right of artFullLeft so the path bulges rightward
    // before settling — keeps the overall diagonal feel ("tetap diagonal").
    // The two-column target sits near the left edge, so the bulge is smaller
    // there to keep the motion a short, natural arc.
    final cpLeft = artFullLeft + screenW * (wideColumns != null ? 0.06 : 0.17);
    final cpTop = lerpDouble(
      miniArtTop,
      artFullTop,
      0.15,
    )!; // low start → late lift
    final bmt = 1.0 - t;
    final artLeft =
        bmt * bmt * miniArtLeft + 2 * bmt * t * cpLeft + t * t * artFullLeft;
    final artTop =
        bmt * bmt * miniArtTop + 2 * bmt * t * cpTop + t * t * artFullTop;
    final artSize = lerpDouble(miniArtSize, largeCoverSize, t)!;
    final artRadius = lerpDouble(4.0, 12.0, t)!;

    return Positioned.fill(
      child: ClipRect(
        clipper: _BottomRevealClipper(clipVisibleHeight),
        child: Stack(
          children: [
            Positioned(
              bottom: bottom,
              left: horizMargin,
              right: horizMargin,
              height: height,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onPanStart: _onPanStart,
                onPanUpdate: _onPanUpdate,
                onPanEnd: _onPanEnd,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(radius),
                  child: Stack(
                    fit: StackFit.expand,
                    clipBehavior: Clip.antiAlias,
                    children: [
                      // ── Dark base (glass-aware at mini state) ──────────────────
                      // BackdropFilter is isolated in its own RepaintBoundary so it
                      // does not re-composite when the rest of the player animates.
                      ValueListenableBuilder<bool>(
                        valueListenable: ThemeController.glassTheme,
                        builder: (_, masterGlass, _) => ValueListenableBuilder<bool>(
                          valueListenable: ThemeController.glassMiniPlayer,
                          builder: (_, compGlass, _) {
                            // Use glass only when fully at rest in mini state.
                            // Threshold 0.05 collapses the glass before drag starts
                            // so BackdropFilter never runs during the morph animation.
                            final useGlass =
                                masterGlass && compGlass && progress < 0.02;
                            if (useGlass) {
                              // Glass = blur backdrop + tint netral penstabil
                              // (sama dengan navbar pill): background pill
                              // tidak meniru warna konten halaman.
                              final c = AppColors.of(context);
                              return RepaintBoundary(
                                child: BackdropGroup(
                                  child: ClipRect(
                                    child: Stack(
                                      fit: StackFit.expand,
                                      children: [
                                        BackdropFilter.grouped(
                                          filterConfig:
                                              const ImageFilterConfig.blur(
                                                sigmaX: 6,
                                                sigmaY: 6,
                                                bounded: true,
                                              ),
                                          blendMode: BlendMode.srcOver,
                                          child: const ColoredBox(
                                            color: Colors.transparent,
                                          ),
                                        ),
                                        ColoredBox(color: c.glassFillTint),
                                      ],
                                    ),
                                  ),
                                ),
                              );
                            }
                            return ColoredBox(
                              color: AppColors.of(context).surface,
                            );
                          },
                        ),
                      ),

                      // ── Pre-blurred artwork background (fades in with progress) ────
                      // AnimatedBlurredPlayerBackground now serves a cached ui.Image
                      // blit — no runtime ImageFilter cost per frame.
                      // The outer ImageFiltered(blurSigma) that previously changed
                      // every drag frame is removed; the inner artwork is already at
                      // sigma 28 which is visually equivalent.
                      if (bgAlpha > 0)
                        Opacity(
                          opacity: bgAlpha,
                          child: RepaintBoundary(
                            child:
                                backgroundStyle ==
                                    PlayerBackgroundStyle.artworkBlur
                                ? ArtworkBlurPlayerBackground(songId: song.id)
                                : AnimatedBlurredPlayerBackground(
                                    songId: song.id,
                                  ),
                          ),
                        ),

                      // ── Gradient overlay ───────────────────────────────────────────
                      if (bgAlpha > 0)
                        Opacity(
                          opacity: bgAlpha,
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              gradient:
                                  backgroundStyle ==
                                      PlayerBackgroundStyle.artworkBlur
                                  ? const LinearGradient(
                                      begin: Alignment.topCenter,
                                      end: Alignment.bottomCenter,
                                      stops: [0, 0.4, 0.7, 1],
                                      colors: [
                                        Color.fromARGB(34, 0, 0, 0),
                                        Color.fromARGB(18, 0, 0, 0),
                                        Color.fromARGB(46, 0, 0, 0),
                                        Color.fromARGB(142, 0, 0, 0),
                                      ],
                                    )
                                  : const LinearGradient(
                                      begin: Alignment.topCenter,
                                      end: Alignment.bottomCenter,
                                      colors: [
                                        Color.fromARGB(40, 0, 0, 0),
                                        Color.fromARGB(40, 0, 0, 0),
                                      ],
                                    ),
                            ),
                          ),
                        ),

                      // ── Status-bar shadow for readable system icons ───────
                      if (isArtworkBlurStyle && bgAlpha > 0)
                        Positioned(
                          top: 0,
                          left: 0,
                          right: 0,
                          height: safeTop.clamp(24.0, 64.0),
                          child: IgnorePointer(
                            child: Opacity(
                              opacity: bgAlpha,
                              child: DecoratedBox(
                                decoration: const BoxDecoration(
                                  gradient: LinearGradient(
                                    begin: Alignment.topCenter,
                                    end: Alignment.bottomCenter,
                                    colors: [
                                      Color.fromARGB(205, 0, 0, 0),
                                      Color.fromARGB(175, 0, 0, 0),
                                      Color.fromARGB(125, 0, 0, 0),
                                      Color.fromARGB(60, 0, 0, 0),
                                      Color.fromARGB(0, 0, 0, 0),
                                    ],
                                    stops: [0.0, 0.22, 0.48, 0.76, 1.0],
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),

                      // ── Full player content (slides up from bottom + fades in) ──────
                      // All UI elements (except the morphing artwork above) enter as a
                      // single unit: they slide up from the bottom of the screen to their
                      // final positions as the sheet expands. The translation is driven by
                      // the same eased `t` used for the rest of the morph so the motion
                      // stays perfectly in sync with the gesture.
                      if (fullAlpha > 0)
                        Transform.translate(
                          offset: Offset(0, screenH * (1.0 - t)),
                          child: Opacity(
                            opacity: fullAlpha,
                            child: IgnorePointer(
                              ignoring: progress < 0.45,
                              child: SafeArea(
                                bottom: false,
                                child: Padding(
                                  padding: const EdgeInsets.only(top: 12),
                                  child: _PlaybackContent(
                                    song: song,
                                    formatTime: _formatTime,
                                    showLyrics: _showLyrics,
                                    onLyricsToggle: _toggleLyrics,
                                    showQueue: _showQueue,
                                    onQueueToggle: _toggleQueue,
                                    // Unified player owns the artwork for all states;
                                    // PlayerContent always hides its own artwork widget.
                                    hideArtwork: true,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),

                      // ── Morphing artwork (mini → full → overlay thumbnail) ─────────
                      // Single artwork widget handles all three states via _overlayAnim,
                      // so there is no crossfade between two separate artwork widgets.
                      AnimatedBuilder(
                        animation: _overlayAnim,
                        builder: (context, _) {
                          final overlayT = Curves.easeInOutCubic.transform(
                            _overlayAnim.value,
                          );

                          // Absolute position of the small thumbnail when overlay is active.
                          // PlayerContent starts at: safeTop + SafeArea(top) + Padding(12) + Padding(25) = safeTop + 37.
                          // Thumbnail is at Stack offset top: -0.5, left: 32 (= _playerHorizontalPadding).
                          const smallLeft = 32.0;
                          const smallSize = 55.0;
                          const smallRadius = 3.0;
                          final smallTop = safeTop + 36.5;

                          // When the sheet is closing from overlay mode (_overlayAnim=1, progress→0),
                          // scale down the thumbnail's influence proportionally with t so the artwork
                          // smoothly flies from the small-thumbnail position to the mini-player
                          // position instead of staying frozen at the top-left corner while the sheet
                          // slides away.
                          final effectiveOverlayT = (overlayT * t).clamp(
                            0.0,
                            1.0,
                          );

                          final finalLeft = lerpDouble(
                            artLeft,
                            smallLeft,
                            effectiveOverlayT,
                          )!;
                          final finalTop = lerpDouble(
                            artTop,
                            smallTop,
                            effectiveOverlayT,
                          )!;
                          final finalSize = lerpDouble(
                            artSize,
                            smallSize,
                            effectiveOverlayT,
                          )!;
                          final finalRadius = lerpDouble(
                            artRadius,
                            smallRadius,
                            effectiveOverlayT,
                          )!;
                          // Shadow grows with sheet-open progress (t) and fades away in thumbnail mode.
                          final shadowBase = t * (1.0 - effectiveOverlayT);
                          final shadowAlpha = 0.20 * shadowBase;
                          final shadowBlur = 20.0 * shadowBase;
                          final shadowOff = 10.0 * shadowBase;

                          // Pulse scale uses raw overlayT (not effectiveOverlayT) so the suppression
                          // only lifts once the overlay animation itself has fully reversed, not
                          // during a sheet-close where _overlayAnim stays at 1.
                          // Uses _isPlaying field — rebuilt by setState only on play/pause, not position ticks.
                          // Keep the main artwork static when playback toggles.
                          const targetScale = 1.0;
                          final artworkFadeStrength = isArtworkBlurStyle
                              ? (((t - 0.65) / 0.35).clamp(0.0, 1.0) *
                                    (1.0 - effectiveOverlayT))
                                    .clamp(0.0, 1.0)
                                    .toDouble()
                              : 0.0;
                          final artworkWithFade = SongArtwork(
                            songId: song.id,
                            size: artSize,
                            borderRadius: BorderRadius.zero,
                            // The artwork itself fades into the blurred background.
                            showBorder: false,
                            bottomFadeStrength: isArtworkBlurStyle
                                ? artworkFadeStrength
                                : 0.0,
                          );

                          return Positioned(
                            left: finalLeft,
                            top: finalTop,
                            width: finalSize,
                            height: finalSize,
                            child: AnimatedScale(
                              duration: const Duration(milliseconds: 300),
                              curve: Curves.easeOutCubic,
                              scale: targetScale,
                              child: Container(
                                // Shadow in background so it renders behind the artwork.
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(4),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black.withValues(
                                        alpha: shadowAlpha,
                                      ),
                                      blurRadius: shadowBlur,
                                      offset: Offset(0, shadowOff),
                                    ),
                                  ],
                                ),
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(
                                    finalRadius,
                                  ),
                                  child: artworkWithFade,
                                ),
                              ),
                            ),
                          );
                        },
                      ),

                      // ── Mini player overlay (fades out in first 28% of progress) ───
                      if (miniAlpha > 0)
                        Opacity(
                          opacity: miniAlpha,
                          child: IgnorePointer(
                            ignoring: progress > 0.08,
                            child: _buildMiniOverlay(
                              context,
                              song,
                              progress,
                              isPill,
                            ),
                          ),
                        ),

                      // ── Border kaca (mode pill) — menyatu dengan navbar ────────────
                      // Hanya saat mini state; memudar saat sheet membuka sehingga
                      // full player tetap tanpa border.
                      if (isPill && miniAlpha > 0)
                        Positioned.fill(
                          child: IgnorePointer(
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(radius),
                                border: Border.all(
                                  // Kalikan alpha token, bukan replace: dulu
                                  // withValues(alpha: miniAlpha) menimpa alpha
                                  // ke 1.0 → outline mini player SOLID dan
                                  // tidak konsisten dengan navbar pill.
                                  color: AppColors.of(context).glassBorderTint
                                      .withValues(
                                        alpha:
                                            AppColors.of(
                                              context,
                                            ).glassBorderTint.a *
                                            miniAlpha,
                                      ),
                                  width: 1,
                                ),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ), // closes inner Positioned
          ],
        ), // closes inner Stack
      ), // closes ClipRect
    ); // closes Positioned.fill
  }

  // ── Mini player overlay (identik dengan MiniPlayer asli) ───────────────────
  // Uses _isPlaying field instead of AudioPlaybackState parameter —
  // only rebuilt on song/isPlaying changes, not on position ticks.
  Widget _buildMiniOverlay(
    BuildContext context,
    LocalSong song,
    double progress,
    bool isPill,
  ) {
    final miniContentAlpha = (1.0 - progress / 0.01).clamp(0.0, 1.0);

    final miniContentOffset = -5.0 * (1.0 - miniContentAlpha);
    return Stack(
      fit: StackFit.expand,
      children: [
        // Swipe arrow hint (kiri = prev, kanan = next)

        // Row utama: [artwork spacer] [title] [controls]
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(
            children: [
              // Spacer untuk morphing artwork (46 px lebar + 10 px gap).
              // Mode pill: +10px agar judul mengikuti artwork yang digeser.
              SizedBox(width: isPill ? 66 : 56),

              // Judul lagu dengan Hero tag
              Expanded(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => _animateTo(1.0),
                  child: Transform.translate(
                    offset: Offset(0, miniContentOffset),
                    child: Opacity(
                      opacity: miniContentAlpha,
                      child: Hero(
                        tag: PlayerHeroTags.title(song),
                        child: Material(
                          type: MaterialType.transparency,
                          child: Text(
                            song.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: AppColors.of(context).primaryLabel,
                              fontSize: 15,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),

              // Play / Pause — uses _isPlaying field
              Transform.translate(
                offset: Offset(0, miniContentOffset),
                child: Opacity(
                  opacity: miniContentAlpha,
                  child: Row(
                    children: [
                      IconButton(
                        onPressed: () => _isPlaying
                            ? AudioService.pause()
                            : AudioService.play(),
                        icon: Icon(
                          _isPlaying
                              ? CupertinoIcons.pause_fill
                              : CupertinoIcons.play_fill,
                          size: 31,
                          color: AppColors.of(context).primaryLabel,
                        ),
                      ),
                      IconButton(
                        onPressed: AudioService.skipNext,
                        icon: Icon(
                          CupertinoIcons.forward_fill,
                          size: 30,
                          color: AppColors.of(context).primaryLabel,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ── _PlaybackContent & _BottomRevealClipper ────────────────────────────────
// Dipindah ke part file (lihat deklarasi `part` di atas):
//   unified_morph_player/playback_content.dart
//   unified_morph_player/bottom_reveal_clipper.dart
