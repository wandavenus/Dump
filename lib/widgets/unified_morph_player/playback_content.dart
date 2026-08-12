part of '../unified_morph_player.dart';

// Narrow VLB wrapper around PlayerContent.
// Responsibility: subscribe to AudioService.playbackState and pass the full
// state to PlayerContent — isolating position-tick rebuilds to this subtree
// only, so the morph layout in _UnifiedMorphPlayerState is NOT rebuilt on
// every 100 ms position update.
class _PlaybackContent extends StatelessWidget {
  final LocalSong song;
  final String Function(Duration) formatTime;
  final bool showLyrics;
  final VoidCallback onLyricsToggle;
  final bool showQueue;
  final VoidCallback onQueueToggle;
  final bool hideArtwork;

  const _PlaybackContent({
    required this.song,
    required this.formatTime,
    required this.showLyrics,
    required this.onLyricsToggle,
    required this.showQueue,
    required this.onQueueToggle,
    this.hideArtwork = false,
  });

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<AudioPlaybackState>(
      valueListenable: AudioService.playbackState,
      builder: (context, playbackState, _) {
        return PlayerContent(
          song: song,
          playbackState: playbackState,
          formatTime: formatTime,
          showLyrics: showLyrics,
          onLyricsToggle: onLyricsToggle,
          showQueue: showQueue,
          onQueueToggle: onQueueToggle,
          hideArtwork: hideArtwork,
        );
      },
    );
  }
}
