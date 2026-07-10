import 'package:flutter/material.dart';

import '../services/artwork_repository.dart';

/// Hairline border overlaid on every piece of artwork (mirrors Apple Music
/// Android's thin white stroke around covers), so artwork never visually
/// merges into a background of similar tone.
const Color kArtworkHairlineColor = Color(0x29FFFFFF); // white @ ~16% opacity
const double kArtworkHairlineWidth = 0.75;

/// Wraps [child] with the shared hairline border, matching [borderRadius].
/// Uses [foregroundDecoration] so the stroke paints on top of the image
/// without affecting layout — safe to use around animated/resizing artwork.
class ArtworkHairlineBorder extends StatelessWidget {
  final BorderRadius borderRadius;
  final Widget child;

  const ArtworkHairlineBorder({
    super.key,
    required this.borderRadius,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      foregroundDecoration: BoxDecoration(
        borderRadius: borderRadius,
        border: Border.all(
          color: kArtworkHairlineColor,
          width: kArtworkHairlineWidth,
          // Inset alignment (matches Apple Music) so the stroke is drawn
          // fully inside the visible bounds instead of straddling the edge —
          // stays crisp instead of anti-aliasing/blurring outward, and is
          // never partially clipped by an outer ClipRRect of the same radius.
          strokeAlign: BorderSide.strokeAlignInside,
        ),
      ),
      child: child,
    );
  }
}

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

  /// Whether to draw the shared hairline stroke around this artwork.
  /// Set to false when the caller already draws the stroke itself on an
  /// outer bounding box (e.g. animated/morphing artwork that crops this
  /// widget via FittedBox, where a border drawn here would be scaled or
  /// clipped incorrectly) — avoids doubled/mismatched borders.
  final bool showBorder;

  const SongArtwork({
    super.key,
    required this.songId,
    this.size = 55,
    this.borderRadius = const BorderRadius.all(Radius.circular(3)),
    this.fit = BoxFit.cover,
    this.showBorder = true,
  });

  @override
  State<SongArtwork> createState() => _SongArtworkState();
}

/// Deep equality for [ImageProvider] that handles [ResizeImage] wrapping a
/// [FileImage].  Flutter's built-in [FileImage.==] compares path + scale, but
/// [ResizeImage] does NOT override [==] — two instances with identical
/// parameters compare as unequal by object identity.  We need value-equality
/// here so the "skip setState if provider didn't change" guard in [_load] works
/// correctly for both small (ResizeImage) and full-size (FileImage) artwork.
bool _providersEqual(ImageProvider? a, ImageProvider? b) {
  if (identical(a, b)) return true;
  if (a == null || b == null) return false;
  if (a.runtimeType != b.runtimeType) return false;
  // FileImage already has a correct value-equality operator.
  if (a is FileImage) return a == b;
  // ResizeImage: compare target dimensions + the inner provider recursively.
  if (a is ResizeImage && b is ResizeImage) {
    return a.width == b.width &&
        a.height == b.height &&
        _providersEqual(a.imageProvider, b.imageProvider);
  }
  return false;
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
    // Synchronous first-frame check: if this artwork is already on disk
    // (cached from a previous session), render it immediately instead of
    // showing a placeholder while the async lookup resolves. This is what
    // makes cover art appear instantly after the app is killed/reopened.
    final dpr      = WidgetsBinding.instance.platformDispatcher.views.first.devicePixelRatio;
    final targetPx = (widget.size * dpr).round();
    _provider = ArtworkRepository.instance.getProviderSync(
      widget.songId,
      targetSizePx: widget.size >= 250 ? null : targetPx,
    );
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
    try {
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
          // Only rebuild if the provider actually changed.  getProviderSync may
          // have already set _provider to an equivalent provider — avoid an
          // unnecessary setState → widget rebuild → visual flicker.
          //
          // NOTE: FileImage has correct value equality (compares path + scale),
          // but ResizeImage does NOT override == and falls back to object
          // identity.  _providersEqual() handles both cases explicitly.
          if (!_providersEqual(provider, _provider)) {
            setState(() => _provider = provider);
          }
          break;
        }
        // _requestedId changed while we were awaiting — loop for the new ID.
      }
    } finally {
      // Always reset, even if getProvider() throws, so future loads are not
      // permanently suppressed by a stuck _loading flag.
      _loading = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = _provider;
    if (p != null) {
      final image = ClipRRect(
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
      if (!widget.showBorder) return image;
      return ArtworkHairlineBorder(
        borderRadius: widget.borderRadius,
        child: image,
      );
    }
    return _fallback();
  }

  Widget _fallback() {
    final placeholder = Container(
      width: widget.size,
      height: widget.size,
      decoration: BoxDecoration(
        borderRadius: widget.borderRadius,
        color: Colors.grey.shade900,
      ),
    );
    if (!widget.showBorder) return placeholder;
    return ArtworkHairlineBorder(
      borderRadius: widget.borderRadius,
      child: placeholder,
    );
  }
}
