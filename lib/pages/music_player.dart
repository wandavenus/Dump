// import 'package:audioplayers/audioplayers.dart';
import '../services/audio_service.dart';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:just_audio_background/just_audio_background.dart';
import 'package:just_audio/just_audio.dart';
import 'package:on_audio_query/on_audio_query.dart';
import 'package:audiotags/audiotags.dart';
import 'package:flutter/cupertino.dart';

class MusicPlayer extends StatefulWidget {
  const MusicPlayer({super.key});

  @override
  State<MusicPlayer> createState() => _MusicPlayerState();
}

class _MusicPlayerState extends State<MusicPlayer> {
      
  //variable for music audioPlayer
  final AudioPlayer audioPlayer = AudioService.player;
  final OnAudioQuery audioQuery = OnAudioQuery();
  bool isPlaying = false;
  Duration duration = Duration.zero;
  Duration position = Duration.zero;
  String lyrics = 'Loading lyrics...';
  int currentIndex = 0;
  bool isLoading = false;
  double dragOffset = 0;

  @override
  void initState() {
    super.initState();
    // Initialize audio player
    setupAudioPlayer();
    

    WidgetsBinding.instance.addPostFrameCallback((_) {
  final routes =
      ModalRoute.of(context)?.settings.arguments
          as Map<String, dynamic>?;

  if (routes != null && routes.containsKey('index')) {
    setState(() {
      currentIndex = routes['index'] as int;
    });
AudioService.currentIndex = currentIndex;
AudioService.currentPlaylist = routes['songs'];
    _loadSong(currentIndex);
  }
});
 }
  void setupAudioPlayer() {
    // Listen to player state changes
    audioPlayer.playerStateStream.listen((PlayerState state) {
  setState(() {
    isPlaying = state.playing;
  });

  AudioService.isPlaying = state.playing;
});

    // Listen to duration changes
    audioPlayer.durationStream.listen((newDuration) {
      setState(() {
        duration = newDuration ?? Duration.zero;
      });
    });

    // Listen to position changes
    audioPlayer.positionStream.listen((newPosition) {
  if (mounted) {
    setState(() {
      position = newPosition;
    });
  }
});

    // Listen to sequence state for completion
    audioPlayer.processingStateStream.listen((state) {
      if (state == ProcessingState.completed) {
        setState(() {
          position = Duration.zero;
          isPlaying = false;
        });
        // Automatically play next song
        final routes =
    ModalRoute.of(context)?.settings.arguments
        as Map<String, dynamic>?;

final List<SongModel> allSongs = routes?['songs'] ?? [];

if (currentIndex < allSongs.length - 1) {
  currentIndex++;
  _loadSong(currentIndex);
}
      }
    });
  }

  Future<void> _loadSong(int index) async {
  setState(() {
    isLoading = true;
    currentIndex = index;
  });

  AudioService.currentIndex = currentIndex;

  SongModel selectedSong;

final routes =
    ModalRoute.of(context)?.settings.arguments
        as Map<String, dynamic>?;

final List<SongModel> allSongs = routes!['songs'];

selectedSong = allSongs[index];
AudioService.currentSong = selectedSong;
  
   try {
  await audioPlayer.stop();
  await audioPlayer.setAudioSource(
  AudioSource.file(
    selectedSong.data,
    tag: MediaItem(
  id: selectedSong.id.toString(),
  title: selectedSong.title,
  artist: selectedSong.artist ?? 'Unknown Artist',
  artUri: Uri.parse(
    'content://media/external/audio/albumart/${selectedSong.albumId}',
  ),
),
  ),
);
  await audioPlayer.play();
  
} catch (e) {
      print('Error loading song: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error playing song: ${e.toString()}')),
      );
    } finally {
      setState(() {
        isLoading = false;
      });
    }
  }

  String formatTime(Duration duration) {
    final minutes = duration.inMinutes.remainder(60);
    final seconds = duration.inSeconds.remainder(60);
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }

////////////
  

  
  @override
  Widget build(BuildContext context) {
   final coverSize =
    MediaQuery.of(context).size.width -
    (22 * 2);
 return Scaffold(
      extendBodyBehindAppBar: true,
      
      body: GestureDetector(
  onVerticalDragUpdate: (details) {
    setState(() {
      dragOffset =
          (dragOffset + details.delta.dy)
              .clamp(0.0, 500.0);
    });
  },
  onVerticalDragEnd: (details) {
    if (dragOffset > 200) {
      Navigator.pop(context);
    } else {
      setState(() {
        dragOffset = 0;
      });
    }
  },
  child: AnimatedContainer(
  duration: const Duration(milliseconds: 250),
  curve: Curves.easeOutCubic,
  transform: Matrix4.translationValues(
    0,
    dragOffset,
    0,
  ),
  child: Center(
        child: Container(
            decoration: const BoxDecoration(
  color: Color(0xFF1C1C1E),
),

            // height: 500,
            // width: 500,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const SizedBox(
                  height: 60,
                ),
                DecoratedBox(
                  decoration: BoxDecoration(
                    boxShadow: const [
  BoxShadow(
    color: Color.fromARGB(30, 0, 0, 0),
    blurRadius: 4,
    spreadRadius: 0,
  ),
],
                    shape: BoxShape.rectangle,
                    borderRadius: BorderRadius.circular(3.0),
                  ),
                  child: ClipPath(
                    clipper: ShapeBorderClipper(
                      shape: RoundedRectangleBorder(
  borderRadius: BorderRadius.circular(3.0),
)
                    ),
                    child: QueryArtworkWidget(
  controller: audioQuery,
  id: AudioService.currentSong?.id ?? 0,
  type: ArtworkType.AUDIO,

  keepOldArtwork: true,

  artworkHeight: coverSize,
  artworkWidth: coverSize,
  artworkFit: BoxFit.cover,
)
                  ),
                ),
                const SizedBox(
                  height: 60,
                ),
                Container(
                  // color: Color.fromARGB(255, 13, 0, 132),
                  padding: const EdgeInsets.only(left: 25),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      SizedBox(
                        // color: Colors.blue,
                        width: 270,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
  AudioService.currentSong?.title ?? 'Unknown Song',
  maxLines: 1,
  overflow: TextOverflow.ellipsis,
  style: const TextStyle(
    fontWeight: FontWeight.w700,
    fontSize: 24,
  ),
),
                            const SizedBox(
                              height: 3,
                            ),
                      Text(
  AudioService.currentSong?.artist ?? 'Unknown Artist',
  style: const TextStyle(
    color: Colors.white70,
    fontSize: 18,
    fontWeight: FontWeight.w400,
  ),
)       
     ],
                        ),
                      ),
                      Container(
                        // color: Colors.amber,
                        margin: const EdgeInsets.only(right: 22),
                        child: Row(
                          children: [
                            // Padding(padding: EdgeInsets.only(right: 10)),
                            
                            const SizedBox(
                              width: 5,
                            ),
                            Container(
                              // ignore: prefer_const_constructors
                              decoration: BoxDecoration(shape: BoxShape.circle, color: const Color.fromARGB(158, 136, 136, 136)),
                              // color: Colors.black12,
                              child: const Icon(
                                Icons.more_horiz_rounded,
                                size: 29,
                                color: Color.fromARGB(255, 255, 255, 255),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(
                  height: 20,
                ),
                SizedBox(
                  height: 20,
                  child: SliderTheme(
                    data: SliderTheme.of(context).copyWith(
                      trackHeight: 5.0,
                      trackShape: const RoundedRectSliderTrackShape(),
                      activeTrackColor: const Color.fromARGB(255, 233, 233, 233),
                      inactiveTrackColor: const Color.fromARGB(255, 80, 80, 80),
                      thumbShape: const RoundSliderThumbShape(
                        elevation: 0,
                        pressedElevation: 0,
                      ),
                      thumbColor: Colors.transparent,
                      overlayColor: Colors.transparent,
                      activeTickMarkColor: Colors.transparent,
                      disabledThumbColor: Colors.transparent,
                      valueIndicatorColor: Colors.transparent,
                      inactiveTickMarkColor: Colors.transparent,
                      disabledActiveTrackColor: Colors.transparent,
                      secondaryActiveTrackColor: Colors.transparent,
                      valueIndicatorStrokeColor: Colors.transparent,
                      disabledInactiveTrackColor: Colors.transparent,
                      disabledActiveTickMarkColor: Colors.transparent,
                      overlappingShapeStrokeColor: Colors.transparent,
                      disabledInactiveTickMarkColor: Colors.transparent,
                      disabledSecondaryActiveTrackColor: Colors.transparent,
                    ),
                    child: Slider(
                      min: 0,
                      max: duration.inSeconds.toDouble(),
                      value: position.inSeconds.clamp(0, duration.inSeconds).toDouble(),
                      onChanged: (value) async {
                        final newPosition = Duration(seconds: value.toInt());
                        await audioPlayer.seek(newPosition);
                      },
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.only(left: 22, right: 22),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        formatTime(position),
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                      ),
                      Text(formatTime(duration - position), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15))
                    ],
                  ),
                ),
                const SizedBox(height: 30),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    IconButton(
                      icon: const Icon(
                        Icons.fast_rewind_rounded,
                        size: 70,
                        color: Color.fromARGB(255, 255, 255, 255),
                      ),
                      onPressed: () {
  if (currentIndex > 0) {
    setState(() {
      currentIndex--;
    });

    _loadSong(currentIndex);
  }
},
                    ),
                    IconButton(
                      icon: Icon(
                        isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                        size: 70,
                        color: const Color.fromARGB(255, 255, 255, 255),
                      ),
                      onPressed: () {
                        if (isPlaying) {
                          audioPlayer.pause();
                        } else {
                          audioPlayer.play();
                        }
                      },
                    ),
                    IconButton(
                      icon: const Icon(
                        Icons.fast_forward_rounded,
                        size: 70,
                        color: Color.fromARGB(255, 255, 255, 255),
                      ),
                      onPressed: () {
  final routes =
      ModalRoute.of(context)?.settings.arguments
          as Map<String, dynamic>?;

  final List<SongModel> allSongs =
      routes?['songs'] ?? [];

  if (currentIndex < allSongs.length - 1) {
  setState(() {
    currentIndex++;
  });

  _loadSong(currentIndex);
}
},
),
],
),

const SizedBox(height: 45),

Padding(
  padding: EdgeInsets.symmetric(horizontal: 35),
  child: Row(
    mainAxisAlignment: MainAxisAlignment.spaceBetween,
    children: [
      IconButton(
  onPressed: () {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF1C1C1E),
      builder: (context) {
        return Container(
          height: MediaQuery.of(context).size.height * 0.75,
          padding: const EdgeInsets.all(20),
          child: Column(
            children: [
              const SizedBox(height: 10),

              const Text(
                'Lyrics',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                ),
              ),

              const SizedBox(height: 20),

              Expanded(
                child: SingleChildScrollView(
                  child: Text(
                    lyrics,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 20,
                      height: 2,
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  },
  icon: const Icon(
    CupertinoIcons.quote_bubble,
    size: 26,
  ),
),

      IconButton(
  onPressed: () {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF1C1C1E),
      builder: (context) {
        return Container(
          height: MediaQuery.of(context).size.height * 0.75,
          padding: const EdgeInsets.all(20),
          child: Column(
            children: [
              const SizedBox(height: 10),

              const Text(
                'Queue',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                ),
              ),

              const SizedBox(height: 20),

              Expanded(
                child: ListView.builder(
                  itemCount:
                      AudioService.currentPlaylist.length,
                  itemBuilder: (context, index) {
                    final song =
                        AudioService.currentPlaylist[index];

                    return ListTile(
                      title: Text(
                        song.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      subtitle: Text(
                        song.artist ?? 'Unknown Artist',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      trailing:
                          index ==
                                  AudioService.currentIndex
                              ? const Icon(
                                  Icons.equalizer,
                                )
                              : null,
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  },
  icon: const Icon(
    CupertinoIcons.list_bullet,
    size: 26,
  ),
),
    ],
  ),
),
                  ],
                ),
              
            ),
          ),
        ),
      ),
     ),
   );
  }
}
