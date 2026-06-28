import 'package:flutter/material.dart';
import 'package:musicplayer/services/audio_service.dart';
import 'package:musicplayer/services/audio_playback_state.dart';
import 'package:musicplayer/models/local_song.dart';
import 'package:musicplayer/services/up_next_settings.dart';


class PlayerUpNextCard extends StatefulWidget {
  final bool showOverlay;

  const PlayerUpNextCard({super.key, required this.showOverlay});

  @override
  State<PlayerUpNextCard> createState() => _PlayerUpNextCardState();
}

class _PlayerUpNextCardState extends State<PlayerUpNextCard> {
  int? _dismissedSongId;
  double _dragDx = 0.0;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: UpNextSettings.showUpNextCard,
      builder: (_, settingEnabled, _) {
        return ValueListenableBuilder<AudioPlaybackState>(
          valueListenable: AudioService.playbackState,
          builder: (_, state, _) {
            final nextIdx  = AudioService.nextIndex;
            final playlist = state.currentPlaylist;
            final hasNext  = nextIdx >= 0 && nextIdx < playlist.length;
            final nextSong = hasNext ? playlist[nextIdx] : null;
            final visible  = settingEnabled &&
                hasNext &&
                !widget.showOverlay &&
                nextSong?.id != _dismissedSongId;

            return AnimatedSwitcher(
              duration: const Duration(milliseconds: 320),
              transitionBuilder: (child, animation) => FadeTransition(
                opacity: animation,
                child: SizeTransition(
                  sizeFactor: animation,
                  axis: Axis.vertical,
                  axisAlignment: -1,
                  child: child,
                ),
              ),
              child: visible
                  ? GestureDetector(
                      key: ValueKey('up_next_${nextSong?.id}'),
                      onHorizontalDragUpdate: (d) =>
                          setState(() => _dragDx += d.delta.dx),
                      onHorizontalDragEnd: (d) {
                        final velocity = d.primaryVelocity?.abs() ?? 0;
                        if (_dragDx.abs() > 80 || velocity > 300) {
                          setState(() {
                            _dismissedSongId = nextSong?.id;
                            _dragDx = 0.0;
                          });
                        } else {
                          setState(() => _dragDx = 0.0);
                        }
                      },
                      onHorizontalDragCancel: () =>
                          setState(() => _dragDx = 0.0),
                      child: Transform.translate(
                        offset: Offset(_dragDx, 0),
                        child: _UpNextCardContent(song: nextSong!),
                      ),
                    )
                  : const SizedBox.shrink(key: ValueKey('empty')),
            );
          },
        );
      },
    );
  }
}

class _UpNextCardContent extends StatelessWidget {
  final LocalSong song;

  const _UpNextCardContent({required this.song});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(23, 4, 23, 0),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.0),
          borderRadius: BorderRadius.circular(12),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 5),
        child: Row(
  crossAxisAlignment: CrossAxisAlignment.start,
  children: [
    Padding(
      padding: const EdgeInsets.only(top: 2),
      child: Text(
        'UP NEXT',
        style: TextStyle(
          color: Colors.white.withValues(alpha: 0.45),
          fontSize: 10,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.8,
        ),
      ),
    ),
    const SizedBox(width: 10),
    Expanded(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            song.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 14,
              fontWeight: FontWeight.w500,
            ),
          ),
          Text(
            song.artist,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.55),
              fontSize: 12,
            ),
          ),
        ],
      ),
    ),
  ],
),
      ),
    );
  }
}
