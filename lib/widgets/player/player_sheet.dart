import 'package:flutter/material.dart';
import '../../services/audio_playback_state.dart';
import '../../services/audio_service.dart';
import '../../services/player_sheet_controller.dart';
import 'player_empty_state.dart';

class PlayerSheet extends StatelessWidget {
  final bool expanded;
  final VoidCallback? onCollapse;

  const PlayerSheet({
    super.key,
    required this.expanded,
    this.onCollapse,
  });

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      ignoring: false,
      child: AnimatedPositioned(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOutCubic,
        left: 0,
        right: 0,
        top: 0,
        bottom: 0,
        child: Material(
          color: const Color(0xFF000000),
          child: ValueListenableBuilder<AudioPlaybackState>(
            valueListenable: AudioService.playbackState,
            builder: (context, playbackState, _) {
              final song = playbackState.currentSong;

              return Stack(
                fit: StackFit.expand,
                children: [
                  const ColoredBox(color: Colors.black),
                  SafeArea(
                    child: Stack(
                      children: [
                        Positioned(
                          top: 12,
                          left: 0,
                          right: 0,
                          child: Center(
                            child: GestureDetector(
                              onTap: PlayerSheetController.close,
                              child: Container(
                                width: 36,
                                height: 5,
                                decoration: BoxDecoration(
                                  color: Colors.white24,
                                  borderRadius: BorderRadius.circular(99),
                                ),
                              ),
                            ),
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.only(top: 18),
                          child: song == null
                              ? const PlayerEmptyState()
                              : const Center(
                                  child: Text(
                                    'PLAYER SHEET WORKS',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 30,
                                    ),
                                  ),
                                ),
                        ),
                      ],
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}
