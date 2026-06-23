import 'package:flutter/material.dart';

import '../services/artwork_repository.dart';

/// Displays a song's artwork using the persistent [ArtworkRepository] cache.
///
/// Load order (handled by the repository):
///   Memory cache → Disk WebP file → Native MediaStore extraction.
///
/// After first extraction artwork is served from disk ([FileImage]) with no
/// MethodChannel calls.  Flutter's own [ImageCache] prevents re-decoding
/// already-loaded images during the same session.
class SongArtwork extends StatefulWidget {
  final int songId;
  final double size;
  final BorderRadius borderRadius;
  final BoxFit fit;

  const SongArtwork({
    super.key,
    required this.songId,
    this.size = 55,
    this.borderRadius = const BorderRadius.all(Radius.circular(4)),
    this.fit = BoxFit.cover,
  });

  @override
  State<SongArtwork> createState() => _SongArtworkState();
}

class _SongArtworkState extends State<SongArtwork> {
  ImageProvider? _provider;

  // _requestedId: ID of the most recent _load() call.
  // _loading:     whether an async load is currently in flight.
  // Together these implement a "latest-wins" strategy: if the widget's songId
  // changes while a load is in flight, the loop picks up the new ID.
  int  _requestedId = -1;
  bool _loading     = false;

  @override
  void initState() {
    super.initState();
    _load(widget.songId);
  }

  @override
  void didUpdateWidget(covariant SongArtwork old) {
    super.didUpdateWidget(old);
    if (old.songId != widget.songId) {
      _load(widget.songId);
      return;
    }
    // Re-load when size crosses the full-res threshold (250 px).
    // The morphing artwork widget starts at mini-player size (~46 px) and grows
    // to full-player size (~350 px) during the open animation.  Because _load
    // bakes targetSizePx from widget.size at call time, a provider obtained at
    // mini-player size is a ResizeImage(FileImage, ~139, ~139) — permanently
    // blurry when stretched to full-player dimensions.  Detecting the threshold
    // crossing here forces a reload with targetSizePx: null so the full-res
    // FileImage is used for the full player.
    final wasSmall = old.size < 250;
    final isLarge  = widget.size >= 250;
    if (wasSmall && isLarge) _load(widget.songId);
  }

  Future<void> _load(int songId) async {
    _requestedId = songId;
    if (_loading) return; // running loop will pick up the new _requestedId

    _loading = true;
    // Loop so a changed _requestedId is always served (covers fast scrolling).
    while (mounted) {
      final targetId = _requestedId;

      // Read pixel ratio before the await (safe on the UI isolate).
      final dpr      = WidgetsBinding.instance.platformDispatcher.views.first.devicePixelRatio;
      final targetPx = (widget.size * dpr).round();

      final provider = await ArtworkRepository.instance.getProvider(
      targetId,
      targetSizePx: widget.size >= 250 ? null : targetPx,
      );

      if (!mounted) break;

      if (_requestedId == targetId) {
        // Still the right song — apply and stop.
        setState(() => _provider = provider);
        break;
      }
      // _requestedId changed while we were awaiting — loop for the new ID.
    }
    _loading = false;
  }

  @override
  Widget build(BuildContext context) {
    final p = _provider;
    if (p != null) {
      return ClipRRect(
        borderRadius: widget.borderRadius,
        child: Image(
          image: p,
          width: widget.size,
          height: widget.size,
          fit: widget.fit,
          gaplessPlayback: true,
          filterQuality: FilterQuality.medium,
          errorBuilder: (_, _, _) => _fallback(),
        ),
      );
    }
    return _fallback();
  }

  Widget _fallback() => Container(
        width: widget.size,
        height: widget.size,
        decoration: BoxDecoration(
          borderRadius: widget.borderRadius,
          color: Colors.grey.shade900,
        ),
        child: const Icon(Icons.music_note),
      );
}
