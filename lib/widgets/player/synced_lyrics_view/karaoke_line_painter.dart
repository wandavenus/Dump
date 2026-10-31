part of '../synced_lyrics_view.dart';

class _KaraokeLinePainter extends CustomPainter {
  final String text;
  final int lineIndex;
  final List<_TimelineWord> timeline;
  final List<String> wordTexts;
  final KaraokeLayoutCache layoutCache;
  final _KaraokeLineController controller;
  final Color activeColor;
  final Color dimColor;
  final double fontSize;
  final TextAlign textAlign;
  final double textScaleFactor;
  final TextDirection textDirection;

  // Cached paint state for the active word's soft glow.
  final Paint _glowLayerPaint = Paint();
  ui.ImageFilter? _wordGlowFilter;
  double _wordGlowSigma = -1;

  _KaraokeLinePainter({
    required this.text,
    required this.lineIndex,
    required this.timeline,
    required this.wordTexts,
    required this.layoutCache,
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
    if (size.width <= 0) return;
    final layout = layoutCache.obtain(
      lineIndex: lineIndex,
      text: text,
      wordTexts: wordTexts,
      maxWidth: size.width,
      fontSize: fontSize,
      textScaleFactor: textScaleFactor,
      textAlign: textAlign,
      textDirection: textDirection,
      activeColor: activeColor,
      dimColor: dimColor,
    );
    final base = layout.basePainter;
    final highlight = layout.highlightPainter;
    final wordRects = layout.wordBoxes;

    if (timeline.isEmpty || _wordRects.length != timeline.length) {
      base.paint(canvas, Offset.zero);
      return;
    }

    final position = controller.position;
    final pendingPaths = <double, Path>{};
    final completedPaths = <double, Path>{};
    final partialBoxes = <(Rect, TextDirection, double, double, double)>[];
    final glows = <(Path, double, double)>[];
    var hasWordBoxes = false;

    for (var index = 0; index < timeline.length; index++) {
      final word = timeline[index];
      final start = word.start;
      final end = word.end;
      final spanUs = (end - start).inMicroseconds;
      final elapsedUs = (position - start).inMicroseconds;
      final progress = spanUs <= 0
          ? 0.0
          : (elapsedUs / spanUs).clamp(0.0, 1.0).toDouble();
      final lift = spanUs <= 0
          ? 0.0
          : lyricWordLift(
              position: position,
              start: start,
              end: end,
              fontSize: fontSize * textScaleFactor,
            );

      final boxes = _orderedWordBoxes(wordRects[index]);
      if (boxes.isEmpty) continue;
      hasWordBoxes = true;

      // Critical difference from the previous painter: draw the dim glyphs
      // through each word's lift clip. The base glyph and color sweep therefore
      // share precisely the same transform instead of leaving a stationary
      // duplicate underneath the moving highlighted copy.
      final pending = pendingPaths.putIfAbsent(lift, Path.new);
      for (final box in boxes) {
        if (!box.rect.isEmpty) pending.addRect(box.rect);
      }

      final width = boxes.fold<double>(0, (sum, box) => sum + box.rect.width);
      if (width <= 0) continue;

      if (progress >= 1.0) {
        final completed = completedPaths.putIfAbsent(lift, Path.new);
        for (final box in boxes) {
          if (!box.rect.isEmpty) completed.addRect(box.rect);
        }
      } else if (progress > 0.0) {
        final feather = (width * 0.3).clamp(4.0, 16.0).toDouble();
        var consumedWidth = 0.0;
        for (final box in boxes) {
          final revealWidth = width * progress - consumedWidth;
          if (revealWidth >= box.rect.width) {
            completedPaths.putIfAbsent(lift, Path.new).addRect(box.rect);
          } else if (revealWidth > -feather && box.rect.width > 0) {
            partialBoxes.add((
              box.rect,
              box.direction,
              revealWidth / box.rect.width,
              lift,
              feather,
            ));
          }
          consumedWidth += box.rect.width;
        }
      }

      // Glow only the sung portion. Long-held words build a halo while they
      // are sung and fade for 500 ms after their timing ends.
      final durationMs = spanUs / 1000.0;
      final elapsedMs = elapsedUs / 1000.0;
      if (elapsedMs >= 0 && elapsedMs <= durationMs + 500.0) {
        final heldStrength = ((durationMs - 900.0) / 1100.0)
            .clamp(0.0, 1.0)
            .toDouble();
        if (heldStrength > 0) {
          final riseWindow = math.min(900.0, durationMs * 0.5);
          final rise = _smooth((elapsedMs - 250.0) / riseWindow);
          final fade = _smooth((durationMs + 500.0 - elapsedMs) / 500.0);
          final strength = heldStrength * rise * fade;
          if (strength > 0.01) {
            final glowPath = Path();
            var consumedWidth = 0.0;
            for (final box in boxes) {
              final revealWidth = width * progress - consumedWidth;
              if (progress >= 1.0) {
                glowPath.addRect(box.rect);
              } else if (revealWidth > 0 && box.rect.width > 0) {
                glowPath.addRect(
                  _revealedRect(box.rect, box.direction, revealWidth),
                );
              }
              consumedWidth += box.rect.width;
            }
            if (!glowPath.getBounds().isEmpty) {
              glows.add((glowPath, lift, strength));
            }
          }
        }
      }
    }

    if (!hasWordBoxes) {
      base.paint(canvas, Offset.zero);
      return;
    }

    // Paint pending text, sung glow, and completed highlights in the same
    // per-word coordinate space. Their timing envelopes are independent from
    // the linear color sweep so short syllables never snap vertically.
    for (final entry in pendingPaths.entries) {
      _paintLiftedText(canvas, base, entry.value, entry.key);
    }
    for (final (path, lift, strength) in glows) {
      _paintWordGlow(canvas, highlight, path, lift, strength);
    }
    for (final entry in completedPaths.entries) {
      _paintLiftedText(canvas, highlight, entry.value, entry.key);
    }
    for (final (rect, direction, revealFraction, lift, feather)
        in partialBoxes) {
      _paintPartialHighlight(
        canvas,
        highlight,
        rect,
        direction,
        revealFraction,
        lift,
        feather,
      );
    }
  }

  List<KaraokeWordBox> _orderedWordBoxes(List<KaraokeWordBox> boxes) {
    if (boxes.length <= 1 ||
        !boxes.every((box) => box.direction == boxes.first.direction)) {
      return boxes;
    }
    return List<KaraokeWordBox>.of(boxes)..sort((a, b) {
      final horizontal = a.rect.left.compareTo(b.rect.left);
      return boxes.first.direction == TextDirection.rtl
          ? -horizontal
          : horizontal;
    });
  }

  Rect _revealedRect(Rect rect, TextDirection direction, double revealWidth) {
    final width = revealWidth.clamp(0.0, rect.width).toDouble();
    return direction == TextDirection.rtl
        ? Rect.fromLTRB(rect.right - width, rect.top, rect.right, rect.bottom)
        : Rect.fromLTRB(rect.left, rect.top, rect.left + width, rect.bottom);
  }

  void _paintLiftedText(
    Canvas canvas,
    TextPainter painter,
    Path clip,
    double lift,
  ) {
    canvas.save();
    canvas.translate(0, -lift);
    canvas.clipPath(clip, doAntiAlias: false);
    painter.paint(canvas, Offset.zero);
    canvas.restore();
  }

  void _paintWordGlow(
    Canvas canvas,
    TextPainter painter,
    Path clip,
    double lift,
    double strength,
  ) {
    final sigma = (fontSize * textScaleFactor * 0.2).clamp(0.0, 8.0).toDouble();
    if (sigma <= 0) return;
    if (_wordGlowFilter == null || _wordGlowSigma != sigma) {
      _wordGlowSigma = sigma;
      _wordGlowFilter = ui.ImageFilter.blur(sigmaX: sigma, sigmaY: sigma);
    }

    final bounds = clip.getBounds().inflate(sigma * 3);
    _glowLayerPaint
      ..imageFilter = _wordGlowFilter
      ..colorFilter = ui.ColorFilter.mode(
        activeColor.withValues(alpha: strength * 0.32),
        BlendMode.srcIn,
      );
    canvas.save();
    canvas.translate(0, -lift);
    canvas.saveLayer(bounds, _glowLayerPaint);
    canvas.clipPath(clip, doAntiAlias: false);
    painter.paint(canvas, Offset.zero);
    canvas.restore();
    canvas.restore();
  }

  void _paintPartialHighlight(
    Canvas canvas,
    TextPainter painter,
    Rect box,
    TextDirection direction,
    double revealFraction,
    double lift,
    double feather,
  ) {
    final boundary = direction == TextDirection.rtl
        ? box.right - box.width * revealFraction
        : box.left + box.width * revealFraction;
    final revealRect = direction == TextDirection.rtl
        ? Rect.fromLTRB(
            math.max(box.left, boundary - feather),
            box.top,
            box.right,
            box.bottom,
          )
        : Rect.fromLTRB(
            box.left,
            box.top,
            math.min(box.right, boundary + feather),
            box.bottom,
          );
    if (revealRect.isEmpty) return;

    final maskStart = direction == TextDirection.rtl
        ? Offset(boundary - feather, 0)
        : Offset(boundary, 0);
    final maskEnd = direction == TextDirection.rtl
        ? Offset(boundary, 0)
        : Offset(boundary + feather, 0);
    final colors = direction == TextDirection.rtl
        ? const [Colors.transparent, Colors.white]
        : const [Colors.white, Colors.transparent];

    canvas.save();
    canvas.translate(0, -lift);
    canvas.clipRect(revealRect);
    canvas.saveLayer(revealRect, Paint());
    painter.paint(canvas, Offset.zero);
    final mask = Paint()
      ..blendMode = BlendMode.dstIn
      ..shader = ui.Gradient.linear(maskStart, maskEnd, colors, [0.0, 1.0]);
    canvas.drawRect(revealRect, mask);
    canvas.restore();
    canvas.restore();
  }

  double _smooth(double value) {
    final t = value.clamp(0.0, 1.0).toDouble();
    return t * t * (3 - 2 * t);
  }

  @override
  bool shouldRepaint(covariant _KaraokeLinePainter oldDelegate) {
    return oldDelegate.text != text ||
        oldDelegate.lineIndex != lineIndex ||
        oldDelegate.timeline != timeline ||
        oldDelegate.wordTexts != wordTexts ||
        oldDelegate.layoutCache != layoutCache ||
        oldDelegate.activeColor != activeColor ||
        oldDelegate.dimColor != dimColor ||
        oldDelegate.fontSize != fontSize ||
        oldDelegate.textAlign != textAlign ||
        oldDelegate.textScaleFactor != textScaleFactor ||
        oldDelegate.textDirection != textDirection;
  }
}
