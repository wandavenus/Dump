part of '../synced_lyrics_view.dart';

// ── Opsi B: StatefulWidget agar painter tidak dibuang saat AnimatedBuilder
//    rebuild — cache layout (_basePainter, _wordRects) tetap hidup selama
//    props yang mempengaruhi layout tidak berubah. ───────────────────────────

class _UnifiedKaraokeLine extends StatefulWidget {
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

  const _UnifiedKaraokeLine({
    super.key,
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
  });

  @override
  State<_UnifiedKaraokeLine> createState() => _UnifiedKaraokeLineState();
}

class _UnifiedKaraokeLineState extends State<_UnifiedKaraokeLine> {
  late _KaraokeLinePainter _painter;

  @override
  void initState() {
    super.initState();
    _painter = _buildPainter();
  }

  @override
  void didUpdateWidget(_UnifiedKaraokeLine old) {
    super.didUpdateWidget(old);

    final painterChanged =
        old.text != widget.text ||
        old.lineIndex != widget.lineIndex ||
        old.timeline != widget.timeline ||
        old.wordTexts != widget.wordTexts ||
        old.layoutCache != widget.layoutCache ||
        old.activeColor != widget.activeColor ||
        old.dimColor != widget.dimColor ||
        old.fontSize != widget.fontSize ||
        old.textAlign != widget.textAlign ||
        old.textScaleFactor != widget.textScaleFactor ||
        old.textDirection != widget.textDirection;

    if (painterChanged) _painter = _buildPainter();
  }

  _KaraokeLinePainter _buildPainter() {
    return _KaraokeLinePainter(
      text: widget.text,
      lineIndex: widget.lineIndex,
      timeline: widget.timeline,
      wordTexts: widget.wordTexts,
      layoutCache: widget.layoutCache,
      controller: widget.controller,
      activeColor: widget.activeColor,
      dimColor: widget.dimColor,
      fontSize: widget.fontSize,
      textAlign: widget.textAlign,
      textScaleFactor: widget.textScaleFactor,
      textDirection: widget.textDirection,
    );
  }

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _painter,
      child: Text(
        widget.text,
        textAlign: widget.textAlign,
        style: TextStyle(
          fontSize: widget.fontSize,
          height: 1.4,
          fontWeight: FontWeight.bold,
          color: Colors.transparent,
        ),
      ),
    );
  }
}
