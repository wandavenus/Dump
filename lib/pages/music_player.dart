import 'dart:ui';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../models/local_song.dart';
import '../services/audio_service.dart';
import '../themes/theme_controller.dart';
import '../widgets/now_playing/now_playing_components.dart';
import '../widgets/song_artwork.dart';

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
    setState(() {
      _dragOffset = (_dragOffset + details.delta.dy).clamp(0.0, 520.0).toDouble();
    });
  }

  void _onVerticalDragEnd(DragEndDetails details) {
    final velocity = details.primaryVelocity ?? 0;
    if (_dragOffset > 130 || velocity > 620) {
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
        return ValueListenableBuilder<bool>(
          valueListenable: ThemeController.glassTheme,
          builder: (context, isGlass, _) {
            return DynamicArtworkPalette(
              song: song,
              isGlass: isGlass,
              builder: (context, theme) {
                final progress = (_dragOffset / 520).clamp(0.0, 1.0);
                return Scaffold(
                  backgroundColor: Colors.transparent,
                  extendBodyBehindAppBar: true,
                  body: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onVerticalDragUpdate: _onVerticalDragUpdate,
                    onVerticalDragEnd: _onVerticalDragEnd,
                    child: AnimatedContainer(
                      duration: _dragOffset == 0 ? const Duration(milliseconds: 360) : Duration.zero,
                      curve: Curves.easeOutCubic,
                      transform: Matrix4.translationValues(0, _dragOffset, 0)..scale(lerpDouble(1, 0.94, progress)!),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(lerpDouble(0, 30, progress)!),
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            NowPlayingBackground(song: song, theme: theme),
                            SafeArea(
                              bottom: false,
                              child: song == null
                                  ? const _EmptyPlayerState()
                                  : _ExpandedNowPlaying(
                                      song: song,
                                      playbackState: playbackState,
                                      theme: theme,
                                      formatTime: _formatTime,
                                      lyrics: _lyrics,
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
          },
        );
      },
    );
  }
}

class _ExpandedNowPlaying extends StatelessWidget {
  final LocalSong song;
  final AudioPlaybackState playbackState;
  final NowPlayingThemeData theme;
  final String Function(Duration duration) formatTime;
  final String lyrics;

  const _ExpandedNowPlaying({
    required this.song,
    required this.playbackState,
    required this.theme,
    required this.formatTime,
    required this.lyrics,
  });

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final coverSize = (size.width - 54).clamp(268.0, theme.isGlass ? 430.0 : 390.0).toDouble();

    return Stack(
      children: [
        Positioned(
          top: 4,
          left: 0,
          right: 0,
          child: Center(
            child: Container(
              width: 42,
              height: 4,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(999),
                color: Colors.white.withOpacity(0.32),
              ),
            ),
          ),
        ),
        Positioned.fill(
          child: SingleChildScrollView(
            physics: const ClampingScrollPhysics(),
            padding: EdgeInsets.fromLTRB(22, 30, 22, MediaQuery.of(context).padding.bottom + 22),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _TopBar(theme: theme),
                SizedBox(height: theme.isGlass ? 22 : 14),
                Center(
                  child: NowPlayingArtwork(
                    song: song,
                    size: coverSize,
                    theme: theme,
                  ),
                ),
                SizedBox(height: theme.isGlass ? 36 : 30),
                _PlayerInfoCard(
                  song: song,
                  playbackState: playbackState,
                  theme: theme,
                  formatTime: formatTime,
                  lyrics: lyrics,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _TopBar extends StatelessWidget {
  final NowPlayingThemeData theme;

  const _TopBar({required this.theme});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        _RoundAction(
          icon: CupertinoIcons.chevron_down,
          theme: theme,
          onPressed: () => Navigator.maybePop(context),
        ),
        const Spacer(),
        Text(
          'Now Playing',
          style: TextStyle(
            color: theme.secondaryText,
            fontWeight: FontWeight.w800,
            fontSize: 13,
            letterSpacing: 0.8,
          ),
        ),
        const Spacer(),
        _RoundAction(
          icon: Icons.more_horiz_rounded,
          theme: theme,
          onPressed: () {},
        ),
      ],
    );
  }
}

class _PlayerInfoCard extends StatelessWidget {
  final LocalSong song;
  final AudioPlaybackState playbackState;
  final NowPlayingThemeData theme;
  final String Function(Duration duration) formatTime;
  final String lyrics;

  const _PlayerInfoCard({
    required this.song,
    required this.playbackState,
    required this.theme,
    required this.formatTime,
    required this.lyrics,
  });

  @override
  Widget build(BuildContext context) {
    final child = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: NowPlayingMetadata(
                song: song,
                theme: theme,
                titleSize: theme.isGlass ? 27 : 25,
                maxTitleLines: 2,
              ),
            ),
            const SizedBox(width: 14),
            _FavoriteButton(theme: theme),
          ],
        ),
        const SizedBox(height: 24),
        NowPlayingProgress(theme: theme, formatTime: formatTime),
        const SizedBox(height: 26),
        NowPlayingTransportControls(playbackState: playbackState, theme: theme),
        const SizedBox(height: 22),
        _SecondaryControlRail(theme: theme, lyrics: lyrics),
      ],
    );

    if (!theme.isGlass) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2),
        child: child,
      );
    }

    return GlassSurface(
      theme: theme,
      strong: false,
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 18),
      borderRadius: BorderRadius.circular(34),
      child: child,
    );
  }
}

class _FavoriteButton extends StatefulWidget {
  final NowPlayingThemeData theme;

  const _FavoriteButton({required this.theme});

  @override
  State<_FavoriteButton> createState() => _FavoriteButtonState();
}

class _FavoriteButtonState extends State<_FavoriteButton> {
  bool _selected = false;

  @override
  Widget build(BuildContext context) {
    return _RoundAction(
      icon: _selected ? Icons.favorite_rounded : Icons.favorite_border_rounded,
      theme: widget.theme,
      active: _selected,
      onPressed: () => setState(() => _selected = !_selected),
    );
  }
}

class _SecondaryControlRail extends StatelessWidget {
  final NowPlayingThemeData theme;
  final String lyrics;

  const _SecondaryControlRail({required this.theme, required this.lyrics});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        _PillAction(icon: CupertinoIcons.shuffle, label: 'Shuffle', theme: theme, onPressed: () {}),
        _PillAction(icon: CupertinoIcons.quote_bubble, label: 'Lyrics', theme: theme, onPressed: () => _showLyrics(context)),
        _PillAction(icon: CupertinoIcons.list_bullet, label: 'Queue', theme: theme, onPressed: () => _showQueue(context)),
        _PillAction(icon: CupertinoIcons.repeat, label: 'Repeat', theme: theme, onPressed: () {}),
      ],
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
          theme: theme,
          child: SingleChildScrollView(
            child: Text(
              lyrics,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 20, height: 2, color: theme.primaryText),
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
          theme: theme,
          child: ValueListenableBuilder<AudioPlaybackState>(
            valueListenable: AudioService.playbackState,
            builder: (context, state, _) {
              return ListView.builder(
                itemCount: state.currentPlaylist.length,
                itemBuilder: (context, index) {
                  final queuedSong = state.currentPlaylist[index];
                  final isCurrent = index == state.currentIndex;

                  return ListTile(
                    onTap: () => AudioService.playFromCurrentQueue(index),
                    leading: SongArtwork(
                      songId: queuedSong.id,
                      size: 46,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    title: Text(
                      queuedSong.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: theme.primaryText, fontWeight: FontWeight.w700),
                    ),
                    subtitle: Text(
                      queuedSong.artist,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: theme.secondaryText),
                    ),
                    trailing: isCurrent ? Icon(Icons.equalizer, color: theme.accent) : null,
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

class _RoundAction extends StatelessWidget {
  final IconData icon;
  final NowPlayingThemeData theme;
  final VoidCallback? onPressed;
  final bool active;

  const _RoundAction({
    required this.icon,
    required this.theme,
    required this.onPressed,
    this.active = false,
  });

  @override
  Widget build(BuildContext context) {
    return GlassSurface(
      theme: theme,
      strong: active,
      padding: EdgeInsets.zero,
      borderRadius: BorderRadius.circular(999),
      child: SizedBox(
        width: 44,
        height: 44,
        child: IconButton(
          onPressed: onPressed,
          icon: Icon(icon),
          color: active ? theme.accent : theme.primaryText,
          iconSize: 22,
        ),
      ),
    );
  }
}

class _PillAction extends StatelessWidget {
  final IconData icon;
  final String label;
  final NowPlayingThemeData theme;
  final VoidCallback onPressed;

  const _PillAction({
    required this.icon,
    required this.label,
    required this.theme,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(18),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, color: theme.secondaryText, size: 22),
                const SizedBox(height: 5),
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: theme.secondaryText,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _BottomSheetScaffold extends StatelessWidget {
  final String title;
  final Widget child;
  final NowPlayingThemeData theme;

  const _BottomSheetScaffold({
    required this.title,
    required this.child,
    required this.theme,
  });

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: GlassSurface(
          theme: theme,
          strong: true,
          padding: const EdgeInsets.all(20),
          borderRadius: BorderRadius.circular(30),
          child: SizedBox(
            height: MediaQuery.of(context).size.height * 0.75,
            child: Column(
              children: [
                Container(
                  width: 42,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.white24,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: theme.primaryText,
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
    return const Center(
      child: Text(
        'No song playing',
        style: TextStyle(color: Colors.white70, fontSize: 18),
      ),
    );
  }
}
