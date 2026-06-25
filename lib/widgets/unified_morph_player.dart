import 'dart:ui';
import 'package:flutter/material.dart';

import '../models/local_song.dart';
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
    PlayerSheetController.expanded.addListener(_onExpandedChanged);
  }

  @override
  void dispose() {
    _overlayAnim.dispose();
    _releaseAnim.dispose();
    PlayerSheetController.expanded.removeListener(_onExpandedChanged);
    super.dispose();
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
      final sh = MediaQuery.of(context).size.height;
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
  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<AudioPlaybackState>(
      valueListenable: AudioService.playbackState,
      builder: (context, state, _) {
        final song = state.currentSong;
        if (song == null) return const SizedBox.shrink();
        return ValueListenableBuilder<double>(
          valueListenable: PlayerSheetController.progress,
          builder: (context, progress, _) {
            return _buildMorph(context, song, state, progress);
          },
        );
      },
    );
  }

  Widget _buildMorph(
    BuildContext context,
    LocalSong song,
    AudioPlaybackState state,
    double progress,
  ) {
    final mq = MediaQuery.of(context);
    final screenH = mq.size.height;
    final screenW = mq.size.width;
    final safeBottom = mq.padding.bottom;
    final safeTop = mq.padding.top;

    const miniH = 64.5;
    const miniHorizMargin = 0.0;
    const navBarH = kBottomNavHeight;
    const miniBottomGap = 0.0;

    // Eased curve for Apple-Music–like deceleration
    final t = Curves.easeOutCubic.transform(progress);

    final bottom = lerpDouble(navBarH + safeBottom + miniBottomGap, 0.0, t)!;
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

    final artLeft = lerpDouble(miniArtLeft, artFullLeft, t)!;
    final artTop = lerpDouble(miniArtTop, artFullTop, t)!;
    final artSize = lerpDouble(miniArtSize, largeCoverSize, t)!;
    final artRadius = 3.0;

    return Positioned(
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
                builder: (_, masterGlass, _) =>
                    ValueListenableBuilder<bool>(
                  valueListenable: ThemeController.glassMiniPlayer,
                  builder: (_, compGlass, _) {
                    // Use glass only when fully at rest in mini state.
                    // Threshold 0.05 collapses the glass before drag starts
                    // so BackdropFilter never runs during the morph animation.
                    final useGlass =
                        masterGlass && compGlass && progress < 0.02;
                    if (useGlass) {
                      return RepaintBoundary(
                        child: ClipRect(
                          child: BackdropFilter(
                            filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
                            child: ColoredBox(
                              color: Colors.black.withValues(alpha: 0.0),
                            ),
                          ),
                        ),
                      );
                    }
                    return const ColoredBox(color: Color(0xFF1C1C1E));
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
                    child: AnimatedBlurredPlayerBackground(songId: song.id),
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
                          Color.fromARGB(40, 0, 0, 0),
                          Color.fromARGB(40, 0, 0, 0),
                        ],
                      ),
                    ),
                  ),
                ),

              // ── Full player content (fades in) ─────────────────────────────
              if (fullAlpha > 0)
                Opacity(
                  opacity: fullAlpha,
                  child: IgnorePointer(
                    ignoring: progress < 0.45,
                    child: SafeArea(
                      bottom: false,
                      child: Padding(
                        padding: const EdgeInsets.only(top: 12),
                        child: PlayerContent(
                          song: song,
                          playbackState: state,
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

              // ── Morphing artwork (mini → full → overlay thumbnail) ─────────
              // Single artwork widget handles all three states via _overlayAnim,
              // so there is no crossfade between two separate artwork widgets.
              AnimatedBuilder(
  animation: _overlayAnim,
  builder: (context, _) {
    final overlayT = Curves.easeInOutCubic.transform(_overlayAnim.value);

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
    final effectiveOverlayT = (overlayT * t).clamp(0.0, 1.0);

    final finalLeft   = lerpDouble(artLeft,   smallLeft,   effectiveOverlayT)!;
    final finalTop    = lerpDouble(artTop,    smallTop,    effectiveOverlayT)!;
    final finalSize   = lerpDouble(artSize,   smallSize,   effectiveOverlayT)!;
    final finalRadius = lerpDouble(artRadius, smallRadius, effectiveOverlayT)!;
    final shadowAlpha = lerpDouble(0.30,      0.0,         effectiveOverlayT)!;
    final shadowBlur  = lerpDouble(40.0,      0.0,         effectiveOverlayT)!;
    final shadowOff   = lerpDouble(15.0,      0.0,         effectiveOverlayT)!;

    // Pulse scale uses raw overlayT (not effectiveOverlayT) so the suppression
    // only lifts once the overlay animation itself has fully reversed, not
    // during a sheet-close where _overlayAnim stays at 1.
    final targetScale = overlayT > 0.5
        ? 1.0
        : (state.isPlaying ? 1.0 : 0.96);

    return Positioned(
      left:   finalLeft,
      top:    finalTop,
      width:  finalSize,
      height: finalSize,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(finalRadius),
          boxShadow: [
            BoxShadow(
              color:      Colors.black.withValues(alpha: shadowAlpha),
              blurRadius: shadowBlur,
              offset:     Offset(0, shadowOff),
            ),
          ],
        ),
        child: AnimatedScale(
          duration: const Duration(milliseconds: 300),
          curve:    Curves.easeOutCubic,
          scale:    targetScale,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(finalRadius),
            child: SongArtwork(
              songId:       song.id,
              size:         artSize,
              borderRadius: BorderRadius.zero,
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
                    child: _buildMiniOverlay(
                    song,
                    state,
                    progress,
                    ),
                  ),
                ),

            
              

              // ── Collapse chevron (top-left of full player) ─────────────────
              
            ],
          ),
        ),
      ),
    );
  }

  // ── Mini player overlay (identik dengan MiniPlayer asli) ─────────────────
  Widget _buildMiniOverlay(
  LocalSong song,
  AudioPlaybackState state,
  double progress,
) {
    final miniContentAlpha =
    (1.0 - progress / 0.01).clamp(0.0, 1.0);

    final miniContentOffset =
    -5.0 * (1.0 - miniContentAlpha);
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
              style: const TextStyle(
                color: Colors.white,
                fontSize: 15,
              ),
            ),
          ),
        ),
      ),
    ),
  ),
),
                  
              // Play / Pause
Transform.translate(
  offset: Offset(0, miniContentOffset),
  child: Opacity(
    opacity: miniContentAlpha,
    child: Row(
      children: [
        IconButton(
          onPressed: () => state.isPlaying
              ? AudioService.pause()
              : AudioService.play(),
          icon: Icon(
            state.isPlaying
                ? Icons.pause_rounded
                : Icons.play_arrow_rounded,
            size: 36,
            color: Colors.white,
          ),
        ),
        const IconButton(
          onPressed: AudioService.skipNext,
          icon: Icon(
            Icons.fast_forward_rounded,
            size: 36,
            color: Colors.white,
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
