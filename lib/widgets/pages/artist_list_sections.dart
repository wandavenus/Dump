import 'package:flutter/material.dart';

import '../../models/local_song.dart';
import '../../services/media_store_service.dart';
import '../song_artwork.dart';

class ArtistListContent extends StatefulWidget {
  const ArtistListContent({super.key});

  @override
  State<ArtistListContent> createState() => _ArtistListContentState();
}

class _ArtistListContentState extends State<ArtistListContent> {
  List<_ArtistInfo> _artists = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final songs = await MediaStoreService.getSongs();
      final artistMap = <String, List<LocalSong>>{};
      for (final song in songs) {
        artistMap.putIfAbsent(song.artist, () => []).add(song);
      }
      final artists = artistMap.entries
          .map((e) => _ArtistInfo(name: e.key, songs: e.value))
          .toList()
        ..sort((a, b) => a.name.compareTo(b.name));
      if (mounted) setState(() { _artists = artists; _isLoading = false; });
    } catch (_) {
      if (mounted) setState(() { _isLoading = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_artists.isEmpty) {
      return const Center(
        child: Text('Tidak ada artis ditemukan', style: TextStyle(color: Colors.grey)),
      );
    }
    return ListView.builder(
      itemCount: _artists.length,
      itemBuilder: (context, index) => ArtistListRow(artist: _artists[index]),
    );
  }
}

class _ArtistInfo {
  final String name;
  final List<LocalSong> songs;

  _ArtistInfo({required this.name, required this.songs});

  int get coverSongId => songs.first.id;
}

class ArtistListRow extends StatelessWidget {
  const ArtistListRow({super.key, required this.artist});

  final _ArtistInfo artist;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => Navigator.pushNamed(context, '/artist', arguments: artist.songs),
      child: Container(
        padding: const EdgeInsets.only(top: 10, left: 5, right: 5),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    const Icon(Icons.star, color: Colors.red, size: 15),
                    const SizedBox(width: 10),
                    SongArtwork(
                      songId: artist.coverSongId,
                      size: 90,
                      borderRadius: BorderRadius.circular(45),
                    ),
                    const SizedBox(width: 10),
                    Text(artist.name, style: const TextStyle(fontSize: 22)),
                  ],
                ),
                const Icon(Icons.arrow_forward_ios_rounded, color: Colors.grey, size: 18),
              ],
            ),
            const Divider(
              color: Color.fromARGB(255, 61, 61, 61),
              thickness: .4,
              indent: 125,
              endIndent: 0,
            ),
          ],
        ),
      ),
    );
  }
}
