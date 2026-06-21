// animated_state.dart
part of '../player_background.dart';

class _AnimatedBlurredPlayerBackgroundState
    extends State<AnimatedBlurredPlayerBackground> with TickerProviderStateMixin {
  Future<Uint8List?>? _artworkFuture;
  Uint8List? _cachedArtwork;
  Uint8List? _previousArtwork;
  bool _isLoading = false;
  Color? _dominantColor;
  Color? _previousDominantColor;
  
  // Cache artwork untuk menghindari loading ulang
  static final Map<int, Uint8List> _artworkCache = {};
  static final Map<int, Color> _colorCache = {};

  @override
  void initState() {
    super.initState();
    _initializeArtwork();
  }

  @override
  void didUpdateWidget(AnimatedBlurredPlayerBackground oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.songId != widget.songId) {
      _handleSongChange();
    }
  }

  @override
  void dispose() {
    _artworkFuture = null;
    super.dispose();
  }

  void _initializeArtwork() {
    if (widget.songId > 0) {
      _loadArtwork();
    } else {
      _setFallbackState();
    }
  }

  void _handleSongChange() {
    // Simpan artwork sebelumnya untuk transisi
    _previousArtwork = _cachedArtwork;
    _previousDominantColor = _dominantColor;
    
    // Reset loading state
    _isLoading = true;
    
    if (widget.songId > 0) {
      _loadArtwork();
    } else {
      _setFallbackState();
    }
  }

  void _loadArtwork() async {
    // Cek cache
    if (_artworkCache.containsKey(widget.songId)) {
      _cachedArtwork = _artworkCache[widget.songId];
      _dominantColor = _colorCache[widget.songId];
      _isLoading = false;
      setState(() {});
      return;
    }

    // Load artwork dengan Future
    _artworkFuture = MediaStoreService.getArtwork(widget.songId);
    
    try {
      final artwork = await _artworkFuture;
      
      if (artwork != null && artwork.isNotEmpty) {
        _cachedArtwork = artwork;
        _artworkCache[widget.songId] = artwork;
        
        // Extract dominant color (async)
        _extractDominantColor(artwork).then((color) {
          if (color != null) {
            _dominantColor = color;
            _colorCache[widget.songId] = color;
            if (mounted) setState(() {});
          }
        });
      } else {
        _cachedArtwork = null;
        _dominantColor = null;
      }
    } catch (e) {
      // Error handling - fallback ke state sebelumnya
      _cachedArtwork = null;
      _dominantColor = null;
    } finally {
      _isLoading = false;
      if (mounted) setState(() {});
    }
  }

  void _setFallbackState() {
    _cachedArtwork = null;
    _dominantColor = null;
    _isLoading = false;
    if (mounted) setState(() {});
  }

  Future<Color?> _extractDominantColor(Uint8List artwork) async {
    try {
      // Gunakan compute atau isolate untuk ekstraksi warna
      // Implementasi sederhana dengan image package
      final image = await decodeImageFromList(artwork);
      final imageSize = image.width * image.height;
      
      if (imageSize == 0) return null;
      
      // Sampling pixel untuk dominant color
      final step = imageSize > 10000 ? 10 : 5;
      final colorMap = <int, int>{};
      
      for (int y = 0; y < image.height; y += step) {
        for (int x = 0; x < image.width; x += step) {
          final pixel = image.getPixel(x, y);
          final color = Color(pixel);
          final key = color.value;
          colorMap[key] = (colorMap[key] ?? 0) + 1;
        }
      }
      
      if (colorMap.isEmpty) return null;
      
      final dominantKey = colorMap.entries.reduce((a, b) => a.value > b.value ? a : b).key;
      return Color(dominantKey);
    } catch (e) {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    // Tentukan artwork yang akan ditampilkan
    final currentArtwork = _cachedArtwork;
    final previousArtwork = _previousArtwork;
    
    // Tentukan warna dominan
    final currentColor = _dominantColor ?? Colors.grey.shade900;
    final previousColor = _previousDominantColor ?? Colors.grey.shade900;
    
    // Jika loading dan tidak ada artwork, tampilkan morph color
    if (_isLoading && currentArtwork == null) {
      return _buildMorphingBackground(
        previousColor: previousColor,
        currentColor: currentColor,
        showArtwork: false,
      );
    }
    
    // Jika ada artwork, tampilkan dengan morph
    if (currentArtwork != null) {
      return _buildMorphingBackground(
        previousColor: previousColor,
        currentColor: currentColor,
        artwork: currentArtwork,
        showArtwork: true,
      );
    }
    
    // Fallback dengan morph color
    return _buildMorphingBackground(
      previousColor: previousColor,
      currentColor: currentColor,
      showArtwork: false,
    );
  }

  Widget _buildMorphingBackground({
    required Color previousColor,
    required Color currentColor,
    Uint8List? artwork,
    bool showArtwork = false,
  }) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 600),
      switchInCurve: Curves.easeInOutCubic,
      switchOutCurve: Curves.easeOutCubic,
      child: _MorphingBackground(
        key: ValueKey('morph_${widget.songId}_${showArtwork ? 'artwork' : 'fallback'}'),
        previousColor: previousColor,
        currentColor: currentColor,
        artwork: artwork,
        showArtwork: showArtwork,
        songId: widget.songId,
      ),
    );
  }
}

// Widget untuk morphing background dengan animasi smooth
class _MorphingBackground extends StatefulWidget {
  final Color previousColor;
  final Color currentColor;
  final Uint8List? artwork;
  final bool showArtwork;
  final int songId;

  const _MorphingBackground({
    Key? key,
    required this.previousColor,
    required this.currentColor,
    this.artwork,
    required this.showArtwork,
    required this.songId,
  }) : super(key: key);

  @override
  State<_MorphingBackground> createState() => _MorphingBackgroundState();
}

class _MorphingBackgroundState extends State<_MorphingBackground> 
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<Color?> _colorAnimation;
  late Animation<double> _opacityAnimation;
  
  Color? _previousColor;
  Color? _currentColor;

  @override
  void initState() {
    super.initState();
    _setupAnimations();
  }

  @override
  void didUpdateWidget(_MorphingBackground oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.currentColor != widget.currentColor || 
        oldWidget.showArtwork != widget.showArtwork) {
      _updateAnimations();
    }
  }

  void _setupAnimations() {
    _controller = AnimationController(
      duration: const Duration(milliseconds: 600),
      vsync: this,
    );
    
    _previousColor = widget.previousColor;
    _currentColor = widget.currentColor;
    
    _colorAnimation = ColorTween(
      begin: _previousColor,
      end: _currentColor,
    ).animate(CurvedAnimation(
      parent: _controller,
      curve: Curves.easeInOutCubic,
    ));
    
    _opacityAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.3, 1.0, curve: Curves.easeOutCubic),
    ));
    
    _controller.forward();
  }

  void _updateAnimations() {
    _previousColor = _colorAnimation.value ?? widget.previousColor;
    _currentColor = widget.currentColor;
    
    _controller.reset();
    
    _colorAnimation = ColorTween(
      begin: _previousColor,
      end: _currentColor,
    ).animate(CurvedAnimation(
      parent: _controller,
      curve: Curves.easeInOutCubic,
    ));
    
    _opacityAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.3, 1.0, curve: Curves.easeOutCubic),
    ));
    
    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final color = _colorAnimation.value ?? widget.currentColor;
        
        return Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: _getGradientColors(color),
              stops: const [0.0, 0.5, 1.0],
            ),
          ),
          child: Stack(
            fit: StackFit.expand,
            children: [
              // Artwork dengan blur efek
              if (widget.showArtwork && widget.artwork != null)
                Opacity(
                  opacity: _opacityAnimation.value,
                  child: _buildBlurredArtwork(widget.artwork!),
                ),
              
              // Overlay gradient untuk smooth transition
              Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      color.withOpacity(0.3),
                      color.withOpacity(0.7),
                      color.withOpacity(0.9),
                    ],
                    stops: const [0.0, 0.5, 1.0],
                  ),
                ),
              ),
              
              // Subtle pattern overlay untuk depth
              Container(
                decoration: BoxDecoration(
                  gradient: RadialGradient(
                    center: Alignment.center,
                    radius: 1.5,
                    colors: [
                      Colors.white.withOpacity(0.05),
                      Colors.transparent,
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildBlurredArtwork(Uint8List artwork) {
    return Image.memory(
      artwork,
      fit: BoxFit.cover,
      gaplessPlayback: true,
      errorBuilder: (context, error, stackTrace) => const SizedBox.shrink(),
      frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
        if (frame == null) {
          return const SizedBox.shrink();
        }
        return ClipRRect(
          child: BackdropFilter(
            filter: ImageFilter.blur(
              sigmaX: 40.0,
              sigmaY: 40.0,
            ),
            child: child,
          ),
        );
      },
    );
  }

  List<Color> _getGradientColors(Color baseColor) {
    // Generate gradient colors dari base color
    final hsl = HSLColor.fromColor(baseColor);
    final darker = hsl.withLightness((hsl.lightness - 0.2).clamp(0.0, 1.0)).toColor();
    final lighter = hsl.withLightness((hsl.lightness + 0.15).clamp(0.0, 1.0)).toColor();
    final saturated = hsl.withSaturation((hsl.saturation + 0.2).clamp(0.0, 1.0)).toColor();
    
    return [darker, baseColor, lighter];
  }
}

// Extension untuk clamp
extension ClampExtension on double {
  double clamp(double min, double max) {
    return this < min ? min : (this > max ? max : this);
  }
}
