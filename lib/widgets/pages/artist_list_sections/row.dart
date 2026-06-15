part of '../artist_list_sections.dart';

class ArtistListRow extends StatelessWidget {
  const ArtistListRow({super.key, required this.artist});

  final ArtistInfo artist;

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
