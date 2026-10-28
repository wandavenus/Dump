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
    this.badgeReferenceFontSize,
  });

  /// Song-list variant with a normalized badge size, independent of title style.
  /// The title itself keeps its normal inherited or explicitly supplied style.
  const ExplicitSongTitle.list({
    super.key,
    required this.song,
    this.style,
    this.maxLines,
    required this.overflow,
    this.textAlign,
  }) : badgeReferenceFontSize = 15;

  final LocalSong song;
  final TextStyle? style;
  final int? maxLines;
  final TextOverflow overflow;
  final TextAlign? textAlign;

  /// Optional font-size reference used only for badge sizing, not title styling.
  final double? badgeReferenceFontSize;

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
            ExplicitAdvisoryBadge(
              titleStyle: titleStyle ?? inheritedStyle,
              referenceFontSize: widget.badgeReferenceFontSize,
            ),
          ],
        );
      },
    );
  }
}

/// Shared explicit-content marker used by song titles and player overlays.
/// The E is a real transparent cutout, not transparent text over a solid tile.
class ExplicitAdvisoryBadge extends StatefulWidget {
  const ExplicitAdvisoryBadge({
    super.key,
    required this.titleStyle,
    this.referenceFontSize,
  });

  /// The title's style; retained for the badge glyph typography.
  final TextStyle titleStyle;

  /// Optional font-size reference for the badge, independent of title size.
  final double? referenceFontSize;

  @override
  State<ExplicitAdvisoryBadge> createState() => _ExplicitAdvisoryBadgeState();
}

class _ExplicitAdvisoryBadgeState extends State<ExplicitAdvisoryBadge> {
  TextStyle? _sourceStyle;
  double? _sourceReferenceFontSize;
  TextDirection? _textDirection;
  TextPainter? _textPainter;
  Size _badgeSize = Size.zero;

  void _configurePainterIfNeeded(TextDirection textDirection) {
    if (_textPainter != null &&
        _sourceStyle == widget.titleStyle &&
        _sourceReferenceFontSize == widget.referenceFontSize &&
        _textDirection == textDirection) {
      return;
    }

    _sourceStyle = widget.titleStyle;
    _sourceReferenceFontSize = widget.referenceFontSize;
    _textDirection = textDirection;

    final badgeStyle = widget.titleStyle.copyWith(
      fontSize:
          (widget.referenceFontSize ?? widget.titleStyle.fontSize ?? 14) * 0.78,
      fontWeight: FontWeight.w700,
      letterSpacing: 0.1,
    );

    // Keep the established proportions while reducing the entire badge by
    // another 5% (81% × 95% = 76.95% of the original derived dimensions).
    const previousBadgeScale = 0.81;
    const additionalBadgeScale = 0.95;
    final knockoutScale = previousBadgeScale * additionalBadgeScale;
    final knockoutStyle = TextStyle(
      inherit: false,
      fontFamily: badgeStyle.fontFamily,
      fontFamilyFallback: badgeStyle.fontFamilyFallback,
      fontSize: (badgeStyle.fontSize ?? 14) * knockoutScale,
      fontWeight: badgeStyle.fontWeight,
      fontStyle: badgeStyle.fontStyle,
      letterSpacing: badgeStyle.letterSpacing,
      wordSpacing: badgeStyle.wordSpacing,
      height: badgeStyle.height,
      textBaseline: badgeStyle.textBaseline,
      locale: badgeStyle.locale,
      foreground: Paint()..blendMode = BlendMode.dstOut,
    );

    final textPainter = TextPainter(
      text: TextSpan(text: 'E', style: knockoutStyle),
      textDirection: textDirection,
    )..layout();

    _textPainter = textPainter;
    final paddedWidth = textPainter.width + 6 * knockoutScale;
    final paddedHeight = textPainter.height + 4 * knockoutScale;
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
        child: SizedBox(width: badgeSize.width, height: badgeSize.height),
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
      RRect.fromRectAndRadius(bounds, const Radius.circular(2.43 * 0.95)),
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
