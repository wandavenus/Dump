import 'dart:ui';

import 'package:flutter/material.dart';
import '../../services/audio_service.dart';
import '../../services/audio_playback_state.dart';
import '../../services/player_sheet_controller.dart';
import '../song_artwork.dart';
import 'player_background.dart';
import 'player_content.dart';

class PlayerSheet extends StatefulWidget {
  final bool expanded;
  final VoidCallback? onCollapse;

  const PlayerSheet({
    super.key,
    required this.expanded,
    this.onCollapse,
  });

  @override
  State<PlayerSheet> createState() => _PlayerSheetState();
}

class _PlayerSheetState extends State<PlayerSheet> {
  double _dragDy = 0;

  @override
  void didUpdateWidget(covariant PlayerSheet oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (widget.expanded && !oldWidget.expanded) {
      _dragDy = 0;
    }
  }

  String _formatTime(Duration d) {
    final minutes = d.inMinutes;
    final seconds = d.inSeconds % 60;
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }

  void _close() {
    widget.onCollapse?.call();
    PlayerSheetController.close();
  }

  double get _progress {
    final h = MediaQuery.of(context).size.height;
    return (_dragDy / (h * 0.35)).clamp(0.0, 1.0);
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.expanded) {
      return const SizedBox.shrink();
    }

    final progress = _progress;
    final blurSigma = progress * 22.0;

    return ValueListenableBuilder<AudioPlaybackState>(
      valueListenable: AudioService.playbackState,
      builder: (context, playbackState, _) {
        final song = playbackState.currentSong;

        return AnimatedSlide(
          duration: const Duration(milliseconds: 320),
          curve: Curves.easeOutCubic,
          offset: const Offset(0, 0),
          child: AnimatedOpacity(
            duration: const Duration(milliseconds: 280),
            opacity: 1,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onVerticalDragUpdate: (details) {
                setState(() {
                  _dragDy += details.delta.dy;
                  if (_dragDy < 0) _dragDy = 0;
                });
              },
              onVerticalDragEnd: (details) {
                final velocity = details.primaryVelocity ?? 0;

                if (velocity > 600 || progress > 0.25) {
                  _close();
                } else {
                  setState(() => _dragDy = 0);
                }
              },
              child: Transform.translate(
                offset: Offset(0, _dragDy * 0.5),
                child: Opacity(
                  opacity: (1 - progress).clamp(0.0, 1.0),
                  child: Material(
                    color: Colors.black,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        if (song != null)
                          ClipRect(
                            child: ImageFiltered(
                              imageFilter: ImageFilter.blur(
                                sigmaX: blurSigma,
                                sigmaY: blurSigma,
                              ),
                              child: AnimatedBlurredPlayerBackground(songId: song.id),
                            ),
                          )
                        else
                          const PlayerFallbackBackground(),
                        const DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [
                                Color.fromARGB(80, 0, 0, 0),
                                Color.fromARGB(180, 0, 0, 0),
                              ],
                            ),
                          ),
                        ),
                        SafeArea(
                          child: Padding(
                            padding: const EdgeInsets.only(top: 12),
                            child: song == null
                                ? const Center(
                                    child: Text(
                                      'No song selected',
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontSize: 24,
                                      ),
                                    ),
                                  )
                                : Transform.translate(
                                    offset: Offset(0, -progress * 18),
                                    child: Transform.scale(
                                      scale: 1 - (progress * 0.05),
                                      child: PlayerContent(
                                        song: song,
                                        playbackState: playbackState,
                                        formatTime: _formatTime,
                                        lyrics: '',
                                      ),
                                    ),
                                  ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
