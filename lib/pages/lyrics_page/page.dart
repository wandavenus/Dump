part of '../lyrics_page.dart';

/// Halaman lirik penuh layar dengan latar blur album art.
class LyricsPage extends StatefulWidget {
  final LocalSong song;

  const LyricsPage({super.key, required this.song});

  @override
  State<LyricsPage> createState() => _LyricsPageState();
}
