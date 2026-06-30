part of '../synced_lyrics_view.dart';

/// Widget teks lirik sinkron — scroll otomatis ke baris aktif.
/// Mendukung pengaturan tampilan dari [LyricsSettings].
class SyncedLyricsView extends StatefulWidget {
  final List<LyricLine> lyrics;
  final EdgeInsetsGeometry padding;
  final ScrollController? controller;

  /// Sinyal visibilitas dari parent. Ketika berubah dari false → true,
  /// widget langsung melakukan re-centering ke highlight aktif.
  final bool isVisible;

  /// String LRC mentah termasuk inline word timestamps (Enhanced LRC).
  /// Jika diberikan dan berisi word timestamps, renderer akan menggunakan
  /// timing kata yang akurat. Null berarti gunakan renderer karakter standar.
  final String? rawLrc;

  const SyncedLyricsView({
    super.key,
    required this.lyrics,
    this.padding = const EdgeInsets.symmetric(horizontal: 24, vertical: 80),
    this.controller,
    this.isVisible = true,
    this.rawLrc,
  });

  @override
  State<SyncedLyricsView> createState() => _SyncedLyricsViewState();
}
