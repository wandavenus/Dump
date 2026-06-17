import '../../models/local_song.dart';

/// Detects whether two consecutive songs belong to the same album,
/// which indicates gapless/live/DJ-mix content where crossfade should
/// be automatically suppressed.
class GaplessAlbumDetector {
  GaplessAlbumDetector._();

  /// Returns true when [a] and [b] are from the same album by the same
  /// artist, signalling that the transition should be gapless (no crossfade).
  static bool isGapless(LocalSong a, LocalSong b) {
    final album = a.album.trim();
    if (album.isEmpty || album == 'Unknown Album') return false;
    return album == b.album.trim() && a.artist.trim() == b.artist.trim();
  }
}
