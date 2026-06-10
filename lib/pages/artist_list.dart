import 'package:flutter/material.dart';

import '../widgets/pages/artist_list_sections.dart';

class ArtistList extends StatefulWidget {
  const ArtistList({super.key});

  @override
  State<ArtistList> createState() => _ArtistListState();
}

class _ArtistListState extends State<ArtistList> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          '           Favourite Artist',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 20),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.red),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: const ArtistListContent(),
    );
  }
}
