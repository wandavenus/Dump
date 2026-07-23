import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import '../models/local_song.dart';
import '../theme/app_colors.dart';
import '../services/audio_playback_state.dart';
import '../services/audio_service.dart';
import '../services/player_sheet_controller.dart';
import '../themes/theme_controller.dart';
import 'player/player_background.dart';
import 'player/player_content.dart';
import 'player/player_hero_tags.dart';
import 'song_artwork.dart';

class UnifiedMorphPlayer extends StatefulWidget {
  const UnifiedMorphPlayer({super.key});

  @override
  State<UnifiedMorphPlayer> createState() => _UnifiedMorphPlayerState();
}

class _UnifiedMorphPlayerState extends State<UnifiedMorphPlayer>
    with TickerProviderStateMixin {
  // ── Gesture state ──────────────────────────────────────────────────────────
  double _panDx = 0;
  double _panDy = 0;
  bool _isHorizontal = false;
  bool _directionLocked = false;
  double _swipeOffset = 0;
  double _startProgress = 0;

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
    );
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
      _entryAnim.forward(from: 0.0);
    }
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

    // Entry animation: first song appears (was null, now non-null).
    if (_currentSong == null && song != null) {
      _entryAnim.forward(from: 0.0);
    }

    var needsRebuild = false;

    // Song identity changed (including null → non-null and vice-versa).
    final songChanged =
        (_currentSong == null) != (song == null) ||
        (_currentSong?.id != song?.id);
    if (songChanged) {
      _currentSong = song;
      needsRebuild = true;
    }

    // Play / Pause state changed.
    if (_isPlaying != isPlaying) {
      _isPlaying = isPlaying;
      needsRebuild = true;
    }

    if (needsRebuild && mounted) setState(() {});
  }

  void _onReleaseAnimTick() {
    // easeOutCubic applied in listener so we drive the raw controller linearly
    final u = 1.0 - _releaseAnim.value;
    final eased = 1.0 - u * u * u;
    final value = _animStartVal + (_animTarget - _animStartVal) * eased;
    PlayerSheetController.setProgress(value.clamp(0.0, 1.0));
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
    final durationMs = (distance * 400).clamp(80.0, 400.0).toInt();
    _releaseAnim.duration = Duration(milliseconds: durationMs);
    _releaseAnim.value = 0.0;
    _releaseAnim.animateTo(1.0, curve: Curves.linear);
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
      _overlayAnim.forward();
    } else if (wasOverlay && !isOverlay) {
      _overlayAnim.reverse();
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
      _overlayAnim.forward();
    } else if (wasOverlay && !isOverlay) {
      _overlayAnim.reverse();
    }
  }

  // ── Gesture callbacks ──────────────────────────────────────────────────────
  void _onPanStart(DragStartDetails d) {
    // Stop any in-flight release animation so the finger takes over immediately
    PlayerSheetController.cancelAnimation();
    _releaseAnim.stop();

    _panDx = 0;
    _panDy = 0;
    _isHorizontal = false;
    _directionLocked = false;
    _swipeOffset = 0;
    _startProgress = PlayerSheetController.progress.value;
  }

  void _onPanUpdate(DragUpdateDetails d) {
    _panDx += d.delta.dx;
    _panDy += d.delta.dy;

    if (!_directionLocked && (_panDx.abs() > 8 || _panDy.abs() > 8)) {
      _isHorizontal = _panDx.abs() > _panDy.abs();
      _directionLocked = true;
    }
    if (!_directionLocked) return;

    if (_isHorizontal) {
      if (_startProgress < 0.15) {
        if ((_swipeOffset - _panDx).abs() > 2) {
          setState(() => _swipeOffset = _panDx);
        }
      }
    } else {
      if (_showLyrics || _showQueue) return;
      final sh = MediaQuery.sizeOf(context).height;
      final delta = -d.delta.dy / (sh * 0.55);
      PlayerSheetController.setProgress(
        (PlayerSheetController.progress.value + delta).clamp(0.0, 1.0),
      );
    }
  }

  void _onPanEnd(DragEndDetails d) {
    final progress = PlayerSheetController.progress.value;
    if (_isHorizontal && _startProgress < 0.15) {
      final vx = d.velocity.pixelsPerSecond.dx;
      if (_panDx < -80 || vx < -350) {
        AudioService.skipNext();
      } else if (_panDx > 80 || vx > 350) {
        AudioService.skipPrevious();
      }
      setState(() => _swipeOffset = 0);
    } else if (!_isHorizontal && !(_showLyrics || _showQueue)) {
      final vy = d.velocity.pixelsPerSecond.dy;
      if (vy > 500 || (progress <= 0.35 && vy >= 0)) {
        _animateTo(0.0);
      } else if (progress > 0.35 || vy < -200) {
        _animateTo(1.0);
      } else {
        _animateTo(0.0);
      }
    }
    _panDx = 0;
    _panDy = 0;
    _directionLocked = false;
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
        return AnimatedBuilder(
          animation: _entryAnim,
          builder: (context, _) {
            return ValueListenableBuilder<double>(
              valueListenable: PlayerSheetController.progress,
              builder: (context, progress, _) {
                return _buildMorph(context, song, progress, isGlass);
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
  ) {
    final mq = MediaQuery.of(context);
    final screenH = mq.size.height;
    final screenW = mq.size.width;
    final safeBottom = mq.padding.bottom;
    final safeTop = mq.padding.top;

    const miniH = 64.5;
    const miniHorizMargin = 0.0;
    // Default mode has a 1.5px separator strip above the navBar (total column = 71.5px).
    // Glass mode omits the separator (total column = 70px), so navBar top sits 1.5px
    // lower — offset navBarH down by the same amount so mini player stays flush.
    final navBarH = isGlass ? 53.8 : 55.1;
    const miniBottomGap = 0.0;

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
    // Border radius: linear so corners snap crisply at 0
    final radius = lerpDouble(0.0, 0.0, progress)!;

    // Cross-fade timing
    final miniAlpha = (1.0 - progress / 0.28).clamp(0.0, 1.0);
    final fullAlpha = ((progress - 0.12) / 0.38).clamp(0.0, 1.0);
    final bgAlpha = (progress / 0.35).clamp(0.0, 1.0);

    // ── Artwork morph positions ──────────────────────────────────────────────
    const miniArtSize = 46.3;
    const miniArtLeft = 12.0;
    const miniArtTop = (miniH - miniArtSize) / 2; // = 9 px

    final largeCoverSize = (screenW - 44.0).clamp(260.0, 390.0);
    final artFullLeft = (screenW - largeCoverSize) / 2;

    // Estimate PlayerContent artwork vertical position at full screen.
    // Layout stack: SafeArea.top + Padding(12) + PlayerContent.Padding(25) = topInset
    // Bottom controls ≈ 244 px.
    final topInset = safeTop + 37.0;
    const bottomCtrlH = 244.0;
    final shFull = screenH - topInset - bottomCtrlH;
    final rawCoverTop = (shFull - largeCoverSize - 80.0) / 2.0 - 10.0;
    final coverTopLocal = rawCoverTop.clamp(8.0, 60.0);
    final artFullTop = topInset + coverTopLocal;

    // Quadratic Bézier arc: artwork swings right then curves up to final pos.
    // Control point pulled right of artFullLeft so the path bulges rightward
    // before settling — keeps the overall diagonal feel ("tetap diagonal").
    final cpLeft = artFullLeft + screenW * 0.17; // ≈ 67 px on 393-wide screen
    final cpTop  = lerpDouble(miniArtTop, artFullTop, 0.15)!; // low start → late lift
    final bmt = 1.0 - t;
    final artLeft = bmt * bmt * miniArtLeft + 2 * bmt * t * cpLeft + t * t * artFullLeft;
    final artTop  = bmt * bmt * miniArtTop  + 2 * bmt * t * cpTop  + t * t * artFullTop;
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
                              final c = AppColors.of(context);
                              return RepaintBoundary(
                                child: ClipRect(
                                  child: BackdropFilter(
                                    filter: ImageFilter.blur(
                                      sigmaX: 32,
                                      sigmaY: 32,
                                    ),
                                    blendMode: BlendMode.srcOver,
                                    child: ColoredBox(color: c.glassNavTint),
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
                            child: AnimatedBlurredPlayerBackground(
                              songId: song.id,
                            ),
                          ),
                        ),

                      // ── Gradient overlay ───────────────────────────────────────────
                      if (bgAlpha > 0)
                        Opacity(
                          opacity: bgAlpha,
                          child: const DecoratedBox(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                                colors: [
                                  Color.fromARGB(50, 0, 0, 0),
                                  Color.fromARGB(50, 0, 0, 0),
                                ],
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
                          final targetScale = overlayT > 0.5
                              ? 1.0
                              : (_isPlaying ? 1.0 : 0.96);

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
                                // Hairline border in foreground so it paints ON TOP of the artwork
                                // and covers any antialiasing gaps left by ClipRRect at the corners.
                                // This matches the approach used in ArtworkHairlineBorder.
                                foregroundDecoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(
                                    finalRadius,
                                  ),
                                  border: Border.all(
                                    color: kArtworkHairlineColor,
                                    width: kArtworkHairlineWidth,
                                    strokeAlign: BorderSide.strokeAlignInside,
                                  ),
                                ),
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(
                                    finalRadius,
                                  ),
                                  child: SongArtwork(
                                    songId: song.id,
                                    size: artSize,
                                    borderRadius: BorderRadius.zero,
                                    // Hairline already drawn on the outer Container above —
                                    // avoids a doubled/mismatched stroke here.
                                    showBorder: false,
                                  ),
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
                            child: _buildMiniOverlay(context, song, progress),
                          ),
                        ),

                      // ── Collapse chevron (top-left of full player) ─────────────────
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

  // ── Mini player overlay (identik dengan MiniPlayer asli) ─────────────────
  // Uses _isPlaying field instead of AudioPlaybackState parameter —
  // only rebuilt on song/isPlaying changes, not on position ticks.
  Widget _buildMiniOverlay(
    BuildContext context,
    LocalSong song,
    double progress,
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
              // Spacer untuk morphing artwork (46 px lebar + 10 px gap)
              const SizedBox(width: 56),

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

// ── _PlaybackContent ─────────────────────────────────────────────────────────
// Narrow VLB wrapper around PlayerContent.
// Responsibility: subscribe to AudioService.playbackState and pass the full
// state to PlayerContent — isolating position-tick rebuilds to this subtree
// only, so the morph layout in _UnifiedMorphPlayerState is NOT rebuilt on
// every 100 ms position update.
class _PlaybackContent extends StatelessWidget {
  final LocalSong song;
  final String Function(Duration) formatTime;
  final bool showLyrics;
  final VoidCallback onLyricsToggle;
  final bool showQueue;
  final VoidCallback onQueueToggle;
  final bool hideArtwork;

  const _PlaybackContent({
    required this.song,
    required this.formatTime,
    required this.showLyrics,
    required this.onLyricsToggle,
    required this.showQueue,
    required this.onQueueToggle,
    this.hideArtwork = false,
  });

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<AudioPlaybackState>(
      valueListenable: AudioService.playbackState,
      builder: (context, playbackState, _) {
        return PlayerContent(
          song: song,
          playbackState: playbackState,
          formatTime: formatTime,
          showLyrics: showLyrics,
          onLyricsToggle: onLyricsToggle,
          showQueue: showQueue,
          onQueueToggle: onQueueToggle,
          hideArtwork: hideArtwork,
        );
      },
    );
  }
}

// ── Reveal clipper used by the mini-player entry animation ───────────────────
// Clips away everything at/below a given height so the mini player appears to
// rise from behind/inside the bottom nav bar instead of sliding on top of it.
class _BottomRevealClipper extends CustomClipper<Rect> {
  final double visibleHeight;
  const _BottomRevealClipper(this.visibleHeight);

  @override
  Rect getClip(Size size) => Rect.fromLTWH(0, 0, size.width, visibleHeight);

  @override
  bool shouldReclip(covariant _BottomRevealClipper oldClipper) =>
      oldClipper.visibleHeight != visibleHeight;
}
