import 'package:flutter/material.dart';

import '../../services/audio_service.dart';

class PlayerProgressSection extends StatelessWidget {
  final String Function(Duration duration) formatTime;

  const PlayerProgressSection({super.key, required this.formatTime});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<Duration>(
      stream: AudioService.player.positionStream,
      initialData: AudioService.player.position,
      builder: (context, snapshot) {
        final position = snapshot.data ?? Duration.zero;
        final duration = AudioService.playbackState.value.duration;
        final durationSeconds = duration.inSeconds;
        final value = durationSeconds == 0
            ? 0.0
            : position.inSeconds.clamp(0, durationSeconds).toDouble();

        return Column(
          children: [
            SliderTheme(
              data: SliderTheme.of(context).copyWith(
                trackHeight: 5,
                activeTrackColor: Colors.white,
                inactiveTrackColor: const Color(0xFF505050),
                thumbShape: const RoundSliderThumbShape(
                  enabledThumbRadius: 5,
                  elevation: 0,
                  pressedElevation: 0,
                ),
                overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
                overlayColor: Colors.white24,
              ),
              child: Slider(
                min: 0,
                max: durationSeconds == 0 ? 1 : durationSeconds.toDouble(),
                value: value,
                onChanged: durationSeconds == 0
                    ? null
                    : (newValue) {
                        AudioService.seek(Duration(seconds: newValue.toInt()));
                      },
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    formatTime(position),
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                      color: Colors.white70,
                    ),
                  ),
                  Text(
                    '-${formatTime(duration - position)}',
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                      color: Colors.white70,
                    ),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}
