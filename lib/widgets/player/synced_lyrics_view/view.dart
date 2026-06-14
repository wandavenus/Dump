part of '../synced_lyrics_view.dart';

/// Widget teks lirik sinkron — scroll otomatis ke baris aktif.
/// Mendukung pengaturan tampilan dari [LyricsSettings].
class SyncedLyricsView extends StatefulWidget {
  final List<LyricLine> lyrics;
  final EdgeInsetsGeometry padding;

  const SyncedLyricsView({
    super.key,
    required this.lyrics,
    this.padding = const EdgeInsets.symmetric(horizontal: 24, vertical: 80),
  });

  @override
  State<SyncedLyricsView> createState() => _SyncedLyricsViewState();
}
