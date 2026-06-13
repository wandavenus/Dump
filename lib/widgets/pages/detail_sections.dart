import 'package:flutter/material.dart';

import '../../models/local_song.dart';
import '../../services/audio_service.dart';
import '../../themes/liquid_glass.dart';
import '../../themes/theme_controller.dart';
import '../player/player_panel_controller.dart';
import '../song_artwork.dart';

class DetailTopBar extends StatelessWidget {
  const DetailTopBar({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(top: 30, left: 10, right: 10),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Container(
            margin: const EdgeInsets.only(top: 15),
            padding: const EdgeInsets.all(5),
            child: InkWell(
              onTap: () => Navigator.of(context).pop(),
              child: const Icon(Icons.arrow_back_ios_new_rounded,
                  size: 20, color: Colors.red),
            ),
          ),
          const Row(children: [
            _CircleIcon(icon: Icons.add),
            SizedBox(width: 18),
            _CircleIcon(icon: Icons.more_horiz),
          ]),
        ],
      ),
    );
  }
}

class _CircleIcon extends StatelessWidget {
  const _CircleIcon({required this.icon});

  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: ThemeController.glassTheme,
      builder: (ctx, _) {
        if (ThemeController.glassTheme.value) {
          return LiquidGlass(
            borderRadius: BorderRadius.circular(150),
            blur: 16,
            addShadow: false,
            padding: const EdgeInsets.all(6),
            child: Icon(icon, size: 20, color: Colors.red),
          );
        }
        return DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(150),
            color: const Color.fromARGB(85, 79, 79, 79),
          ),
          child: Padding(
            padding: const EdgeInsets.all(5),
            child: Icon(icon, size: 20, color: Colors.red),
          ),
        );
      },
    );
  }
}

// ─── Album hero ─────────────────────────────────────────────────────────────

class AlbumHero extends StatelessWidget {
  const AlbumHero({super.key, required this.album});

  final LocalSong album;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(top: 20),
      child: Column(
        children: [
          SongArtwork(
            songId: album.id,
            size: 300,
            borderRadius: BorderRadius.circular(15),
          ),
          const SizedBox(height: 20),
          Text(
            album.album,
            textAlign: TextAlign.center,
            style: const TextStyle(
                fontSize: 30,
                fontWeight: FontWeight.bold,
                color: Colors.white),
          ),
          Text(
            album.artist,
            style: const TextStyle(
                fontSize: 23,
                fontWeight: FontWeight.normal,
                color: Colors.red),
          ),
          const Text(
            'Local • Lossless',
            style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: Colors.white),
          ),
        ],
      ),
    );
  }
}

// ─── Artist hero ─────────────────────────────────────────────────────────────

class ArtistHero extends StatelessWidget {
  const ArtistHero({super.key, required this.songs});

  final List<LocalSong> songs;

  @override
  Widget build(BuildContext context) {
    final artistName = songs.first.artist;

    return SizedBox(
      height: 340,
      child: Stack(
        fit: StackFit.expand,
        children: [
          SongArtwork(
            songId: songs.first.id,
            size: 340,
            borderRadius: BorderRadius.zero,
            fit: BoxFit.cover,
          ),
          DecoratedBox(
            decoration:
                BoxDecoration(color: Colors.black.withOpacity(0.45)),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const DetailTopBar(),
              const Spacer(),
              Padding(
                padding: const EdgeInsets.only(left: 16, bottom: 20),
                child: Text(
                  artistName,
                  style: const TextStyle(
                      fontSize: 42,
                      fontWeight: FontWeight.bold,
                      color: Colors.white),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ─── Tombol Play / Shuffle ────────────────────────────────────────────────────

class PlayShuffleButtons extends StatelessWidget {
  const PlayShuffleButtons({super.key, required this.songs});

  final List<LocalSong> songs;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(top: 20),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _ActionButton(
            icon: Icons.play_arrow_rounded,
            label: 'Play',
            onTap: () async {
              await AudioService.playSongAt(playlist: songs, index: 0);
              PlayerPanelController.instance.open();
            },
          ),
          _ActionButton(
            icon: Icons.shuffle_rounded,
            label: 'Shuffle',
            onTap: () async {
              final shuffled = List<LocalSong>.from(songs)..shuffle();
              await AudioService.playSongAt(playlist: shuffled, index: 0);
              PlayerPanelController.instance.open();
            },
          ),
        ],
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton(
      {required this.icon, required this.label, required this.onTap});

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: ThemeController.glassTheme,
      builder: (ctx, _) {
        if (ThemeController.glassTheme.value) {
          return LiquidGlass(
            borderRadius: BorderRadius.circular(12),
            blur: 20,
            addShadow: true,
            child: InkWell(
              onTap: onTap,
              borderRadius: BorderRadius.circular(12),
              child: SizedBox(
                height: 50,
                width: 160,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(icon, color: Colors.red, size: 28),
                    const SizedBox(width: 6),
                    Text(
                      label,
                      style: const TextStyle(
                          color: Colors.red,
                          fontSize: 18,
                          fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
              ),
            ),
          );
        }

        return InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(10),
          child: Container(
            height: 50,
            width: 160,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              color: const Color.fromARGB(85, 79, 79, 79),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, color: Colors.red, size: 30),
                Text(
                  label,
                  style: const TextStyle(
                      color: Colors.red,
                      fontSize: 20,
                      fontWeight: FontWeight.bold),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

// ─── Daftar lagu ──────────────────────────────────────────────────────────

class SongListSection extends StatelessWidget {
  const SongListSection({
    super.key,
    required this.songs,
    this.showHeader = false,
  });

  final List<LocalSong> songs;
  final bool showHeader;

  @override
  Widget build(BuildContext context) {
    final displayCount = songs.length < 4 ? songs.length : 4;
    return Column(
      children: [
        if (showHeader)
          Container(
            margin: const EdgeInsets.only(left: 10, top: 20),
            child: const Row(
              children: [
                Text(
                  'Top Songs',
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.bold),
                ),
                Icon(Icons.arrow_forward_ios_rounded, color: Colors.grey),
              ],
            ),
          ),
        ListView.builder(
          padding: const EdgeInsets.only(top: 0, left: 10, right: 10),
          physics: const NeverScrollableScrollPhysics(),
          shrinkWrap: true,
          itemCount: displayCount,
          itemBuilder: (context, index) =>
              SongListRow(song: songs[index], index: index, playlist: songs),
        ),
      ],
    );
  }
}

class SongListRow extends StatelessWidget {
  const SongListRow({
    super.key,
    required this.song,
    required this.index,
    required this.playlist,
  });

  final LocalSong song;
  final int index;
  final List<LocalSong> playlist;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () async {
        await AudioService.playSongAt(playlist: playlist, index: index);
        PlayerPanelController.instance.open();
      },
      child: Column(
        children: [
          const Divider(
              color: Color.fromARGB(255, 80, 80, 80),
              thickness: .4,
              indent: 58),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  SongArtwork(
                    songId: song.id,
                    size: 50,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  Container(
                    width: 280,
                    margin: const EdgeInsets.only(left: 10),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(song.title,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 20)),
                        Text(song.album,
                            style: const TextStyle(
                                fontSize: 15, color: Colors.grey),
                            overflow: TextOverflow.ellipsis),
                      ],
                    ),
                  ),
                ],
              ),
              const Icon(Icons.more_horiz),
            ],
          ),
        ],
      ),
    );
  }
}
