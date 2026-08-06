part of '../synced_lyrics_view.dart';

class _KaraokeWordBox {
  final Rect rect;
  final TextDirection direction;

  const _KaraokeWordBox(this.rect, this.direction);
}

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
  List<List<_KaraokeWordBox>> _wordRects = const [];
  double _lastWidth = -1;

  // ── Path di-reuse setiap frame, bukan dibuat baru ────────────────────────
  final Path _clipPath = Path();

  // ── Opsi B: Flag untuk skip _cacheWordPixels saat hanya warna berubah ───
  bool _wordRectsPrecomputed = false;

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

  // ── Opsi B: Salin word rects dari painter lama saat hanya warna berubah ─
  void inheritLayoutCache(_KaraokeLinePainter old) {
    _wordRects = old._wordRects;
    _lastWidth = old._lastWidth;
    _wordRectsPrecomputed = true;
  }

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

    // ── Reset path yang sama, tidak alokasi baru tiap frame ─────────────────
    _clipPath.reset();

    // Past words: fully filled
    for (int i = 0; i < cursor; i++) {
      for (final box in _wordRects[i]) {
        _clipPath.addRect(box.rect);
      }
    }

    // Current word: use each visual bidi run's direction. An Arabic line may
    // contain Latin words, so using the paragraph direction for every rect
    // would make those embedded words highlight backwards.
    //
    // Time is linear, so progress must be linear. No easing here; easing
    // distorts the timing perception.
    // Fade effect is rendered afterwards as a soft gradient at the leading edge.
    Rect? currentFillBounds;
    for (final box in _wordRects[cursor]) {
      final rect = box.rect;
      final clipW = rect.width * progress;
      final filled = box.direction == TextDirection.rtl
          ? Rect.fromLTRB(rect.right - clipW, rect.top, rect.right, rect.bottom)
          : Rect.fromLTRB(rect.left, rect.top, rect.left + clipW, rect.bottom);
      _clipPath.addRect(filled);
      currentFillBounds = currentFillBounds == null
          ? filled
          : currentFillBounds.expandToInclude(filled);
    }

    if (!_clipPath.getBounds().isEmpty) {
      canvas.save();
      canvas.clipPath(_clipPath);
      highlight.paint(canvas, Offset.zero);
      canvas.restore();
    }

    // ── Soft fade at the leading edge of the current word ────────────────────
    // A narrow saveLayer strip (max 12 px) uses dstIn masking so only the
    // highlight text pixels survive — the gradient fades from opaque (filled
    // side) to transparent (leading edge). No full-width saveLayer needed.
    if (currentFillBounds != null &&
        currentFillBounds.width > 0 &&
        progress > 0.0 &&
        progress < 1.0) {
      const double fadeW = 12.0;
      final double stripW = currentFillBounds.width.clamp(0.0, fadeW);

      // Leading edge is right side (LTR) or left side (RTL).
      final currentDirection = _wordRects[cursor].isNotEmpty
          ? _wordRects[cursor].first.direction
          : textDirection;
      final strip = currentDirection == TextDirection.rtl
          ? Rect.fromLTRB(
              currentFillBounds.left,
              currentFillBounds.top,
              currentFillBounds.left + stripW,
              currentFillBounds.bottom,
            )
          : Rect.fromLTRB(
              currentFillBounds.right - stripW,
              currentFillBounds.top,
              currentFillBounds.right,
              currentFillBounds.bottom,
            );

      // Composite: draw highlight text, then mask with a gradient so the
      // leading edge of the fill fades to transparent (activeColor → clear).
      canvas.saveLayer(strip, Paint());
      highlight.paint(canvas, Offset.zero);
      final maskPaint = Paint()
        ..shader = ui.Gradient.linear(
          // Gradient runs from filled side → leading edge.
          Offset(
            currentDirection == TextDirection.rtl ? strip.right : strip.left,
            0,
          ),
          Offset(
            currentDirection == TextDirection.rtl ? strip.left : strip.right,
            0,
          ),
          [activeColor.withValues(alpha: 1), activeColor.withValues(alpha: 0)],
          [0.0, 1.0],
        )
        ..blendMode = BlendMode.dstIn;
      canvas.drawRect(strip, maskPaint);
      canvas.restore();
    }
  }

  void _ensureLayout(double width) {
    if (_basePainter != null && _lastWidth == width) return;

    // ── Opsi B: deteksi apakah lebar berubah sebelum _lastWidth diupdate ─
    final bool widthChanged = _lastWidth != width;
    _lastWidth = width;

    // Dispose painter lama sebelum membuat yang baru agar tidak bocor
    // memory native Paragraph (wajib sejak Flutter 3.x).
    _basePainter?.dispose();
    _highlightPainter?.dispose();

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

    // ── Opsi B: skip _cacheWordPixels jika word rects sudah diwarisi dan
    //    lebar widget tidak berubah — getBoxesForSelection tidak perlu jalan.
    if (_wordRectsPrecomputed && !widthChanged) {
      _wordRectsPrecomputed = false;
    } else {
      _wordRectsPrecomputed = false;
      _cacheWordPixels();
    }
  }

  void _cacheWordPixels() {
    if (timeline.isEmpty || text.isEmpty) {
      _wordRects = const [];
      return;
    }
    final painter = _basePainter!;
    final rectsList = <List<_KaraokeWordBox>>[];
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
      rectsList.add(
        boxes
            .map((b) => _KaraokeWordBox(b.toRect(), b.direction))
            .toList(growable: false),
      );
    }
    _wordRects = List<List<_KaraokeWordBox>>.unmodifiable(rectsList);
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
