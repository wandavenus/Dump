part of '../lyrics_page.dart';

class _LyricsBackgroundState extends State<_LyricsBackground> {
  Future<Uint8List?>? _artFuture;

  @override
  void initState() {
    super.initState();
    if (widget.songId > 0) {
      _artFuture = MediaStoreService.getArtwork(widget.songId);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_artFuture == null) return const _LyricsGradient();
    return FutureBuilder<Uint8List?>(
      future: _artFuture,
      builder: (_, snap) {
        final art = snap.data;
        if (art == null || art.isEmpty) return const _LyricsGradient();
        return ValueListenableBuilder<double>(
          valueListenable: LyricsSettings.blurStrength,
          builder: (_, blur, __) => SizedBox.expand(
            child: Transform.scale(
              scale: 1.3,
              child: ImageFiltered(
                imageFilter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
                child: Image.memory(
                  art,
                  fit: BoxFit.cover,
                  gaplessPlayback: true,
                  filterQuality: FilterQuality.low,
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
