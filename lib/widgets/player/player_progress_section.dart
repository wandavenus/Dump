import 'package:flutter/material.dart';

import '../../services/audio_service.dart';

class PlayerProgressSection extends StatefulWidget {
  final String Function(Duration duration) formatTime;

  const PlayerProgressSection({
    super.key,
    required this.formatTime,
  });

  @override
  State<PlayerProgressSection> createState() => _PlayerProgressSectionState();
}

class _PlayerProgressSectionState extends State<PlayerProgressSection> {
  bool _isDragging = false;
  double _dragValue = 0.0;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder(
      valueListenable: AudioService.playbackState,
      builder: (context, state, _) {
        final position = state.position;
        final duration = state.duration;
        final durationSeconds = duration.inSeconds;

        final liveValue = durationSeconds == 0
            ? 0.0
            : position.inSeconds
                .clamp(0, durationSeconds)
                .toDouble();

        final displayValue = _isDragging ? _dragValue : liveValue;

        final displayPosition = _isDragging
            ? Duration(seconds: _dragValue.toInt())
            : position;

        return Column(
          children: [
            SliderTheme(
              data: SliderTheme.of(context).copyWith(
                trackHeight: 6,
                activeTrackColor: Colors.white,
                inactiveTrackColor: const Color(0xFF808080),
                thumbShape: const RoundSliderThumbShape(
                  enabledThumbRadius: 0,
                  disabledThumbRadius: 0,
                ),
                overlayShape: SliderComponentShape.noOverlay,
                thumbColor: Colors.transparent,
                overlayColor: Colors.transparent,
              ),
              child: Slider(
                min: 0,
                max: durationSeconds == 0 ? 1 : durationSeconds.toDouble(),
                value: displayValue,
                onChangeStart: durationSeconds == 0
                    ? null
                    : (startValue) {
                        setState(() {
                          _isDragging = true;
                          _dragValue = startValue;
                        });
                      },
                onChanged: durationSeconds == 0
                    ? null
                    : (newValue) {
                        setState(() {
                          _dragValue = newValue;
                        });
                      },
                onChangeEnd: durationSeconds == 0
                    ? null
                    : (endValue) {
                        AudioService.seek(
                          Duration(seconds: endValue.toInt()),
                        );
                        setState(() {
                          _isDragging = false;
                        });
                      },
              ),
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  widget.formatTime(displayPosition),
                  style: const TextStyle(
                    fontWeight: FontWeight.w400,
                    fontSize: 11,
                    color: Colors.white70,
                  ),
                ),
                Text(
                  '-${widget.formatTime(duration - displayPosition)}',
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
