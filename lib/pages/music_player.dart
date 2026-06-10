import 'dart:typed_data';
import 'dart:ui';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';

import '../models/local_song.dart';
import '../services/audio_service.dart';
import '../services/media_store_service.dart';
import '../themes/apple_music_blur.dart';
import '../widgets/song_artwork.dart';

class PlayerHeroTags {
  const PlayerHeroTags._();

  static String artwork(LocalSong song) => 'player-artwork-${song.id}-${song.path}';
  static String title(LocalSong song) => 'player-title-${song.id}-${song.path}';
}

class MusicPlayer extends StatefulWidget {
  const MusicPlayer({super.key});

  @override
  State<MusicPlayer> createState() => _MusicPlayerState();
}

class _MusicPlayerState extends State<MusicPlayer> {
  bool _handledRouteArguments = false;
  double _dragOffset = 0;
  final String _lyrics = 'Loading lyrics...';

  @override
  void initState() {
    super.initState();
    AudioService.initialize();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_handledRouteArguments) return;
    _handledRouteArguments = true;
    _playRouteSongIfNeeded();
  }

  Future<void> _playRouteSongIfNeeded() async {
    final arguments = ModalRoute.of(context)?.settings.arguments;
    if (arguments is! Map<String, dynamic>) return;

    final rawIndex = arguments['index'];
    final rawSongs = arguments['songs'];
    if (rawIndex is! int || rawSongs is! List) return;

    final songs = rawSongs.whereType<LocalSong>().toList(growable: false);
    if (songs.isEmpty || rawIndex < 0 || rawIndex >= songs.length) return;

    try {
      await AudioService.playSongAt(playlist: songs, index: rawIndex);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error playing song: $error')),
      );
    }
  }

  String _formatTime(Duration duration) {
    final safeDuration = duration.isNegative ? Duration.zero : duration;
    final minutes = safeDuration.inMinutes.remainder(60);
    final seconds = safeDuration.inSeconds.remainder(60);
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }

  void _onVerticalDragUpdate(DragUpdateDetails details) {
    if (details.delta.dy < 0 && _dragOffset == 0) return;

    setState(() {
      _dragOffset = (_dragOffset + details.delta.dy).clamp(0.0, 500.0).toDouble();
    });
  }

  void _onVerticalDragEnd(DragEndDetails details) {
    final velocity = details.primaryVelocity ?? 0;
    if (_dragOffset > 160 || velocity > 800) {
      Navigator.maybePop(context);
      return;
    }

    setState(() {
      _dragOffset = 0;
    });
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<AudioPlaybackState>(
      valueListenable: AudioService.playbackState,
      builder: (context, playbackState, _) {
        final song = playbackState.currentSong;

        return Scaffold(
          backgroundColor: AppleMusicColors.background,
          extendBodyBehindAppBar: true,
          body: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onVerticalDragUpdate: _onVerticalDragUpdate,
            onVerticalDragEnd: _onVerticalDragEnd,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 240),
              curve: Curves.easeOutCubic,
              transform: Matrix4.translationValues(0, _dragOffset, 0),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  _AnimatedBlurredPlayerBackground(songId: song?.id ?? 0),
                  SafeArea(
                    child: song == null
                        ? const _EmptyPlayerState()
                        : _PlayerContent(
                            song: song,
                            playbackState: playbackState,
                            formatTime: _formatTime,
                            lyrics: _lyrics,
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
}

class _PlayerContent extends StatelessWidget {
  final LocalSong song;
  final AudioPlaybackState playbackState;
  final String Function(Duration duration) formatTime;
  final String lyrics;

  const _PlayerContent({
    required this.song,
    required this.playbackState,
    required this.formatTime,
    required this.lyrics,
  });

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final coverSize = (width - 44).clamp(260.0, 390.0).toDouble();

    return Column(
      children: [

        Expanded(
          child: SingleChildScrollView(
            physics: const ClampingScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(22, 8, 22, 30),
            child: Column(
              children: [
                const SizedBox(height: 18),
                Hero(
                  tag: PlayerHeroTags.artwork(song),
                  flightShuttleBuilder: _artworkFlightShuttleBuilder,
                  child: Material(
                    type: MaterialType.transparency,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(AppleMusicRadii.artwork),
                        boxShadow: const [
                          BoxShadow(
                            color: Color(0x66000000),
                            blurRadius: 42,
                            offset: Offset(0, 24),
                          ),
                        ],
                      ),
                      child: SongArtwork(
                        songId: song.id,
                        size: coverSize,
                        borderRadius: BorderRadius.circular(
                          AppleMusicRadii.artwork,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 38),
                _SongHeader(song: song),
                const SizedBox(height: 22),
                _ProgressSection(formatTime: formatTime),
                const SizedBox(height: 28),
                _TransportControls(playbackState: playbackState),
                const SizedBox(height: 32),
                _SecondaryControls(lyrics: lyrics),
              ],
            ),
          ),
        ),
      ],
    );
  }

  static Widget _artworkFlightShuttleBuilder(
    BuildContext flightContext,
    Animation<double> animation,
    HeroFlightDirection flightDirection,
    BuildContext fromHeroContext,
    BuildContext toHeroContext,
  ) {
    return AnimatedBuilder(
      animation: animation,
      builder: (context, child) {
        return Material(
          type: MaterialType.transparency,
          child: Transform.scale(
            scale: lerpDouble(0.98, 1.0, Curves.easeOutCubic.transform(animation.value))!,
            child: child,
          ),
        );
      },
      child: flightDirection == HeroFlightDirection.push
          ? (toHeroContext.widget as Hero).child
          : (fromHeroContext.widget as Hero).child,
    );
  }
}

class _SongHeader extends StatelessWidget {
  final LocalSong song;

  const _SongHeader({required this.song});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Hero(
                tag: PlayerHeroTags.title(song),
                flightShuttleBuilder: _titleFlightShuttleBuilder,
                child: Material(
                  type: MaterialType.transparency,
                  child: Text(
                    song.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: AppleMusicColors.label,
                      fontWeight: FontWeight.w700,
                      fontSize: 25,
                      letterSpacing: -0.4,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                song.artist,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: AppleMusicColors.secondaryLabel,
                  fontSize: 18,
                  fontWeight: FontWeight.w400,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 16),
        AppleMusicIconMaterial(
          onTap: () {},
          child: const Icon(
            Icons.more_horiz_rounded,
            color: AppleMusicColors.label,
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
        opacity: CurvedAnimation(parent: animation, curve: Curves.easeOut),
        child: flightDirection == HeroFlightDirection.push
            ? (toHeroContext.widget as Hero).child
            : (fromHeroContext.widget as Hero).child,
      ),
    );
  }
}

class _ProgressSection extends StatelessWidget {
  final String Function(Duration duration) formatTime;

  const _ProgressSection({required this.formatTime});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<Duration>(
      stream: AudioService.player.positionStream,
      initialData: AudioService.player.position,
      builder: (context, snapshot) {
        final position = snapshot.data ?? Duration.zero;
        final duration = AudioService.playbackState.value.duration;
        final durationSeconds = duration.inSeconds;
        final value = durationSeconds == 0
            ? 0.0
            : position.inSeconds.clamp(0, durationSeconds).toDouble();

        return Column(
          children: [
            SliderTheme(
              data: SliderTheme.of(context).copyWith(
                trackHeight: 4,
                activeTrackColor: AppleMusicColors.label,
                inactiveTrackColor: Colors.white.withOpacity(0.18),
                thumbShape: const RoundSliderThumbShape(
                  enabledThumbRadius: 5,
                  elevation: 0,
                  pressedElevation: 0,
                ),
                overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
                overlayColor: Colors.white.withOpacity(0.16),
              ),
              child: Slider(
                min: 0,
                max: durationSeconds == 0 ? 1 : durationSeconds.toDouble(),
                value: value,
                onChanged: durationSeconds == 0
                    ? null
                    : (newValue) {
                        AudioService.seek(Duration(seconds: newValue.toInt()));
                      },
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    formatTime(position),
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                      color: AppleMusicColors.secondaryLabel,
                    ),
                  ),
                  Text(
                    '-${formatTime(duration - position)}',
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                      color: AppleMusicColors.secondaryLabel,
                    ),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

class _TransportControls extends StatelessWidget {
  final AudioPlaybackState playbackState;

  const _TransportControls({required this.playbackState});

  @override
  Widget build(BuildContext context) {
    final canGoPrevious = playbackState.currentIndex > 0;
    final canGoNext =
        playbackState.currentIndex < playbackState.currentPlaylist.length - 1;

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        IconButton(
          icon: Icon(
            Icons.fast_rewind_rounded,
            size: 64,
            color: canGoPrevious ? AppleMusicColors.label : AppleMusicColors.tertiaryLabel,
          ),
          onPressed: canGoPrevious ? () => AudioService.skipPrevious() : null,
        ),
        const SizedBox(width: 10),
        IconButton(
          icon: Icon(
            playbackState.isPlaying
                ? Icons.pause_rounded
                : Icons.play_arrow_rounded,
            size: 76,
            color: AppleMusicColors.label,
          ),
          onPressed: playbackState.isLoading
              ? null
              : () {
                  playbackState.isPlaying
                      ? AudioService.pause()
                      : AudioService.play();
                },
        ),
        const SizedBox(width: 10),
        IconButton(
          icon: Icon(
            Icons.fast_forward_rounded,
            size: 64,
            color: canGoNext ? AppleMusicColors.label : AppleMusicColors.tertiaryLabel,
          ),
          onPressed: canGoNext ? () => AudioService.skipNext() : null,
        ),
      ],
    );
  }
}

class _SecondaryControls extends StatelessWidget {
  final String lyrics;

  const _SecondaryControls({required this.lyrics});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: AppleMusicMaterial(
        style: AppleMusicMaterialStyle.ultraThin,
        borderRadius: BorderRadius.circular(AppleMusicRadii.floating),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 6),
        showShadow: false,
        child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          IconButton(
            onPressed: () => _showLyrics(context),
            icon: const Icon(CupertinoIcons.quote_bubble, size: 26),
          ),
          IconButton(
            onPressed: () => _showQueue(context),
            icon: const Icon(CupertinoIcons.list_bullet, size: 26),
          ),
        ],
        ),
      ),
    );
  }

  void _showLyrics(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return _BottomSheetScaffold(
          title: 'Lyrics',
          child: SingleChildScrollView(
            child: Text(
              lyrics,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 20, height: 2),
            ),
          ),
        );
      },
    );
  }

  void _showQueue(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return _BottomSheetScaffold(
          title: 'Queue',
          child: ValueListenableBuilder<AudioPlaybackState>(
            valueListenable: AudioService.playbackState,
            builder: (context, state, _) {
              return ListView.builder(
                itemCount: state.currentPlaylist.length,
                itemBuilder: (context, index) {
                  final song = state.currentPlaylist[index];
                  final isCurrent = index == state.currentIndex;

                  return ListTile(
                    onTap: () => AudioService.playFromCurrentQueue(index),
                    title: Text(
                      song.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: Text(
                      song.artist,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    trailing: isCurrent
                        ? const Icon(Icons.equalizer, color: AppleMusicColors.accent)
                        : null,
                  );
                },
              );
            },
          ),
        );
      },
    );
  }
}

class _BottomSheetScaffold extends StatelessWidget {
  final String title;
  final Widget child;

  const _BottomSheetScaffold({
    required this.title,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
        child: AppleMusicMaterial(
          style: AppleMusicMaterialStyle.prominent,
          borderRadius: const BorderRadius.vertical(
            top: Radius.circular(AppleMusicRadii.sheet),
            bottom: Radius.circular(AppleMusicRadii.card),
          ),
          padding: const EdgeInsets.all(20),
          child: SizedBox(
            height: MediaQuery.of(context).size.height * 0.75,
            child: Column(
              children: [
                Container(
                  width: 42,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.28),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  title,
                  style: const TextStyle(
                    color: AppleMusicColors.label,
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.2,
                  ),
                ),
                const SizedBox(height: 20),
                Expanded(child: child),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _EmptyPlayerState extends StatelessWidget {
  const _EmptyPlayerState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.music_note, size: 64, color: Colors.white38),
          const SizedBox(height: 16),
          const Text(
            'No song selected',
            style: TextStyle(color: AppleMusicColors.secondaryLabel, fontSize: 18),
          ),
          const SizedBox(height: 24),
          TextButton(
            onPressed: () => Navigator.maybePop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }
}

class _AnimatedBlurredPlayerBackground extends StatefulWidget {
  final int songId;

  const _AnimatedBlurredPlayerBackground({required this.songId});

  @override
  State<_AnimatedBlurredPlayerBackground> createState() =>
      _AnimatedBlurredPlayerBackgroundState();
}

class _AnimatedBlurredPlayerBackgroundState
    extends State<_AnimatedBlurredPlayerBackground> {
  Future<Uint8List?>? _artworkFuture;

  @override
  void initState() {
    super.initState();
    _updateArtworkFuture();
  }

  @override
  void didUpdateWidget(_AnimatedBlurredPlayerBackground oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.songId != widget.songId) {
      _updateArtworkFuture();
    }
  }

  void _updateArtworkFuture() {
    _artworkFuture = widget.songId > 0
        ? MediaStoreService.getArtwork(widget.songId)
        : Future<Uint8List?>.value();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Uint8List?>(
      key: ValueKey<int>(widget.songId),
      future: _artworkFuture,
      builder: (context, snapshot) {
        final artwork = snapshot.data;
        final child = artwork == null || artwork.isEmpty
            ? const _PlayerFallbackBackground(key: ValueKey<String>('fallback'))
            : _BlurredArtworkBackground(
                key: ValueKey<int>(widget.songId),
                artwork: artwork,
              );

        return AnimatedSwitcher(
          duration: const Duration(milliseconds: 420),
          switchInCurve: Curves.easeOutCubic,
          switchOutCurve: Curves.easeOutCubic,
          child: child,
        );
      },
    );
  }
}

class _BlurredArtworkBackground extends StatelessWidget {
  final Uint8List artwork;

  const _BlurredArtworkBackground({super.key, required this.artwork});

  @override
  Widget build(BuildContext context) {
    return AppleMusicArtworkBackground(artwork: artwork);
  }
}

class _PlayerFallbackBackground extends StatelessWidget {
  const _PlayerFallbackBackground({super.key});

  @override
  Widget build(BuildContext context) {
    return const AppleMusicArtworkBackground();
  }
}
