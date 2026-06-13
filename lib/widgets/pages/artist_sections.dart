import 'package:flutter/material.dart';
import '../../services/media_store_service.dart';

class ArtistListContent extends StatefulWidget {
  const ArtistListContent({super.key});

  @override
  State<ArtistListContent> createState() => _ArtistListContentState();
}

class _ArtistListContentState extends State<ArtistListContent> {
  List<String> artists = [];
  bool loading = true;

  @override
  void initState() {
    super.initState();
    _loadArtists();
  }

  Future<void> _loadArtists() async {
    final songs = await MediaStoreService.getSongs();

    final uniqueArtists = songs
        .map((e) => e.artist)
        .toSet()
        .toList()
      ..sort();

    setState(() {
      artists = uniqueArtists;
      loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (artists.isEmpty) {
      return const Center(child: Text('No artists found'));
    }

    return ListView.builder(
      itemCount: artists.length,
      itemBuilder: (context, index) {
        final artist = artists[index];

        return ListTile(
          leading: const Icon(Icons.person),
          title: Text(artist),
          onTap: () {
            Navigator.pushNamed(
              context,
              '/artist',
              arguments: artist,
            );
          },
        );
      },
    );
  }
}