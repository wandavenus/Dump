import 'dart:ui';
import 'dart:typed_data';
import '../services/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:just_audio/just_audio.dart';
import 'package:just_audio_background/just_audio_background.dart';
import 'package:on_audio_query/on_audio_query.dart';
import 'package:palette_generator/palette_generator.dart';

class MusicPlayer extends StatefulWidget {
  const MusicPlayer({super.key});

  @override
  State<MusicPlayer> createState() => _MusicPlayerState();
}

class _MusicPlayerState extends State<MusicPlayer>
    with TickerProviderStateMixin {
  final AudioPlayer audioPlayer = AudioService.player;
  final OnAudioQuery audioQuery = OnAudioQuery();

  bool isPlaying = false;
  Duration duration = Duration.zero;
  Duration position = Duration.zero;
  bool isLoading = false;
  int currentIndex = 0;

  bool isShuffle = false;
  bool isRepeat = false;
  bool isFavorite = false;

  double dragOffset = 0;
  double volume = 0.8;

  // Dynamic bg colors
  Color dominantColor = const Color(0xFF2C2C2E);
  Color secondaryColor = const Color(0xFF000000);

  late AnimationController _artworkScaleController;
  late Animation<double> _artworkScale;

  @override
  void initState() {
    super.initState();

    _artworkScaleController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 350),
    );
    _artworkScale = Tween<double>(begin: 0.85, end: 1.0).animate(
      CurvedAnimation(parent: _artworkScaleController, curve: Curves.easeOut),
    );

    _setupAudioPlayer();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      final args = ModalRoute.of(context)?.settings.arguments
          as Map<String, dynamic>?;
      if (args != null && args.containsKey('index')) {
        setState(() => currentIndex = args['index'] as int);
        AudioService.currentIndex = currentIndex;
        AudioService.currentPlaylist = args['songs'] ?? [];
        _loadSong(currentIndex);
      } else {
        _extractPalette();
        if (AudioService.isPlaying) _artworkScaleController.forward();
      }
    });
  }

  void _setupAudioPlayer() {
    audioPlayer.playerStateStream.listen((state) {
      if (!mounted) return;
      setState(() => isPlaying = state.playing);
      AudioService.isPlaying = state.playing;

      if (state.playing) {
        _artworkScaleController.forward();
      } else {
        _artworkScaleController.reverse();
      }
    });

    audioPlayer.durationStream.listen((d) {
      if (mounted) setState(() => duration = d ?? Duration.zero);
    });

    audioPlayer.positionStream.listen((p) {
      if (mounted) setState(() => position = p);
    });

    audioPlayer.processingStateStream.listen((state) {
      if (state == ProcessingState.completed) _playNext();
    });
  }

  Future<void> _loadSong(int index) async {
    if (!mounted) return;
    setState(() {
      isLoading = true;
      currentIndex = index;
    });

    AudioService.currentIndex = index;

    final args = ModalRoute.of(context)?.settings.arguments
        as Map<String, dynamic>?;
    final List<SongModel> playlist =
        args?['songs'] ?? AudioService.currentPlaylist;

    if (playlist.isEmpty || index >= playlist.length) {
      setState(() => isLoading = false);
      return;
    }

    final song = playlist[index];
    AudioService.currentSong = song;

    try {
      await audioPlayer.stop();
      await audioPlayer.setAudioSource(
        AudioSource.file(
          song.data,
          tag: MediaItem(
            id: song.id.toString(),
            title: song.title,
            artist: song.artist ?? 'Unknown Artist',
            artUri: Uri.parse(
              'content://media/external/audio/albumart/${song.albumId}',
            ),
          ),
        ),
      );
      await audioPlayer.play();
      await _extractPalette();
    } catch (e) {
      debugPrint('Error loading song: $e');
    } finally {
      if (mounted) setState(() => isLoading = false);
    }
  }

  Future<void> _extractPalette() async {
    if (AudioService.currentSong == null) return;
    try {
      final Uint8List? artwork = await audioQuery.queryArtwork(
        AudioService.currentSong!.id,
        ArtworkType.AUDIO,
        size: 200,
      );
      if (artwork == null || !mounted) return;

      final palette = await PaletteGenerator.fromImageProvider(
        MemoryImage(artwork),
        size: const Size(200, 200),
      );

      if (!mounted) return;
      setState(() {
        dominantColor =
            palette.dominantColor?.color ?? const Color(0xFF2C2C2E);
        secondaryColor = palette.darkVibrantColor?.color ??
            palette.darkMutedColor?.color ??
            Colors.black;
      });
    } catch (e) {
      debugPrint('Palette error: $e');
    }
  }

  void _playNext() {
    final playlist = AudioService.currentPlaylist;
    if (playlist.isEmpty) return;
    if (isRepeat) {
      _loadSong(currentIndex);
    } else if (isShuffle) {
      final rand = DateTime.now().millisecondsSinceEpoch % playlist.length;
      _loadSong(rand);
    } else if (currentIndex < playlist.length - 1) {
      _loadSong(currentIndex + 1);
    }
  }

  void _playPrev() {
    if (position.inSeconds > 3) {
      audioPlayer.seek(Duration.zero);
    } else if (currentIndex > 0) {
      _loadSong(currentIndex - 1);
    }
  }

  String _fmt(Duration d) {
    final m = d.inMinutes.remainder(60);
    final s = d.inSeconds.remainder(60);
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  @override
  void dispose() {
    _artworkScaleController.dispose();
    super.dispose();
  }

  // ─── UI ────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final screenW = MediaQuery.of(context).size.width;
    final coverSize = screenW - 48.0;
    final remaining = duration > position ? duration - position : Duration.zero;

    return Scaffold(
      backgroundColor: Colors.black,
      body: GestureDetector(
        onVerticalDragUpdate: (d) {
          setState(() {
            dragOffset = (dragOffset + d.delta.dy).clamp(0.0, 500.0);
          });
        },
        onVerticalDragEnd: (d) {
          if (dragOffset > 120 || (d.primaryVelocity ?? 0) > 1000) {
            Navigator.pop(context);
          } else {
            setState(() => dragOffset = 0);
          }
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOutCubic,
          transform: Matrix4.translationValues(0, dragOffset, 0),
          child: Stack(
            children: [
              // ── Dynamic gradient background ──
              AnimatedContainer(
                duration: const Duration(milliseconds: 700),
                curve: Curves.easeInOut,
                width: double.infinity,
                height: double.infinity,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      dominantColor,
                      Color.lerp(dominantColor, Colors.black, 0.5)!,
                      Colors.black,
                    ],
                    stops: const [0.0, 0.45, 1.0],
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                  ),
                ),
              ),

              // ── Noise/grain overlay for depth ──
              Opacity(
                opacity: 0.04,
                child: Container(
                  decoration: const BoxDecoration(color: Colors.white),
                ),
              ),

              // ── Content ──
              SafeArea(
                child: Column(
                  children: [
                    _buildHandle(),
                    _buildHeader(),
                    const SizedBox(height: 24),
                    _buildArtwork(coverSize),
                    const SizedBox(height: 28),
                    _buildSongInfo(),
                    const SizedBox(height: 20),
                    _buildProgressBar(remaining),
                    const SizedBox(height: 8),
                    _buildTimeLabels(remaining),
                    const SizedBox(height: 24),
                    _buildControls(),
                    const SizedBox(height: 24),
                    _buildVolumeSlider(),
                    const SizedBox(height: 28),
                    _buildBottomActions(),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Drag handle pill ─────────────────────────────────────────────────────
  Widget _buildHandle() {
    return Padding(
      padding: const EdgeInsets.only(top: 10, bottom: 2),
      child: Container(
        width: 36,
        height: 4,
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.3),
          borderRadius: BorderRadius.circular(2),
        ),
      ),
    );
  }

  // ── Header row ───────────────────────────────────────────────────────────
  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      child: Row(
        children: [
          _headerIconBtn(
            CupertinoIcons.chevron_down,
            onTap: () => Navigator.pop(context),
          ),
          Expanded(
            child: Column(
              children: [
                Text(
                  'PLAYING FROM LIBRARY',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: Colors.white.withOpacity(0.6),
                    letterSpacing: 0.8,
                  ),
                ),
                const SizedBox(height: 2),
                const Text(
                  'All Songs',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
              ],
            ),
          ),
          _headerIconBtn(CupertinoIcons.ellipsis),
        ],
      ),
    );
  }

  Widget _headerIconBtn(IconData icon, {VoidCallback? onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 32,
        height: 32,
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.15),
          shape: BoxShape.circle,
        ),
        child: Icon(icon, size: 15, color: Colors.white),
      ),
    );
  }

  // ── Artwork ───────────────────────────────────────────────────────────────
  Widget _buildArtwork(double size) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: AnimatedBuilder(
        animation: _artworkScale,
        builder: (_, child) => Transform.scale(
          scale: _artworkScale.value,
          child: child,
        ),
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              BoxShadow(
                color: dominantColor.withOpacity(0.6),
                blurRadius: 50,
                spreadRadius: 10,
                offset: const Offset(0, 20),
              ),
              BoxShadow(
                color: Colors.black.withOpacity(0.4),
                blurRadius: 20,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: QueryArtworkWidget(
              controller: audioQuery,
              id: AudioService.currentSong?.id ?? 0,
              type: ArtworkType.AUDIO,
              keepOldArtwork: true,
              artworkHeight: size,
              artworkWidth: size,
              artworkFit: BoxFit.cover,
              nullArtworkWidget: Container(
                color: const Color(0xFF2C2C2E),
                child: const Center(
                  child: Icon(
                    CupertinoIcons.music_note,
                    size: 80,
                    color: Colors.white30,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ── Song info + heart ────────────────────────────────────────────────────
  Widget _buildSongInfo() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 28),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  AudioService.currentSong?.title ?? 'Unknown Song',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 22,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  AudioService.currentSong?.artist ?? 'Unknown Artist',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w500,
                    color: Colors.white.withOpacity(0.65),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 16),
          GestureDetector(
            onTap: () => setState(() => isFavorite = !isFavorite),
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 200),
              transitionBuilder: (child, anim) =>
                  ScaleTransition(scale: anim, child: child),
              child: Icon(
                isFavorite
                    ? CupertinoIcons.heart_fill
                    : CupertinoIcons.heart,
                key: ValueKey(isFavorite),
                size: 27,
                color: isFavorite
                    ? const Color(0xFFF92D48)
                    : Colors.white.withOpacity(0.65),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Progress bar ─────────────────────────────────────────────────────────
  Widget _buildProgressBar(Duration remaining) {
    final maxMs =
        duration.inMilliseconds.toDouble().clamp(1.0, double.infinity);
    final curMs =
        position.inMilliseconds.clamp(0, duration.inMilliseconds).toDouble();

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: SliderTheme(
        data: SliderTheme.of(context).copyWith(
          trackHeight: 4,
          activeTrackColor: Colors.white,
          inactiveTrackColor: Colors.white.withOpacity(0.25),
          thumbColor: Colors.white,
          thumbShape: const RoundSliderThumbShape(
            enabledThumbRadius: 5,
            elevation: 0,
            pressedElevation: 0,
          ),
          overlayColor: Colors.transparent,
          trackShape: const RoundedRectSliderTrackShape(),
        ),
        child: Slider(
          min: 0,
          max: maxMs,
          value: curMs,
          onChanged: (v) async {
            await audioPlayer.seek(Duration(milliseconds: v.toInt()));
          },
        ),
      ),
    );
  }

  // ── Time labels ──────────────────────────────────────────────────────────
  Widget _buildTimeLabels(Duration remaining) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 28),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            _fmt(position),
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: Colors.white.withOpacity(0.65),
            ),
          ),
          Text(
            '-${_fmt(remaining)}',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: Colors.white.withOpacity(0.65),
            ),
          ),
        ],
      ),
    );
  }

  // ── Playback controls ────────────────────────────────────────────────────
  Widget _buildControls() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 28),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Shuffle
          GestureDetector(
            onTap: () => setState(() => isShuffle = !isShuffle),
            child: _controlIcon(
              CupertinoIcons.shuffle,
              size: 22,
              active: isShuffle,
            ),
          ),

          // Previous
          GestureDetector(
            onTap: _playPrev,
            child: Icon(
              CupertinoIcons.backward_end_fill,
              size: 40,
              color: Colors.white,
            ),
          ),

          // Play / Pause — big circle
          GestureDetector(
            onTap: () {
              isPlaying ? audioPlayer.pause() : audioPlayer.play();
            },
            child: Container(
              width: 72,
              height: 72,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white,
              ),
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 200),
                transitionBuilder: (child, anim) =>
                    ScaleTransition(scale: anim, child: child),
                child: isLoading
                    ? const CupertinoActivityIndicator(color: Colors.black)
                    : Icon(
                        isPlaying
                            ? CupertinoIcons.pause_fill
                            : CupertinoIcons.play_fill,
                        key: ValueKey(isPlaying),
                        size: 32,
                        color: Colors.black,
                      ),
              ),
            ),
          ),

          // Next
          GestureDetector(
            onTap: () {
              final p = AudioService.currentPlaylist;
              if (currentIndex < p.length - 1) _loadSong(currentIndex + 1);
            },
            child: const Icon(
              CupertinoIcons.forward_end_fill,
              size: 40,
              color: Colors.white,
            ),
          ),

          // Repeat
          GestureDetector(
            onTap: () => setState(() => isRepeat = !isRepeat),
            child: _controlIcon(
              isRepeat ? CupertinoIcons.repeat_1 : CupertinoIcons.repeat,
              size: 22,
              active: isRepeat,
            ),
          ),
        ],
      ),
    );
  }

  Widget _controlIcon(IconData icon,
      {required double size, bool active = false}) {
    return Stack(
      alignment: Alignment.bottomCenter,
      children: [
        Icon(icon,
            size: size,
            color: active
                ? const Color(0xFFF92D48)
                : Colors.white.withOpacity(0.7)),
        if (active)
          Positioned(
            bottom: -4,
            child: Container(
              width: 4,
              height: 4,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                color: Color(0xFFF92D48),
              ),
            ),
          ),
      ],
    );
  }

  // ── Volume slider ────────────────────────────────────────────────────────
  Widget _buildVolumeSlider() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 28),
      child: Row(
        children: [
          Icon(
            CupertinoIcons.speaker_fill,
            size: 15,
            color: Colors.white.withOpacity(0.5),
          ),
          Expanded(
            child: SliderTheme(
              data: SliderTheme.of(context).copyWith(
                trackHeight: 3.5,
                activeTrackColor: Colors.white.withOpacity(0.75),
                inactiveTrackColor: Colors.white.withOpacity(0.2),
                thumbColor: Colors.white,
                thumbShape: const RoundSliderThumbShape(
                  enabledThumbRadius: 5,
                  elevation: 0,
                ),
                overlayColor: Colors.transparent,
                trackShape: const RoundedRectSliderTrackShape(),
              ),
              child: Slider(
                value: volume,
                onChanged: (v) {
                  setState(() => volume = v);
                  audioPlayer.setVolume(v);
                },
              ),
            ),
          ),
          Icon(
            CupertinoIcons.speaker_3_fill,
            size: 15,
            color: Colors.white.withOpacity(0.5),
          ),
        ],
      ),
    );
  }

  // ── Bottom row: lyrics / airplay / queue ─────────────────────────────────
  Widget _buildBottomActions() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 44),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          _bottomBtn(
            CupertinoIcons.quote_bubble,
            onTap: _showLyrics,
          ),
          _bottomBtn(CupertinoIcons.airplayaudio),
          _bottomBtn(
            CupertinoIcons.list_bullet,
            onTap: _showQueue,
          ),
        ],
      ),
    );
  }

  Widget _bottomBtn(IconData icon, {VoidCallback? onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Icon(
        icon,
        size: 22,
        color: Colors.white.withOpacity(0.7),
      ),
    );
  }

  // ── Bottom sheets ────────────────────────────────────────────────────────
  void _showLyrics() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF1C1C1E),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => DraggableScrollableSheet(
        initialChildSize: 0.75,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        expand: false,
        builder: (_, controller) => Column(
          children: [
            _sheetHandle(),
            const SizedBox(height: 8),
            const Text(
              'Lyrics',
              style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Colors.white),
            ),
            const Expanded(
              child: Center(
                child: Text(
                  'Lyrics not available',
                  style: TextStyle(color: Colors.white38, fontSize: 16),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showQueue() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF1C1C1E),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => DraggableScrollableSheet(
        initialChildSize: 0.75,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        expand: false,
        builder: (_, controller) => Column(
          children: [
            _sheetHandle(),
            const SizedBox(height: 8),
            const Text(
              'Queue',
              style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Colors.white),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: ListView.builder(
                controller: controller,
                itemCount: AudioService.currentPlaylist.length,
                itemBuilder: (_, i) {
                  final s = AudioService.currentPlaylist[i];
                  final isCurrent = i == AudioService.currentIndex;
                  return ListTile(
                    title: Text(
                      s.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: isCurrent
                            ? const Color(0xFFF92D48)
                            : Colors.white,
                        fontWeight: isCurrent
                            ? FontWeight.w700
                            : FontWeight.normal,
                      ),
                    ),
                    subtitle: Text(
                      s.artist ?? 'Unknown Artist',
                      style: const TextStyle(color: Colors.white54),
                    ),
                    trailing: isCurrent
                        ? const Icon(
                            CupertinoIcons.speaker_2_fill,
                            color: Color(0xFFF92D48),
                            size: 18,
                          )
                        : null,
                    onTap: () {
                      Navigator.pop(context);
                      _loadSong(i);
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _sheetHandle() {
    return Padding(
      padding: const EdgeInsets.only(top: 10, bottom: 6),
      child: Container(
        width: 36,
        height: 4,
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.3),
          borderRadius: BorderRadius.circular(2),
        ),
      ),
    );
  }
}
