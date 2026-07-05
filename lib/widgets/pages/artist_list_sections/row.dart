part of '../artist_list_sections.dart';

class ArtistListRow extends StatelessWidget {
  const ArtistListRow({super.key, required this.artist});

  final ArtistInfo artist;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => Navigator.pushNamed(context, '/artist', arguments: artist.songs),
      child: Container(
        padding: const EdgeInsets.only(top: 15, left: 15, right: 15),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    
                    
                    SongArtwork(
                      songId: artist.coverSongId,
                      size: 50,
                      borderRadius: BorderRadius.circular(5),
                    ),
                    const SizedBox(width: 11),
                    Text(artist.name, style: const TextStyle(fontSize: 14)),
                  ],
                ),
                const Icon(Icons.arrow_forward_ios_rounded, color: Colors.grey, size: 18),
              ],
            ),
            const Divider(
              color: Color(0xFF48484A),
              thickness: 0.5,
              indent: 125,
              endIndent: 0,
            ),
          ],
        ),
      ),
    );
  }
}
