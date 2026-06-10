import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../../models/local_song.dart';
import '../../services/audio_service.dart';
import '../../services/media_store_service.dart';
import '../song_artwork.dart';

class PlayerHeroTags {
  const PlayerHeroTags._();

  static String artwork(LocalSong song) => 'player-artwork-${song.id}-${song.path}';
  static String title(LocalSong song) => 'player-title-${song.id}-${song.path}';
}

enum NowPlayingStyle { material, liquidGlass }

class NowPlayingThemeData {
  final NowPlayingStyle style;
  final Color accent;
  final Color background;
  final Color surface;
  final Color surfaceStrong;
  final Color primaryText;
  final Color secondaryText;
  final double cornerRadius;
  final double blurSigma;
  final bool isGlass;

  const NowPlayingThemeData._({
    required this.style,
    required this.accent,
    required this.background,
    required this.surface,
    required this.surfaceStrong,
    required this.primaryText,
    required this.secondaryText,
    required this.cornerRadius,
    required this.blurSigma,
    required this.isGlass,
  });

  factory NowPlayingThemeData.material(Color seed) {
    final accent = Color.lerp(const Color(0xFFF92D48), seed, 0.16)!;
    return NowPlayingThemeData._(
      style: NowPlayingStyle.material,
      accent: accent,
      background: const Color(0xFF0B0B0D),
      surface: const Color(0xFF1C1C1E),
      surfaceStrong: const Color(0xFF2A2A2D),
      primaryText: Colors.white,
      secondaryText: Colors.white70,
      cornerRadius: 24,
      blurSigma: 0,
      isGlass: false,
    );
  }

  factory NowPlayingThemeData.glass(Color seed) {
    final accent = HSLColor.fromColor(seed).withLightness(0.64).withSaturation(0.72).toColor();
    return NowPlayingThemeData._(
      style: NowPlayingStyle.liquidGlass,
      accent: accent,
      background: Color.lerp(const Color(0xFF09070B), seed, 0.28)!,
      surface: Colors.white.withOpacity(0.105),
      surfaceStrong: Colors.white.withOpacity(0.16),
      primaryText: Colors.white,
      secondaryText: Colors.white.withOpacity(0.76),
      cornerRadius: 32,
      blurSigma: 22,
      isGlass: true,
    );
  }
}

class DynamicArtworkPalette extends StatelessWidget {
  final LocalSong? song;
  final bool isGlass;
  final Widget Function(BuildContext context, NowPlayingThemeData theme) builder;

  const DynamicArtworkPalette({
    super.key,
    required this.song,
    required this.isGlass,
    required this.builder,
  });

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Color>(
      future: ArtworkColorExtractor.colorForSong(song?.id ?? 0),
      initialData: const Color(0xFFF92D48),
      builder: (context, snapshot) {
        final seed = snapshot.data ?? const Color(0xFFF92D48);
        return TweenAnimationBuilder<Color?>(
          tween: ColorTween(end: seed),
          duration: const Duration(milliseconds: 520),
          curve: Curves.easeOutCubic,
          builder: (context, animatedSeed, _) {
            final animatedTheme = isGlass
                ? NowPlayingThemeData.glass(animatedSeed ?? seed)
                : NowPlayingThemeData.material(animatedSeed ?? seed);
            return builder(context, animatedTheme);
          },
        );
      },
    );
  }
}

class ArtworkColorExtractor {
  static final Map<int, Future<Color>> _cache = <int, Future<Color>>{};

  static Future<Color> colorForSong(int songId) {
    if (songId <= 0) return Future<Color>.value(const Color(0xFFF92D48));
    return _cache.putIfAbsent(songId, () async {
      final bytes = await MediaStoreService.getArtwork(songId);
      if (bytes == null || bytes.isEmpty) return const Color(0xFFF92D48);
      return _averageColor(bytes);
    });
  }

  static Future<Color> _averageColor(Uint8List bytes) async {
    try {
      final codec = await instantiateImageCodec(bytes, targetWidth: 18, targetHeight: 18);
      final frame = await codec.getNextFrame();
      final byteData = await frame.image.toByteData(format: ImageByteFormat.rawRgba);
      if (byteData == null) return const Color(0xFFF92D48);

      int red = 0;
      int green = 0;
      int blue = 0;
      int samples = 0;
      final data = byteData.buffer.asUint8List();
      for (int i = 0; i < data.length; i += 16) {
        final alpha = data[i + 3];
        if (alpha < 80) continue;
        red += data[i];
        green += data[i + 1];
        blue += data[i + 2];
        samples++;
      }
      if (samples == 0) return const Color(0xFFF92D48);
      final color = Color.fromARGB(255, red ~/ samples, green ~/ samples, blue ~/ samples);
      final hsl = HSLColor.fromColor(color);
      return hsl.withSaturation(hsl.saturation.clamp(0.34, 0.78).toDouble()).withLightness(hsl.lightness.clamp(0.28, 0.58).toDouble()).toColor();
    } catch (_) {
      return const Color(0xFFF92D48);
    }
  }
}

class NowPlayingBackground extends StatelessWidget {
  final LocalSong? song;
  final NowPlayingThemeData theme;

  const NowPlayingBackground({
    super.key,
    required this.song,
    required this.theme,
  });

  @override
  Widget build(BuildContext context) {
    if (!theme.isGlass || song == null) {
      return DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Color.lerp(theme.background, theme.accent, 0.12)!,
              theme.background,
              const Color(0xFF030304),
            ],
          ),
        ),
      );
    }

    return Stack(
      fit: StackFit.expand,
      children: [
        Transform.scale(
          scale: 1.18,
          child: SongArtwork(
            songId: song!.id,
            size: MediaQuery.of(context).size.longestSide,
            borderRadius: BorderRadius.zero,
          ),
        ),
        BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 42, sigmaY: 42),
          child: const SizedBox.expand(),
        ),
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: RadialGradient(
              center: const Alignment(-0.4, -0.72),
              radius: 1.2,
              colors: [
                theme.accent.withOpacity(0.48),
                theme.background.withOpacity(0.64),
                const Color(0xFF030305),
              ],
            ),
          ),
        ),
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Colors.black.withOpacity(0.10),
                Colors.black.withOpacity(0.28),
                Colors.black.withOpacity(0.72),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class GlassSurface extends StatelessWidget {
  final Widget child;
  final NowPlayingThemeData theme;
  final EdgeInsetsGeometry padding;
  final BorderRadius? borderRadius;
  final bool strong;

  const GlassSurface({
    super.key,
    required this.child,
    required this.theme,
    this.padding = EdgeInsets.zero,
    this.borderRadius,
    this.strong = false,
  });

  @override
  Widget build(BuildContext context) {
    final radius = borderRadius ?? BorderRadius.circular(theme.cornerRadius);
    final fill = strong ? theme.surfaceStrong : theme.surface;
    final content = Container(
      padding: padding,
      decoration: BoxDecoration(
        borderRadius: radius,
        color: fill,
        border: Border.all(color: Colors.white.withOpacity(theme.isGlass ? 0.18 : 0.05)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(theme.isGlass ? 0.30 : 0.20),
            blurRadius: theme.isGlass ? 30 : 18,
            offset: const Offset(0, 16),
          ),
          if (theme.isGlass)
            BoxShadow(
              color: theme.accent.withOpacity(0.18),
              blurRadius: 42,
              offset: const Offset(0, -10),
            ),
        ],
        gradient: theme.isGlass
            ? LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Colors.white.withOpacity(0.22),
                  fill,
                  theme.accent.withOpacity(0.10),
                ],
              )
            : null,
      ),
      child: child,
    );

    if (!theme.isGlass) return content;
    return ClipRRect(
      borderRadius: radius,
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: theme.blurSigma, sigmaY: theme.blurSigma),
        child: content,
      ),
    );
  }
}

class NowPlayingArtwork extends StatelessWidget {
  final LocalSong song;
  final double size;
  final NowPlayingThemeData theme;
  final double expansion;

  const NowPlayingArtwork({
    super.key,
    required this.song,
    required this.size,
    required this.theme,
    this.expansion = 1,
  });

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(lerpDouble(10, theme.isGlass ? 34 : 18, expansion)!);
    return Hero(
      tag: PlayerHeroTags.artwork(song),
      flightShuttleBuilder: _flightShuttleBuilder,
      child: Material(
        type: MaterialType.transparency,
        child: RepaintBoundary(
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 360),
            curve: Curves.easeOutCubic,
            decoration: BoxDecoration(
              borderRadius: radius,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(theme.isGlass ? 0.44 : 0.32),
                  blurRadius: lerpDouble(12, theme.isGlass ? 54 : 34, expansion)!,
                  offset: Offset(0, lerpDouble(8, 28, expansion)!),
                ),
                if (theme.isGlass)
                  BoxShadow(
                    color: theme.accent.withOpacity(0.34),
                    blurRadius: 70,
                    offset: const Offset(0, 18),
                  ),
              ],
            ),
            child: SongArtwork(songId: song.id, size: size, borderRadius: radius),
          ),
        ),
      ),
    );
  }

  static Widget _flightShuttleBuilder(
    BuildContext flightContext,
    Animation<double> animation,
    HeroFlightDirection flightDirection,
    BuildContext fromHeroContext,
    BuildContext toHeroContext,
  ) {
    return AnimatedBuilder(
      animation: animation,
      builder: (context, child) {
        return Transform.scale(
          scale: lerpDouble(0.985, 1, Curves.easeOutCubic.transform(animation.value))!,
          child: child,
        );
      },
      child: flightDirection == HeroFlightDirection.push
          ? (toHeroContext.widget as Hero).child
          : (fromHeroContext.widget as Hero).child,
    );
  }
}

class NowPlayingMetadata extends StatelessWidget {
  final LocalSong song;
  final NowPlayingThemeData theme;
  final bool centered;
  final double titleSize;
  final int maxTitleLines;

  const NowPlayingMetadata({
    super.key,
    required this.song,
    required this.theme,
    this.centered = false,
    this.titleSize = 24,
    this.maxTitleLines = 1,
  });

  @override
  Widget build(BuildContext context) {
    final alignment = centered ? CrossAxisAlignment.center : CrossAxisAlignment.start;
    final textAlign = centered ? TextAlign.center : TextAlign.start;
    return Column(
      crossAxisAlignment: alignment,
      mainAxisSize: MainAxisSize.min,
      children: [
        Hero(
          tag: PlayerHeroTags.title(song),
          flightShuttleBuilder: _titleFlightShuttleBuilder,
          child: Material(
            type: MaterialType.transparency,
            child: Text(
              song.title,
              maxLines: maxTitleLines,
              overflow: TextOverflow.ellipsis,
              textAlign: textAlign,
              style: TextStyle(
                color: theme.primaryText,
                fontWeight: FontWeight.w800,
                fontSize: titleSize,
                height: 1.05,
                letterSpacing: -0.3,
              ),
            ),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          song.artist,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: textAlign,
          style: TextStyle(
            color: theme.secondaryText,
            fontSize: math.max(13, titleSize - 6),
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }

  static Widget _titleFlightShuttleBuilder(
    BuildContext flightContext,
    Animation<double> animation,
    HeroFlightDirection flightDirection,
    BuildContext fromHeroContext,
    BuildContext toHeroContext,
  ) {
    return Material(
      type: MaterialType.transparency,
      child: FadeTransition(
        opacity: CurvedAnimation(parent: animation, curve: Curves.easeOutCubic),
        child: flightDirection == HeroFlightDirection.push
            ? (toHeroContext.widget as Hero).child
            : (fromHeroContext.widget as Hero).child,
      ),
    );
  }
}

class NowPlayingProgress extends StatelessWidget {
  final NowPlayingThemeData theme;
  final String Function(Duration duration) formatTime;
  final bool compact;

  const NowPlayingProgress({
    super.key,
    required this.theme,
    required this.formatTime,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<Duration>(
      stream: AudioService.player.positionStream,
      initialData: AudioService.player.position,
      builder: (context, snapshot) {
        final position = snapshot.data ?? Duration.zero;
        final duration = AudioService.playbackState.value.duration;
        final durationMs = duration.inMilliseconds;
        final value = durationMs == 0 ? 0.0 : position.inMilliseconds.clamp(0, durationMs).toDouble();

        if (compact) {
          return ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              minHeight: 2.5,
              value: durationMs == 0 ? 0 : value / durationMs,
              backgroundColor: Colors.white.withOpacity(0.14),
              valueColor: AlwaysStoppedAnimation<Color>(theme.accent),
            ),
          );
        }

        return Column(
          children: [
            SliderTheme(
              data: SliderTheme.of(context).copyWith(
                trackHeight: theme.isGlass ? 6 : 5,
                activeTrackColor: theme.isGlass ? Colors.white : theme.accent,
                inactiveTrackColor: Colors.white.withOpacity(theme.isGlass ? 0.22 : 0.16),
                thumbColor: Colors.white,
                thumbShape: RoundSliderThumbShape(enabledThumbRadius: theme.isGlass ? 7 : 6, elevation: 0, pressedElevation: 2),
                overlayShape: const RoundSliderOverlayShape(overlayRadius: 18),
                overlayColor: theme.accent.withOpacity(0.18),
              ),
              child: Slider(
                min: 0,
                max: durationMs == 0 ? 1 : durationMs.toDouble(),
                value: value,
                onChanged: durationMs == 0 ? null : (newValue) => AudioService.seek(Duration(milliseconds: newValue.toInt())),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  _TimeLabel(formatTime(position), theme),
                  _TimeLabel('-${formatTime(duration - position)}', theme),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

class _TimeLabel extends StatelessWidget {
  final String text;
  final NowPlayingThemeData theme;

  const _TimeLabel(this.text, this.theme);

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: TextStyle(
        color: theme.secondaryText,
        fontSize: 12.5,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.1,
      ),
    );
  }
}

class NowPlayingTransportControls extends StatelessWidget {
  final AudioPlaybackState playbackState;
  final NowPlayingThemeData theme;
  final bool compact;

  const NowPlayingTransportControls({
    super.key,
    required this.playbackState,
    required this.theme,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    final canGoPrevious = playbackState.currentIndex > 0;
    final canGoNext = playbackState.currentIndex < playbackState.currentPlaylist.length - 1;

    if (compact) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _ControlButton(
            icon: playbackState.isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
            size: 34,
            enabled: !playbackState.isLoading,
            theme: theme,
            onPressed: _togglePlay(playbackState),
          ),
          _ControlButton(
            icon: Icons.skip_next_rounded,
            size: 31,
            enabled: canGoNext,
            theme: theme,
            onPressed: canGoNext ? AudioService.skipNext : null,
          ),
        ],
      );
    }

    return GlassSurface(
      theme: theme,
      strong: true,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      borderRadius: BorderRadius.circular(theme.isGlass ? 38 : 28),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _ControlButton(
            icon: CupertinoIcons.backward_fill,
            size: 36,
            enabled: canGoPrevious,
            theme: theme,
            onPressed: canGoPrevious ? AudioService.skipPrevious : null,
          ),
          AnimatedScale(
            scale: playbackState.isLoading ? 0.94 : 1,
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOutCubic,
            child: Container(
              width: 78,
              height: 78,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: theme.isGlass ? Colors.white.withOpacity(0.92) : theme.accent,
                boxShadow: [
                  BoxShadow(
                    color: theme.accent.withOpacity(0.42),
                    blurRadius: 28,
                    offset: const Offset(0, 12),
                  ),
                ],
              ),
              child: IconButton(
                onPressed: playbackState.isLoading ? null : _togglePlay(playbackState),
                icon: Icon(playbackState.isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded),
                iconSize: 46,
                color: theme.isGlass ? const Color(0xFF111113) : Colors.white,
              ),
            ),
          ),
          _ControlButton(
            icon: CupertinoIcons.forward_fill,
            size: 36,
            enabled: canGoNext,
            theme: theme,
            onPressed: canGoNext ? AudioService.skipNext : null,
          ),
        ],
      ),
    );
  }

  VoidCallback? _togglePlay(AudioPlaybackState state) {
    if (state.isLoading) return null;
    return () => state.isPlaying ? AudioService.pause() : AudioService.play();
  }
}

class _ControlButton extends StatelessWidget {
  final IconData icon;
  final double size;
  final bool enabled;
  final VoidCallback? onPressed;
  final NowPlayingThemeData theme;

  const _ControlButton({
    required this.icon,
    required this.size,
    required this.enabled,
    required this.onPressed,
    required this.theme,
  });

  @override
  Widget build(BuildContext context) {
    return IconButton(
      onPressed: enabled ? onPressed : null,
      splashRadius: size,
      icon: Icon(icon),
      iconSize: size,
      color: enabled ? theme.primaryText : Colors.white.withOpacity(0.24),
    );
  }
}
