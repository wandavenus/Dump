part of '../player_background.dart';

class _AnimatedBlurredPlayerBackgroundState
    extends State<AnimatedBlurredPlayerBackground> {
  int          _songId  = -1;
  List<Color>  _palette = const [];

  @override
  void initState() {
    super.initState();
    _loadPalette(widget.songId);
  }

  @override
  void didUpdateWidget(AnimatedBlurredPlayerBackground old) {
    super.didUpdateWidget(old);
    if (old.songId != widget.songId) {
      _loadPalette(widget.songId);
    }
  }

  Future<void> _loadPalette(int id) async {
    if (id <= 0) {
      if (mounted) setState(() { _songId = id; _palette = const []; });
      return;
    }

    // Fast path: already in the LRU cache — no I/O needed.
    final cached = PaletteExtractor.getSync(id);
    if (cached != null) {
      if (mounted) setState(() { _songId = id; _palette = cached; });
      return;
    }

    // Slow path: fetch artwork bytes then run palette_generator extraction.
    final bytes = await ArtworkRepository.instance.getBytes(id);
    if (!mounted || widget.songId != id) return;

    if (bytes == null || bytes.isEmpty) {
      setState(() { _songId = id; _palette = const []; });
      return;
    }

    final colors = await PaletteExtractor.get(id, bytes);
    if (!mounted || widget.songId != id) return;

    setState(() { _songId = id; _palette = colors; });
  }

  @override
  Widget build(BuildContext context) {
    final Widget child = _palette.isEmpty
        ? const PlayerFallbackBackground(key: ValueKey<String>('fallback'))
        : ProceduralFogBackground(
            key:     ValueKey<int>(_songId),
            songId:  _songId,
            palette: _palette,
          );

    return AnimatedSwitcher(
      duration:       const Duration(milliseconds: 480),
      switchInCurve:  Curves.easeOut,
      switchOutCurve: Curves.easeIn,
      child: child,
    );
  }
}
