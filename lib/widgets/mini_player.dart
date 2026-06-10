import 'dart:ui';

import 'package:flutter/material.dart';

import '../models/local_song.dart';
import '../pages/music_player.dart';
import '../services/audio_service.dart';
import '../themes/theme_controller.dart';
import 'now_playing/now_playing_components.dart';

class MiniPlayer extends StatelessWidget {
  const MiniPlayer({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<AudioPlaybackState>(
      valueListenable: AudioService.playbackState,
      builder: (context, playbackState, _) {
        final song = playbackState.currentSong;
        if (song == null) return const SizedBox.shrink();

        return ValueListenableBuilder<bool>(
          valueListenable: ThemeController.glassTheme,
          builder: (context, isGlass, _) {
            return DynamicArtworkPalette(
              song: song,
              isGlass: isGlass,
              builder: (context, theme) {
                return _MiniPlayerBody(
                  song: song,
                  playbackState: playbackState,
                  theme: theme,
                );
              },
            );
          },
        );
      },
    );
  }
}

class _MiniPlayerBody extends StatelessWidget {
  final LocalSong song;
  final AudioPlaybackState playbackState;
  final NowPlayingThemeData theme;

  const _MiniPlayerBody({
    required this.song,
    required this.playbackState,
    required this.theme,
  });

  @override
  Widget build(BuildContext context) {
    final horizontal = theme.isGlass ? 12.0 : 8.0;

    return Padding(
      padding: EdgeInsets.fromLTRB(horizontal, 8, horizontal, theme.isGlass ? 8 : 0),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => _openFullPlayer(context),
        onVerticalDragEnd: (details) {
          final velocity = details.primaryVelocity ?? 0;
          if (velocity < -260) _openFullPlayer(context);
        },
        child: TweenAnimationBuilder<double>(
          tween: Tween<double>(begin: 0.98, end: 1),
          duration: const Duration(milliseconds: 360),
          curve: Curves.easeOutBack,
          builder: (context, scale, child) => Transform.scale(scale: scale, child: child),
          child: GlassSurface(
            theme: theme,
            strong: theme.isGlass,
            padding: const EdgeInsets.fromLTRB(10, 8, 8, 8),
            borderRadius: BorderRadius.circular(theme.isGlass ? 26 : 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    NowPlayingArtwork(song: song, size: 46, theme: theme, expansion: 0),
                    const SizedBox(width: 12),
                    Expanded(
                      child: NowPlayingMetadata(
                        song: song,
                        theme: theme,
                        titleSize: 15.5,
                      ),
                    ),
                    const SizedBox(width: 4),
                    NowPlayingTransportControls(
                      playbackState: playbackState,
                      theme: theme,
                      compact: true,
                    ),
                  ],
                ),
                const SizedBox(height: 7),
                NowPlayingProgress(
                  theme: theme,
                  formatTime: _formatTime,
                  compact: true,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _formatTime(Duration duration) {
    final safeDuration = duration.isNegative ? Duration.zero : duration;
    final minutes = safeDuration.inMinutes.remainder(60);
    final seconds = safeDuration.inSeconds.remainder(60);
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }

  void _openFullPlayer(BuildContext context) {
    Navigator.of(context).push(
      PageRouteBuilder<void>(
        opaque: false,
        barrierColor: Colors.black.withOpacity(0.52),
        transitionDuration: const Duration(milliseconds: 520),
        reverseTransitionDuration: const Duration(milliseconds: 360),
        pageBuilder: (context, animation, secondaryAnimation) => const MusicPlayer(),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          final curved = CurvedAnimation(
            parent: animation,
            curve: Curves.easeOutCubic,
            reverseCurve: Curves.easeInCubic,
          );
          return AnimatedBuilder(
            animation: curved,
            builder: (context, _) {
              final value = curved.value;
              return BackdropFilter(
                filter: ImageFilter.blur(
                  sigmaX: lerpDouble(0, 10, value)!,
                  sigmaY: lerpDouble(0, 10, value)!,
                ),
                child: FadeTransition(
                  opacity: curved,
                  child: SlideTransition(
                    position: Tween<Offset>(
                      begin: const Offset(0, 0.10),
                      end: Offset.zero,
                    ).animate(curved),
                    child: child,
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
