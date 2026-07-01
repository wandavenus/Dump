part of '../synced_lyrics_view.dart';

class _KaraokeLinePainter extends CustomPainter {
  final String text;
  final List<_TimelineWord> timeline;
  final _KaraokeLineController controller;
  final Color activeColor;
  final Color dimColor;
  final double fontSize;
  final TextAlign textAlign;
  final double textScaleFactor;
  final TextDirection textDirection;

  TextPainter? _basePainter;
  TextPainter? _highlightPainter;
  List<List<Rect>> _wordRects = const [];
  double _lastWidth = -1;

  _KaraokeLinePainter({
    required this.text,
    required this.timeline,
    required this.controller,
    required this.activeColor,
    required this.dimColor,
    required this.fontSize,
    required this.textAlign,
    required this.textScaleFactor,
    required this.textDirection,
  }) : super(repaint: controller);

  @override
  void paint(Canvas canvas, Size size) {
    _ensureLayout(size.width);
    final base = _basePainter;
    final highlight = _highlightPainter;
    if (base == null || highlight == null) return;

    base.paint(canvas, Offset.zero);

    if (timeline.isEmpty || _wordRects.length != timeline.length) return;

    final cursor = controller.cursor.clamp(0, timeline.length - 1);
    final word = timeline[cursor];
    final startMs = word.start.inMilliseconds.toDouble();
    final endMs = word.end.inMilliseconds.toDouble();
    final durationMs = (endMs - startMs).clamp(1.0, 30000.0);
    final progress =
        ((controller.position.inMilliseconds - startMs) / durationMs).clamp(
          0.0,
          1.0,
        );

    final Path clipPath = Path();

    for (int i = 0; i <= cursor; i++) {
      final rects = _wordRects[i];
      if (i < cursor) {
        for (final rect in rects) {
          clipPath.addRect(rect);
        }
      } else {
        for (final rect in rects) {
          final clipW = rect.width * progress;
          if (textDirection == TextDirection.rtl) {
            clipPath.addRect(
              Rect.fromLTRB(
                rect.right - clipW,
                rect.top,
                rect.right,
                rect.bottom,
              ),
            );
          } else {
            clipPath.addRect(
              Rect.fromLTRB(
                rect.left,
                rect.top,
                rect.left + clipW,
                rect.bottom,
              ),
            );
          }
        }
      }
    }

    if (!clipPath.getBounds().isEmpty) {
      canvas.save();
      canvas.clipPath(clipPath);
      highlight.paint(canvas, Offset.zero);
      canvas.restore();
    }
  }

  void _ensureLayout(double width) {
    if (_basePainter != null && _lastWidth == width) return;
    _lastWidth = width;

    final style = TextStyle(
      fontSize: fontSize,
      fontWeight: FontWeight.bold,
      color: dimColor,
      height: 1.4,
    );
    _basePainter = TextPainter(
      text: TextSpan(text: text, style: style),
      textAlign: textAlign,
      textDirection: textDirection,
      textScaler: TextScaler.linear(textScaleFactor),
    )..layout(maxWidth: width);

    _highlightPainter = TextPainter(
      text: TextSpan(
        text: text,
        style: style.copyWith(color: activeColor),
      ),
      textAlign: textAlign,
      textDirection: textDirection,
      textScaler: TextScaler.linear(textScaleFactor),
    )..layout(maxWidth: width);

    _cacheWordPixels();
  }

  void _cacheWordPixels() {
    if (timeline.isEmpty || text.isEmpty) {
      _wordRects = const [];
      return;
    }
    final painter = _basePainter!;
    final rectsList = <List<Rect>>[];
    var searchFrom = 0;

    for (final word in timeline) {
      final index = text.indexOf(word.text, searchFrom);
      if (index < 0) {
        rectsList.add(const []);
        continue;
      }
      searchFrom = index + word.text.length;
      final boxes = painter.getBoxesForSelection(
        TextSelection(baseOffset: index, extentOffset: searchFrom),
      );
      rectsList.add(boxes.map((b) => b.toRect()).toList());
    }
    _wordRects = List<List<Rect>>.unmodifiable(rectsList);
  }

  @override
  bool shouldRepaint(covariant _KaraokeLinePainter oldDelegate) {
    return oldDelegate.text != text ||
        oldDelegate.timeline != timeline ||
        oldDelegate.activeColor != activeColor ||
        oldDelegate.dimColor != dimColor ||
        oldDelegate.fontSize != fontSize ||
        oldDelegate.textAlign != textAlign ||
        oldDelegate.textScaleFactor != textScaleFactor ||
        oldDelegate.textDirection != textDirection;
  }
}
