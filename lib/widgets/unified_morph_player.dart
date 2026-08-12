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
import '../themes/theme_controller.dart';
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

    final provider = repo.getProviderSync(
      song.id,
      targetSizePx: targetPx,
    );

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
      _currentSong = song;
      needsRebuild = true;

      // Entry animation is only for the mini player first appearing.
      // Do not restart it when switching directly from one song to another.
      if (!hadPreviousSong && song != null) {
        final appearedSong = song;

        unawaited(
          _prewarmEntryArtwork(appearedSong).then((_) {
            if (mounted && _currentSong?.id == appearedSong.id) {
              unawaited(_entryAnim.forward(from: 0.0));
            }
          }),
        );
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
        unawaited(AudioService.skipNext());
      } else if (_panDx > 80 || vx > 350) {
        unawaited(AudioService.skipPrevious());
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
    // so it... (content unchanged except trigger condition)