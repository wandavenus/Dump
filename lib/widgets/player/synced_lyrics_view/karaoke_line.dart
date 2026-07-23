part of '../synced_lyrics_view.dart';

// ── Opsi B: StatefulWidget agar painter tidak dibuang saat AnimatedBuilder
//    rebuild — cache layout (_basePainter, _wordRects) tetap hidup selama
//    props yang mempengaruhi layout tidak berubah. ───────────────────────────

class _UnifiedKaraokeLine extends StatefulWidget {
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

    // Props yang membutuhkan layout ulang penuh (text metrics berubah)
    final bool needsRelayout =
        old.text != widget.text ||
        old.timeline != widget.timeline ||
        old.fontSize != widget.fontSize ||
        old.textAlign != widget.textAlign ||
        old.textScaleFactor != widget.textScaleFactor ||
        old.textDirection != widget.textDirection;

    // Props yang hanya mempengaruhi warna (geometry tidak berubah)
    final bool colorChanged =
        old.activeColor != widget.activeColor ||
        old.dimColor != widget.dimColor;

    if (needsRelayout) {
      // Rebuild penuh — _cacheWordPixels akan jalan kembali
      _painter = _buildPainter();
    } else if (colorChanged) {
      // Hanya warna berubah — wariskan word rects ke painter baru sehingga
      // getBoxesForSelection tidak perlu dipanggil lagi.
      final next = _buildPainter();
      next.inheritLayoutCache(_painter);
      _painter = next;
    }
    // Jika tidak ada yang berubah, _painter yang sama dipakai lagi —
    // repaint tetap jalan lewat repaint: controller (60fps ticker).
  }

  _KaraokeLinePainter _buildPainter() {
    return _KaraokeLinePainter(
      text: widget.text,
      timeline: widget.timeline,
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
