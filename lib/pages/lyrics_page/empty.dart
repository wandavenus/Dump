part of '../lyrics_page.dart';

class _EmptyLyrics extends StatelessWidget {
  final LocalSong song;
  const _EmptyLyrics({required this.song});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(CupertinoIcons.music_note,
                size: 48, color: Colors.white.withOpacity(0.2)),
            const SizedBox(height: 16),
            Text(
              'Lirik tidak ditemukan',
              style: TextStyle(
                  color: Colors.white.withOpacity(0.6),
                  fontSize: 17,
                  fontWeight: FontWeight.w500),
            ),
            const SizedBox(height: 8),
            Text(
              '${song.title} · ${song.artist}',
              textAlign: TextAlign.center,
              style: TextStyle(
                  color: Colors.white.withOpacity(0.3), fontSize: 13),
            ),
            const SizedBox(height: 6),
            Text(
              'Tambahkan file .lrc di folder yang sama dengan lagu,\n'
              'atau konfigurasi folder lirik di Pengaturan.',
              textAlign: TextAlign.center,
              style: TextStyle(
                  color: Colors.white.withOpacity(0.2), fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Sheet pengaturan tampilan ─────────────────────────────────────────────────
