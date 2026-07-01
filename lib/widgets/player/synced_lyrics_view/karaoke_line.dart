part of '../synced_lyrics_view.dart';

class _UnifiedKaraokeLine extends StatelessWidget {
  final String text;
  final List<_TimelineWord> timeline;
  final _KaraokeLineController controller;
  final Color activeColor;
  final Color dimColor;
  final double fontSize;
  final TextAlign textAlign;
  final double textScaleFactor;
  final TextDirection textDirection;

  const _UnifiedKaraokeLine({
    super.key,
    required this.text,
    required this.timeline,
    required this.controller,
    required this.activeColor,
    required this.dimColor,
    required this.fontSize,
    required this.textAlign,
    required this.textScaleFactor,
    required this.textDirection,
  });

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _KaraokeLinePainter(
        text: text,
        timeline: timeline,
        controller: controller,
        activeColor: activeColor,
        dimColor: dimColor,
        fontSize: fontSize,
        textAlign: textAlign,
        textScaleFactor: textScaleFactor,
        textDirection: textDirection,
      ),
      child: Text(
        text,
        textAlign: textAlign,
        style: TextStyle(
          fontSize: fontSize,
          height: 1.4,
          fontWeight: FontWeight.bold,
          color: Colors.transparent,
        ),
      ),
    );
  }
}
