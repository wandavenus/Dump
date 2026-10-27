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
class _KnockoutExplicitBadge extends StatefulWidget {
  const _KnockoutExplicitBadge({required this.style});

  final TextStyle style;

  @override
  State<_KnockoutExplicitBadge> createState() =>
      _KnockoutExplicitBadgeState();
}

class _KnockoutExplicitBadgeState extends State<_KnockoutExplicitBadge> {
  TextStyle? _sourceStyle;
  TextDirection? _textDirection;
  TextPainter? _textPainter;
  Size _badgeSize = Size.zero;

  void _configurePainterIfNeeded(TextDirection textDirection) {
    if (_textPainter != null &&
        _sourceStyle == widget.style &&
        _textDirection == textDirection) {
      return;
    }

    _sourceStyle = widget.style;
    _textDirection = textDirection;

    // The badge has been reduced to 81% of its original size after two
    // successive 10% reductions. Keep the knockout glyph and padding in scale.
    final knockoutStyle = TextStyle(
      inherit: false,
      fontFamily: widget.style.fontFamily,
      fontFamilyFallback: widget.style.fontFamilyFallback,
      fontSize: (widget.style.fontSize ?? 14) * 0.81,
      fontWeight: widget.style.fontWeight,
      fontStyle: widget.style.fontStyle,
      letterSpacing: widget.style.letterSpacing,
      wordSpacing: widget.style.wordSpacing,
      height: widget.style.height,
      textBaseline: widget.style.textBaseline,
      locale: widget.style.locale,
      foreground: Paint()..blendMode = BlendMode.dstOut,
    );

    final textPainter = TextPainter(
      text: TextSpan(text: 'E', style: knockoutStyle),
      textDirection: textDirection,
    )..layout();

    _textPainter = textPainter;
    final paddedWidth = textPainter.width + 4.86;
    final paddedHeight = textPainter.height + 3.24;
    _badgeSize = Size.square(
      paddedWidth > paddedHeight ? paddedWidth : paddedHeight,
    );
  }

  @override
  Widget build(BuildContext context) {
    final textDirection = Directionality.of(context);
    _configurePainterIfNeeded(textDirection);

    final textPainter = _textPainter!;
    final badgeSize = _badgeSize;

    return Semantics(
      label: 'Explicit content advisory',
      child: CustomPaint(
        size: badgeSize,
        painter: _KnockoutBadgePainter(
          textPainter: textPainter,
          sourceStyle: _sourceStyle!,
          textDirection: textDirection,
          badgeSize: badgeSize,
        ),
        child: SizedBox(
          width: badgeSize.width,
          height: badgeSize.height,
        ),
      ),
    );
  }
}

class _KnockoutBadgePainter extends CustomPainter {
  const _KnockoutBadgePainter({
    required this.textPainter,
    required this.sourceStyle,
    required this.textDirection,
    required this.badgeSize,
  });

  final TextPainter textPainter;
  final TextStyle sourceStyle;
  final TextDirection textDirection;
  final Size badgeSize;

  @override
  void paint(Canvas canvas, Size size) {
    final bounds = Offset.zero & size;

    // Isolate dstOut to this tiny badge so it cuts the glyph from the
    // translucent background without erasing the surrounding UI.
    canvas.saveLayer(bounds, Paint());
    canvas.drawRRect(
      RRect.fromRectAndRadius(bounds, const Radius.circular(2.43)),
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
    return oldDelegate.sourceStyle != sourceStyle ||
        oldDelegate.textDirection != textDirection ||
        oldDelegate.badgeSize != badgeSize;
  }
}
