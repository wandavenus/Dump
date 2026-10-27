import 'package:flutter/material.dart';
import 'package:musicplayer/models/local_song.dart';
import 'package:musicplayer/services/media_store_service.dart';

/// Renders a song title with an [E] marker when its embedded advisory tag is
/// explicit. Metadata lookup is cached by [MediaStoreService], so rebuilds do
/// not repeatedly parse the audio file.
class ExplicitSongTitle extends StatefulWidget {
  const ExplicitSongTitle({
    super.key,
    required this.song,
    this.style,
    this.maxLines,
    required this.overflow,
    this.textAlign,
  });

  final LocalSong song;
  final TextStyle? style;
  final int? maxLines;
  final TextOverflow overflow;
  final TextAlign? textAlign;

  @override
  State<ExplicitSongTitle> createState() => _ExplicitSongTitleState();
}

class _ExplicitSongTitleState extends State<ExplicitSongTitle> {
  late Future<bool?> _explicitFuture;

  @override
  void initState() {
    super.initState();
    _loadExplicitStatus();
  }

  @override
  void didUpdateWidget(covariant ExplicitSongTitle oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.song.id != widget.song.id ||
        oldWidget.song.path != widget.song.path) {
      _loadExplicitStatus();
    }
  }

  void _loadExplicitStatus() {
    _explicitFuture = MediaStoreService.getExplicitStatus(widget.song);
  }

  @override
  Widget build(BuildContext context) {
    final inheritedStyle = DefaultTextStyle.of(context).style;
    final titleStyle = widget.style;
    final badgeStyle = (titleStyle ?? inheritedStyle).copyWith(
      fontSize: ((titleStyle ?? inheritedStyle).fontSize ?? 14) * 0.78,
      fontWeight: FontWeight.w700,
      letterSpacing: 0.1,
    );

    return FutureBuilder<bool?>(
      future: _explicitFuture,
      builder: (context, snapshot) {
        final title = Text(
          widget.song.title,
          maxLines: widget.maxLines,
          overflow: widget.overflow,
          textAlign: widget.textAlign,
          style: titleStyle,
        );
        if (snapshot.data != true) return title;

        return Row(
          mainAxisSize: MainAxisSize.max,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Flexible(child: title),
            const SizedBox(width: 5),
            _KnockoutExplicitBadge(style: badgeStyle),
          ],
        );
      },
    );
  }
}

/// Draws the E as a real transparent cutout, rather than transparent text
/// painted over an intact background.
class _KnockoutExplicitBadge extends StatelessWidget {
  const _KnockoutExplicitBadge({required this.style});

  final TextStyle style;

  @override
  Widget build(BuildContext context) {
    final textDirection = Directionality.of(context);
    final knockoutStyle = TextStyle(
      inherit: false,
      fontFamily: style.fontFamily,
      fontFamilyFallback: style.fontFamilyFallback,
      fontSize: style.fontSize,
      fontWeight: style.fontWeight,
      fontStyle: style.fontStyle,
      letterSpacing: style.letterSpacing,
      wordSpacing: style.wordSpacing,
      height: style.height,
      textBaseline: style.textBaseline,
      locale: style.locale,
      foreground: Paint()..blendMode = BlendMode.dstOut,
    );
    final textPainter = TextPainter(
      text: TextSpan(text: 'E', style: knockoutStyle),
      textDirection: textDirection,
    )..layout();

    // Preserve the former 3 px horizontal and 2 px vertical padding.
    final badgeSize = Size(textPainter.width + 6, textPainter.height + 4);

    return Semantics(
      label: 'Explicit content advisory',
      child: CustomPaint(
        size: badgeSize,
        painter: _KnockoutBadgePainter(textPainter: textPainter),
        child: SizedBox(
          width: badgeSize.width,
          height: badgeSize.height,
        ),
      ),
    );
  }
}

class _KnockoutBadgePainter extends CustomPainter {
  const _KnockoutBadgePainter({required this.textPainter});

  final TextPainter textPainter;

  @override
  void paint(Canvas canvas, Size size) {
    final bounds = Offset.zero & size;

    // The badge and glyph are composited in an isolated layer. dstOut removes
    // the glyph pixels from the translucent background, exposing what is
    // actually behind the badge.
    canvas.saveLayer(bounds, Paint());
    canvas.drawRRect(
      RRect.fromRectAndRadius(bounds, const Radius.circular(3)),
      Paint()..color = Colors.white.withValues(alpha: 0.18),
    );
    textPainter.paint(
      canvas,
      Offset(
        (size.width - textPainter.width) / 2,
        (size.height - textPainter.height) / 2,
      ),
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _KnockoutBadgePainter oldDelegate) {
    return oldDelegate.textPainter.text != textPainter.text;
  }
}
