part of '../lyrics_page.dart';

class _LyricsPageState extends State<LyricsPage>
    with SingleTickerProviderStateMixin {
  late Future<LyricsResult> _lyricsFuture;
  late AnimationController _fadeCtrl;
  late Animation<double> _fade;

  @override
  void initState() {
    super.initState();
    _lyricsFuture = LyricsService.fetchLyrics(
      title: widget.song.title,
      artist: widget.song.artist,
      filePath: widget.song.path.isNotEmpty ? widget.song.path : null,
    );
    _fadeCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 360));
    _fade = CurvedAnimation(parent: _fadeCtrl, curve: Curves.easeOut);
    _fadeCtrl.forward();
  }

  @override
  void dispose() {
    _fadeCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          // Latar album art blur
          _LyricsBackground(songId: widget.song.id),

          // Overlay gelap + tambahan blur
          ValueListenableBuilder<double>(
            valueListenable: LyricsSettings.bgDim,
            builder: (_, dim, __) => ValueListenableBuilder<double>(
              valueListenable: LyricsSettings.blurStrength,
              builder: (_, blur, __) => Stack(
                fit: StackFit.expand,
                children: [
                  if (blur > 0)
                    BackdropFilter(
                      filter: ImageFilter.blur(
                          sigmaX: blur * 0.3, sigmaY: blur * 0.3),
                      child: const SizedBox.expand(),
                    ),
                  ColoredBox(
                      color: Colors.black.withValues(alpha: dim.clamp(0.0, 0.95).toDouble())),
                ],
              ),
            ),
          ),

          // Gradient atas dan bawah
          const _EdgeGradients(),

          // Konten utama
          FadeTransition(
            opacity: _fade,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _LyricsHeader(song: widget.song),
                Expanded(
                  child: FutureBuilder<LyricsResult>(
                    future: _lyricsFuture,
                    builder: (context, snapshot) {
                      if (snapshot.connectionState != ConnectionState.done) {
                        return const Center(
                          child: CircularProgressIndicator(
                            color: Colors.white24,
                            strokeWidth: 2,
                          ),
                        );
                      }
                      final result = snapshot.data ??
                          const LyricsResult([], LyricsSource.none);
                      if (result.isEmpty) {
                        return _EmptyLyrics(song: widget.song);
                      }
                      return _LyricsBody(result: result);
                    },
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Latar blur ────────────────────────────────────────────────────────────────
