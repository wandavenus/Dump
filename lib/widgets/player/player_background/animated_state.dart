part of '../player_background.dart';

class _AnimatedBlurredPlayerBackgroundState
    extends State<AnimatedBlurredPlayerBackground> {
  int _songId = -1;
  List<Color> _palette = const [];

  @override
  void initState() {
    super.initState();
    unawaited(_loadPalette(widget.songId));
  }

  @override
  void didUpdateWidget(AnimatedBlurredPlayerBackground old) {
    super.didUpdateWidget(old);
    if (old.songId != widget.songId) {
      unawaited(_loadPalette(widget.songId));
    }
  }

  Future<void> _loadPalette(int id, {int attempt = 0}) async {
    if (id <= 0) {
      // Clear palette so PlayerFallbackBackground is shown, not stale colors
      // from the previously-playing song.
      if (mounted) {
        setState(() {
          _songId = id;
          _palette = const [];
        });
      }
      return;
    }

    // Fast path: already in the LRU cache — no I/O needed.
    final cached = NativePaletteService.getSync(id);
    if (cached != null) {
      if (mounted) {
        setState(() {
          _songId = id;
          _palette = cached;
        });
      }
      return;
    }

    // Slow path: native bridge extracts colours from ArtworkCacheManager.
    final colors = await NativePaletteService.get(id);
    if (!mounted || widget.songId != id) return;

    // ArtworkCacheManager and Media3 can finish their work just after the
    // palette call starts during a shuffle transition. The service deliberately
    // does not cache this hard fallback, so retry a few times before showing it.
    if (NativePaletteService.isHardFallback(colors) && attempt < 3) {
      await Future<void>.delayed(const Duration(milliseconds: 250));
      if (mounted && widget.songId == id) {
        await _loadPalette(id, attempt: attempt + 1);
      }
      return;
    }

    setState(() {
      _songId = id;
      _palette = colors;
    });
  }

  @override
  Widget build(BuildContext context) {
    final Widget child = _palette.isEmpty
        ? const PlayerFallbackBackground()
        : ProceduralFogBackground(songId: _songId, palette: _palette);

    return child;
  }
}
