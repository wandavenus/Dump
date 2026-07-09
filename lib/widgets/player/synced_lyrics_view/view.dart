part of '../synced_lyrics_view.dart';

/// Widget teks lirik sinkron — scroll otomatis ke baris aktif.
/// Mendukung pengaturan tampilan dari [LyricsSettings].
class SyncedLyricsView extends StatefulWidget {
  final List<LyricLine> lyrics;
  final EdgeInsetsGeometry padding;
  final ScrollController? controller;
  /// Controller pixel-based untuk menggeser [ScrollablePositionedList] secara
  /// relatif (mis. dari drag eksternal di area transport controls). Berbeda
  /// dari [controller] biasa — [ItemScrollController]/[ScrollOffsetController]
  /// adalah mekanisme scroll asli package `scrollable_positioned_list`.
  final ScrollOffsetController? offsetController;
  /// Handle untuk forward drag delta langsung ke [ScrollPosition] internal
  /// yang sedang live, via [ScrollPosition.jumpTo] — lihat [LyricsDragHandle].
  final LyricsDragHandle? dragHandle;
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
    this.offsetController,
    this.dragHandle,
    this.isVisible = true,
    this.rawLrc,
  });

  @override
  State<SyncedLyricsView> createState() => _SyncedLyricsViewState();
}
