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
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: 3,
                vertical: 2,
              ),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.18),
                borderRadius: BorderRadius.circular(3),
              ),
              child: Text(
                'E',
                style: badgeStyle.copyWith(color: Colors.white),
              ),
            ),
          ],
        );
      },
    );
  }
}
