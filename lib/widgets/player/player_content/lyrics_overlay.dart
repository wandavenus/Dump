part of '../player_content.dart';

// ─── Lyrics body ─────────────────────────────────────────────────────────────

class _LyricsOverlayBody extends StatelessWidget {
  final LyricsResult result;
  final ScrollController scrollController;
  final ScrollOffsetController offsetController;
  final LyricsDragHandle dragHandle;
  final ValueChanged<bool> onExpandChanged;
  final bool isVisible;

  const _LyricsOverlayBody({
    required this.result,
    required this.scrollController,
    required this.offsetController,
    required this.dragHandle,
    required this.onExpandChanged,
    this.isVisible = true,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        // Swipe-down-to-collapse: a fast downward drag released anywhere on
        // the lyrics list (any line, any scroll position) collapses back to
        // half-view mode while in full mode. Purely additive — wraps the
        // existing offset-based listener below without altering it; only
        // fires for genuine user drags (ScrollEndNotification.dragDetails is
        // null for programmatic scrolls like jumpTo/animateScroll), and
        // onExpandChanged(false) is already a no-op when not expanded.
        NotificationListener<ScrollEndNotification>(
          onNotification: (notification) {
            final velocity = notification.dragDetails?.primaryVelocity ?? 0;
            if (velocity > 300) {
              onExpandChanged(false);
            }
            return false;
          },
          // ScrollUpdateNotification (not UserScrollNotification) so this also
          // fires for drags forwarded from outside the list itself — e.g. the
          // bottom-controls / gesture-inset drag relays in content.dart and
          // player_sheet/state.dart, which scroll the list programmatically
          // via ScrollOffsetController rather than a direct user drag on it.
          child: NotificationListener<ScrollUpdateNotification>(
            onNotification: (notification) {
              final offset = notification.metrics.pixels;

              // Only a genuine user swipe-up (dragDetails != null) may expand
              // to full mode and hide the bottom controls — automatic/
              // programmatic scrolls (e.g. auto-following the current lyric
              // line as the song plays) must never trigger that hide.
              // Collapsing back to half-view (revealing the controls again)
              // stays unrestricted, as before.
              if (offset > 150 && notification.dragDetails != null) {
                onExpandChanged(true);
              } else if (offset < 50) {
                onExpandChanged(false);
              }

              return false;
            },
            child: ShaderMask(
              shaderCallback: (Rect rect) {
                return const LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.transparent,
                    Colors.white,
                    Colors.white,
                    Colors.transparent,
                  ],
                  stops: [0.0, 0.35, 0.65, 1.0],
                ).createShader(rect);
              },
              blendMode: BlendMode.dstIn,
              child: SyncedLyricsView(
                lyrics: result.lines,
                padding: const EdgeInsets.fromLTRB(24, 130, 48, 130),
                controller: scrollController,
                offsetController: offsetController,
                dragHandle: dragHandle,
                isVisible: isVisible,
                rawLrc: result.rawLrc,
              ),
            ),
          ),
        ),
        ValueListenableBuilder<bool>(
          valueListenable: LyricsSettings.showSource,
          builder: (_, show, _) {
            if (!show || result.source == LyricsSource.none) {
              return const SizedBox.shrink();
            }
            return Positioned(
              bottom: 8,
              left: 24,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.12),
                    width: 0.5,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      result.source == LyricsSource.internet
                          ? CupertinoIcons.globe
                          : CupertinoIcons.doc_text,
                      color: Colors.white.withValues(alpha: 0.45),
                      size: 11,
                    ),
                    const SizedBox(width: 5),
                    Text(
                      result.sourceLabel,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.45),
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ],
    );
  }
}

// ─── Empty lyrics state ───────────────────────────────────────────────────────

class _EmptyLyricsOverlay extends StatelessWidget {
  final LocalSong song;
  const _EmptyLyricsOverlay({required this.song});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              CupertinoIcons.music_note,
              size: 48,
              color: Colors.white.withValues(alpha: 0.2),
            ),
            const SizedBox(height: 16),
            Text(
              'Lirik tidak ditemukan',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.6),
                fontSize: 17,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '${song.title} · ${song.artist}',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.3),
                fontSize: 13,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Tambahkan file .lrc di folder yang sama\ndengan lagu, atau konfigurasikan folder\nlirik di Pengaturan.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.2),
                fontSize: 12,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
