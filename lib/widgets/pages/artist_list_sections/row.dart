part of '../artist_list_sections.dart';

class ArtistListRow extends StatelessWidget {
  const ArtistListRow({super.key, required this.artist});

  final ArtistInfo artist;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap:
          () =>
              Navigator.pushNamed(context, '/artist', arguments: artist.songs),
      child: Container(
        padding: const EdgeInsets.only(top: 10, left: 5, right: 5),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    SongArtwork(
                      songId: artist.coverSongId,
                      size: 70,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    const SizedBox(width: 10),
                    Text(artist.name, style: const TextStyle(fontSize: 22)),
                  ],
                ),
                const Icon(
                  Icons.arrow_forward_ios_rounded,
                  color: Colors.grey,
                  size: 18,
                ),
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
