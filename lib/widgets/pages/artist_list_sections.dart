import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../utils/sample_music_data.dart';

class ArtistListContent extends StatelessWidget {
  const ArtistListContent({super.key});

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      itemCount: artistSongs.length,
      itemBuilder: (context, index) => ArtistListRow(index: index),
    );
  }
}

class ArtistListRow extends StatelessWidget {
  const ArtistListRow({super.key, required this.index});

  final int index;

  @override
  Widget build(BuildContext context) {
    final artist = artistSongs[index][index];
    return InkWell(
      onTap: () => Navigator.pushNamed(context, '/artist', arguments: {'index': index}),
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
                    ClipPath(
                      clipper: ShapeBorderClipper(shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(150))),
                      child: CachedNetworkImage(
                        placeholder: (context, url) => const CircularProgressIndicator(),
                        errorWidget: (context, url, error) => const Icon(Icons.error),
                        imageUrl: artist['artist_img'],
                        height: 90,
                        width: 90,
                        fit: BoxFit.cover,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Text(artist['artist'], style: const TextStyle(fontSize: 22)),
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
