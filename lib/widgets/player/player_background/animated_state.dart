part of '../player_background.dart';

class _AnimatedBlurredPlayerBackgroundState
    extends State<AnimatedBlurredPlayerBackground>
    with TickerProviderStateMixin {
  Future<Uint8List?>? _artworkFuture;

  Widget? _previousLayer;
  Widget? _currentLayer;

  late final AnimationController _fadeController;

  @override
  void initState() {
    super.initState();

    _fadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
      value: 1,
    );

    _updateArtworkFuture();
  }

  @override
  void dispose() {
    _fadeController.dispose();
    super.dispose();
  }

        if (_currentLayer == null) {
  _currentLayer = newLayer;
} else if (_currentLayer!.key != newLayer.key) {
  _previousLayer = _currentLayer;
  _currentLayer = newLayer;

  _fadeController
    ..stop()
    ..reset()
    ..forward();

  _fadeController.addStatusListener((status) {
    if (status == AnimationStatus.completed && mounted) {
      setState(() {
        _previousLayer = null;
      });
    }
  });
}

        return Stack(
  fit: StackFit.expand,
  children: [
    if (_previousLayer != null)
      Positioned.fill(
        child: _previousLayer!,
      ),

    if (_currentLayer != null)
      Positioned.fill(
        child: FadeTransition(
          opacity: CurvedAnimation(
            parent: _fadeController,
            curve: Curves.easeInOutQuart,
          ),
          child: ScaleTransition(
            scale: Tween<double>(
              begin: 1.0,
              end: 1.0,
            ).animate(
              CurvedAnimation(
                parent: _fadeController,
                curve: Curves.easeOutCubic,
              ),
            ),
            child: _currentLayer!,
          ),
        ),
      ),
  ],
);
