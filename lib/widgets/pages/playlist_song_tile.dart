import 'package:flutter/material.dart';
import 'package:musicplayer/models/local_song.dart';
import 'package:musicplayer/widgets/song_artwork.dart';

class PlaylistSongTile extends StatelessWidget {
  final LocalSong song;
  final bool removable;
  final VoidCallback? onRemove;
  final String duration;
  final VoidCallback onTap;

  const PlaylistSongTile({
    super.key,
    required this.song,
    required this.removable,
    required this.onRemove,
    required this.duration,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
      leading: SongArtwork(
        songId: song.id,
        size: 48,
        borderRadius: BorderRadius.circular(6),
      ),
      title: Text(
        song.title,
        style: TextStyle(color: colors.onSurface, fontSize: 15),
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text(
        song.artist,
        style: TextStyle(color: colors.onSurfaceVariant, fontSize: 13),
        overflow: TextOverflow.ellipsis,
      ),
      trailing: removable
          ? IconButton(
              icon: Icon(
                Icons.remove_circle_outline,
                color: colors.onSurfaceVariant,
                size: 20,
              ),
              onPressed: onRemove,
            )
          : Text(
              duration,
              style: TextStyle(
                color: colors.onSurfaceVariant,
                fontSize: 12,
              ),
            ),
      onTap: onTap,
    );
  }
}
