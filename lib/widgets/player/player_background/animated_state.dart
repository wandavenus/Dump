part of '../player_background.dart';

class _AnimatedBlurredPlayerBackgroundState
    extends State<AnimatedBlurredPlayerBackground>
    with SingleTickerProviderStateMixin {

  Uint8List? _currentArtwork;
  Uint8List? _previousArtwork;

  late final AnimationController _controller;
  late final Animation<double> _fade;

  int? _loadingSongId;

  @override
  void initState() {
    super.initState();

    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );

    _fade = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOutCubic,
    );

    _controller.addStatusListener((status) {
      if (status == AnimationStatus.completed && mounted) {
        setState(() {
          _previousArtwork = null;
        });
      }
    });

    _loadArtwork(widget.songId);
  }

  @override
  void didUpdateWidget(
    AnimatedBlurredPlayerBackground oldWidget,
  ) {
    super.didUpdateWidget(oldWidget);

    if (oldWidget.songId != widget.songId) {
      _loadArtwork(widget.songId);
    }
  }

  Future<void> _loadArtwork(int songId) async {
    _loadingSongId = songId;

    final artwork = songId > 0
        ? await MediaStoreService.getArtwork(songId)
        : null;

    if (!mounted) return;
    if (_loadingSongId != songId) return;

    if (_currentArtwork == null) {
      setState(() {
        _currentArtwork = artwork;
      });
      return;
    }

    setState(() {
      _previousArtwork = _currentArtwork;
      _currentArtwork = artwork;
    });

    _controller
      ..reset()
      ..forward();
  }

  Widget _buildLayer(Uint8List? artwork) {
    if (artwork == null || artwork.isEmpty) {
      return const PlayerFallbackBackground();
    }

    return BlurredArtworkBackground(
      songId: widget.songId,
      artwork: artwork,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        if (_previousArtwork != null)
          Positioned.fill(
            child: _buildLayer(_previousArtwork),
          ),

        if (_currentArtwork != null)
          Positioned.fill(
            child: FadeTransition(
              opacity: _fade,
              child: _buildLayer(_currentArtwork),
            ),
          ),

        if (_currentArtwork == null &&
            _previousArtwork == null)
          const Positioned.fill(
            child: PlayerFallbackBackground(),
          ),
      ],
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }
}
