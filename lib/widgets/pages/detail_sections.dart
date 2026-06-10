import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

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
              child: const Icon(Icons.arrow_back_ios_new_rounded, size: 20, color: Colors.red),
            ),
          ),
          const Row(children: [_CircleIcon(icon: Icons.add), SizedBox(width: 18), _CircleIcon(icon: Icons.more_horiz)]),
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
  }
}

class AlbumHero extends StatelessWidget {
  const AlbumHero({super.key, required this.album});

  final Map album;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(top: 20),
      child: Column(
        children: [
          ClipPath(
            clipper: ShapeBorderClipper(shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15))),
            child: CachedNetworkImage(
              placeholder: (context, url) => const CircularProgressIndicator(),
              errorWidget: (context, url, error) => const Icon(Icons.error),
              imageUrl: album['image'],
              height: 300,
              width: 300,
            ),
          ),
          const SizedBox(height: 20),
          Text(album['title'],
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 30, fontWeight: FontWeight.bold, color: Colors.white)),
          Text(album['artist'],
              style: const TextStyle(fontSize: 23, fontWeight: FontWeight.normal, color: Colors.red)),
          const Text('SoundTrack • 2024 • Lossless',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.white)),
        ],
      ),
    );
  }
}

class ArtistHero extends StatelessWidget {
  const ArtistHero({super.key, required this.songs});

  final List songs;

  @override
  Widget build(BuildContext context) {
    final artist = songs[0];
    return Container(
      height: 340,
      decoration: BoxDecoration(
        image: DecorationImage(
          image: NetworkImage(artist['artist_img']),
          fit: BoxFit.cover,
          colorFilter: ColorFilter.mode(Colors.black.withOpacity(0.35), BlendMode.darken),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const DetailTopBar(),
          const Spacer(),
          Padding(
            padding: const EdgeInsets.only(left: 16, bottom: 20),
            child: Text(artist['artist'],
                style: const TextStyle(fontSize: 42, fontWeight: FontWeight.bold, color: Colors.white)),
          ),
        ],
      ),
    );
  }
}

class PlayShuffleButtons extends StatelessWidget {
  const PlayShuffleButtons({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(top: 20),
      child: const Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _ActionButton(icon: Icons.play_arrow_rounded, label: 'Play'),
          _ActionButton(icon: Icons.shuffle_rounded, label: 'Shuffle'),
        ],
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
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
          Text(label,
              style: const TextStyle(color: Colors.red, fontSize: 20, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }
}

class SongListSection extends StatelessWidget {
  const SongListSection({super.key, required this.songs, this.showHeader = false});

  final List songs;
  final bool showHeader;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        if (showHeader)
          Container(
            margin: const EdgeInsets.only(left: 10, top: 20),
            child: const Row(
              children: [
                Text('Top Songs',
                    style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
                Icon(Icons.arrow_forward_ios_rounded, color: Colors.grey),
              ],
            ),
          ),
        ListView.builder(
          padding: const EdgeInsets.only(top: 0, left: 10, right: 10),
          physics: const NeverScrollableScrollPhysics(),
          shrinkWrap: true,
          itemCount: songs.length < 4 ? songs.length : 4,
          itemBuilder: (context, index) => SongListRow(song: songs[index], index: index),
        ),
      ],
    );
  }
}

class SongListRow extends StatelessWidget {
  const SongListRow({super.key, required this.song, required this.index});

  final Map song;
  final int index;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const Divider(color: Color.fromARGB(255, 80, 80, 80), thickness: .4, indent: 58),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: [
                ClipPath(
                  clipper: ShapeBorderClipper(shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8.0))),
                  child: CachedNetworkImage(
                    placeholder: (context, url) => const CircularProgressIndicator(),
                    errorWidget: (context, url, error) => const Icon(Icons.error),
                    imageUrl: song['image'],
                    height: 50,
                    width: 50,
                    fit: BoxFit.cover,
                  ),
                ),
                Container(
                  width: 280,
                  margin: const EdgeInsets.only(left: 10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(song['song'], overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 20)),
                      Text('${song['album']} • 2022',
                          style: const TextStyle(fontSize: 15, color: Colors.grey)),
                    ],
                  ),
                ),
              ],
            ),
            const Icon(Icons.more_horiz),
          ],
        ),
      ],
    );
  }
}
