part of '../lyrics_page.dart';

class _LyricsBody extends StatelessWidget {
  final LyricsResult result;
  const _LyricsBody({required this.result});

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        SyncedLyricsView(
          lyrics: result.lines,
          padding: const EdgeInsets.fromLTRB(24, 16, 48, 100),
          rawLrc: result.rawLrc,
        ),
        // Lencana sumber lirik
        ValueListenableBuilder<bool>(
          valueListenable: LyricsSettings.showSource,
          builder: (_, show, _) {
            if (!show || result.source == LyricsSource.none) {
              return const SizedBox.shrink();
            }
            return Positioned(
              bottom: 14,
              left: 24,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                      color: Colors.white.withValues(alpha: 0.12), width: 0.5),
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
                          color: Colors.white.withValues(alpha: 0.45), fontSize: 11),
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

// ─── Empty state ───────────────────────────────────────────────────────────────
