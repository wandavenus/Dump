part of '../mini_player.dart';

class _MiniPlayerBody extends StatelessWidget {
  final LocalSong song;
  final AudioPlaybackState playbackState;
  final double anim;
  final double swipeOffset;

  const _MiniPlayerBody({
    required this.song,
    required this.playbackState,
    required this.anim,
    this.swipeOffset = 0,
  });

  @override
  Widget build(BuildContext context) {
    final canGoNext =
        playbackState.currentIndex < playbackState.currentPlaylist.length - 1;
    final artworkSize = 46 + (50 * anim);
    final swipeFraction = (swipeOffset.abs() / 80).clamp(0.0, 1.0).toDouble();
    final fastAnim = Curves.easeOutCubic.transform(
  (anim * 0.5).clamp(0.0, 1.0),
);
    return ValueListenableBuilder<bool>(
      valueListenable: ThemeController.glassMiniPlayer,
      builder: (context, glassComp, _) {
        return ValueListenableBuilder<bool>(
          valueListenable: ThemeController.glassTheme,
          builder: (context, isGlassMaster, _) {
            final isGlass = isGlassMaster && glassComp;

            return Material(
              color: isGlass ? Colors.transparent : const Color(0xFF1C1C1E),
              child: SizedBox(
                height: 55,
                child: Stack(
                  children: [
                    if (swipeFraction > 0.05)
                      Positioned.fill(
                        child: Opacity(
                          opacity: swipeFraction * 0.18,
                          child: Container(
                            color: swipeOffset < 0
                                ? Colors.transparent
                                : Colors.transparent,
                          ),
                        ),
                      ),
                    if (swipeFraction > 0.05)
                      Positioned(
                        top: 0,
                        bottom: 0,
                        left: swipeOffset < 0 ? null : 14,
                        right: swipeOffset < 0 ? 14 : null,
                        child: Opacity(
                          opacity: swipeFraction,
                          child: Icon(
                            swipeOffset < 0
                                ? Icons.skip_next
                                : Icons.skip_previous,
                            color: Colors.white,
                            size: 22,
                          ),
                        ),
                      ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      child: Row(
                        children: [
                          Expanded(
                            child: GestureDetector(
                              behavior: HitTestBehavior.opaque,
                              onTap: _openFullPlayer,
                              child: Row(
                                children: [
                                  Transform.translate(
  offset: Offset(
    0,
    -(20 * anim),
  ),
  child: Hero(
    tag: PlayerHeroTags.artwork(song),
    child: SongArtwork(
      songId: song.id,
      size: artworkSize,
      borderRadius: BorderRadius.circular(
        3 + (9 * anim),
      ),
    ),
  ),
),
                                  SizedBox(width: 10 + (6 * anim)),
                                  Expanded(
  child: Transform.translate(
    offset: Offset(
      0,
      -(2 * fastAnim),
    ),
    child: Opacity(
      opacity: (1 - fastAnim * 3.0).clamp(0.0, 1.0),
      child: Hero(
        tag: PlayerHeroTags.title(song),
        child: Material(
          type: MaterialType.transparency,
          child: Text(
            song.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: Colors.white,
              fontSize: 15,
            ),
          ),
        ),
      ),
    ),
  ),
),
                                ],
                              ),
                            ),
                          ),
                          
                            Transform.translate(
  offset: Offset(
    0,
    -(2 * fastAnim),
  ),
  child: Opacity(
    opacity: (1 - fastAnim * 3.0).clamp(0.0, 1.0),
    child: Row(
      children: [
        IconButton(
          onPressed: () {
            playbackState.isPlaying
                ? AudioService.pause()
                : AudioService.play();
          },
          icon: Icon(
            playbackState.isPlaying
                ? Icons.pause
                : Icons.play_arrow,
            size: 34,
            color: Colors.white,
          ),
        ),
        IconButton(
          onPressed: canGoNext
              ? () => AudioService.skipNext()
              : null,
          icon: Icon(
            Icons.skip_next,
            size: 30,
            color: canGoNext
                ? Colors.white
                : Colors.white24,
          ),
        ),
      ],
    ),
  ),
),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  void _openFullPlayer() {
    PlayerSheetController.open();
  }
}
