import 'package:flutter/material.dart';

import '../../services/audio_service.dart';

class PlayerProgressSection extends StatelessWidget {
  final String Function(Duration duration) formatTime;

  const PlayerProgressSection({
    super.key,
    required this.formatTime,
  });

  @override
Widget build(BuildContext context) {
  return ValueListenableBuilder(
    valueListenable: AudioService.playbackState,
    builder: (context, state, _) {
      final position = state.position;
      final duration = state.duration;
      final durationSeconds = duration.inSeconds;

      final value = durationSeconds == 0
          ? 0.0
          : position.inSeconds
              .clamp(0, durationSeconds)
              .toDouble();

      return Column(
        children: [
          SliderTheme(
  data: SliderTheme.of(context).copyWith(
    trackHeight: 6,
    activeTrackColor: Colors.white,
    inactiveTrackColor: const Color(0xFF808080),
    // Thumb transparan namun tetap memiliki area sentuh
    thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 4),
    overlayShape: const RoundSliderOverlayShape(overlayRadius: 0),
    thumbColor: Colors.transparent,
  ),
  child: Slider(
    min: 0,
    max: durationSeconds == 0 ? 1 : durationSeconds.toDouble(),
    value: value,
    onChanged: durationSeconds == 0
        ? null
        : (newValue) {
            AudioService.seek(
              Duration(seconds: newValue.toInt()),
            );
          },
  ),
),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                formatTime(position),
                style: const TextStyle(
                  fontWeight: FontWeight.w400,
                  fontSize: 11,
                  color: Colors.white70,
                ),
              ),
              Text(
                '-${formatTime(duration - position)}',
                style: const TextStyle(
                  fontWeight: FontWeight.w400,
                  fontSize: 11,
                  color: Colors.white70,
                ),
              ),
            ],
          ),
        ],
      );
    },
  );
}
}
