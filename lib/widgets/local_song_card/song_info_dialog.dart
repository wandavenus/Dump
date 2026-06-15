part of '../local_song_card.dart';

class _SongInfoDialog extends StatelessWidget {
  final LocalSong song;
  const _SongInfoDialog({required this.song});

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: const Color(0xFF1C1C1E),
      title: const Text(
        'Informasi Lagu',
        style: TextStyle(color: Colors.white, fontSize: 17),
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _InfoRow('Judul',   song.title),
          _InfoRow('Artis',   song.artist),
          _InfoRow('Album',   song.album),
          _InfoRow('Durasi',  _fmtDuration(song.duration)),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text(
            'Tutup',
            style: TextStyle(color: Color(0xFFF92D48)),
          ),
        ),
      ],
    );
  }

  static String _fmtDuration(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '${d.inHours > 0 ? '${d.inHours}:' : ''}$m:$s';
  }
}
