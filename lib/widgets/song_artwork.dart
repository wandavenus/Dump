import 'dart:async' show unawaited;

import 'package:flutter/material.dart';

import '../services/artwork_repository.dart';
import '../theme/app_colors.dart';

/// Hairline border overlaid on every piece of artwork, tuned per brightness
/// so it stays visible without looking harsh against light or dark covers.
const Color kArtworkHairlineDarkColor = Color(0x29FFFFFF); // white @ ~16%
const Color kArtworkHairlineLightColor = Color(0x29000000); // black @ ~16%
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
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final hairlineColor = isDark
        ? kArtworkHairlineDarkColor
        : kArtworkHairlineLightColor;

    return Container(
      foregroundDecoration: BoxDecoration(
        borderRadius: borderRadius,
        border: Border.all(
          color: hairlineColor,
          width: kArtworkHairlineWidth,
          // Inset alignment keeps the stroke crisp inside the visible bounds.
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
/// MethodChannel calls. Flutter's own [ImageCache] prevents re-decoding
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

  /// Fade the artwork itself to transparency at the bottom (0 = disabled).
  final double bottomFadeStrength;

  const SongArtwork({
    super.key,
    required this.songId,
    this.size = 55,
    this.borderRadius = const BorderRadius.all(Radius.circular(3)),
    this.fit = BoxFit.cover,
    this.showBorder = true,
    this.bottomFadeStrength = 0.0,
  });

  @override
  State<SongArtwork> createState() => _SongArtworkState();
}

/// Deep equality for [ImageProvider] that handles [ResizeImage] wrapping a
/// [FileImage]. Flutter's built-in [FileImage.==] compares path + scale, but
/// [ResizeImage] does NOT override [==] — two instances with identical
/// parameters compare as unequal by object identity. We need value-equality
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
  // _loading: whether an async load is currently in flight.
  // Together these implement a "latest-wins" strategy: if the widget's songId
  // changes while a load is in flight, the loop picks up the new ID.
  int _requestedId = -1;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    // Synchronous first-frame check: if this artwork is already on disk
    // (cached from a previous session), render it immediately instead of
    // showing a placeholder while the async lookup resolves.
    final targetPx = ArtworkRepository.instance.resolveTargetPx(widget.size);
    _provider = ArtworkRepository.instance.getProviderSync(
      widget.songId,
      targetSizePx: widget.size >= 250 ? null : targetPx,
    );
    unawaited(_load(widget.songId));
  }

  @override
  void didUpdateWidget(covariant SongArtwork old) {
    super.didUpdateWidget(old);
    if (old.songId != widget.songId) {
      unawaited(_load(widget.songId));
      return;
    }
    // Re-load when size crosses the full-res threshold (250 px).
    final wasSmall = old.size < 250;
    final isLarge = widget.size >= 250;
    if (wasSmall && isLarge) unawaited(_load(widget.songId));
  }

  Future<void> _load(int songId) async {
    _requestedId = songId;
    if (_loading) return; // running loop will pick up the new _requestedId

    _loading = true;
    try {
      while (mounted) {
        final targetId = _requestedId;
        final targetPx = ArtworkRepository.instance.resolveTargetPx(
          widget.size,
        );

        final provider = await ArtworkRepository.instance.getProvider(
          targetId,
          targetSizePx: widget.size >= 250 ? null : targetPx,
        );

        if (!mounted) break;

        if (_requestedId == targetId) {
          if (!_providersEqual(provider, _provider)) {
            setState(() => _provider = provider);
          }
          break;
        }
      }
    } finally {
      _loading = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = _provider;
    if (p != null) {
      Widget image = ClipRRect(
        borderRadius: widget.borderRadius,
        child: Image(
          image: p,
          width: widget.size,
          height: widget.size,
          fit: widget.fit,
          gaplessPlayback: true,
          filterQuality: FilterQuality.medium,
          errorBuilder: (_, _, _) => _fallback(context),
        ),
      );
      final fadeStrength = widget.bottomFadeStrength.clamp(0.0, 1.0);
      if (fadeStrength > 0.001) {
        // Use a broad, gently accelerating alpha falloff so the lower edge
        // dissolves into the blurred background instead of forming a seam.
        image = ShaderMask(
          blendMode: BlendMode.dstIn,
          shaderCallback: (bounds) => LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Colors.white,
              Colors.white,
              Colors.white.withValues(alpha: 1.0 - fadeStrength * 0.01),
              Colors.white.withValues(alpha: 1.0 - fadeStrength * 0.04),
              Colors.white.withValues(alpha: 1.0 - fadeStrength * 0.10),
              Colors.white.withValues(alpha: 1.0 - fadeStrength * 0.22),
              Colors.white.withValues(alpha: 1.0 - fadeStrength * 0.43),
              Colors.white.withValues(alpha: 1.0 - fadeStrength * 0.68),
              Colors.white.withValues(alpha: 1.0 - fadeStrength * 0.88),
              Colors.white.withValues(alpha: 1.0 - fadeStrength * 0.97),
              Colors.white.withValues(alpha: 1.0 - fadeStrength),
            ],
            stops: const [
              0.0,
              0.55,
              0.63,
              0.70,
              0.77,
              0.83,
              0.88,
              0.92,
              0.96,
              0.985,
              1.0,
            ],
          ).createShader(bounds),
          child: image,
        );
      }
      if (!widget.showBorder) return image;
      return ArtworkHairlineBorder(
        borderRadius: widget.borderRadius,
        child: image,
      );
    }
    return _fallback(context);
  }

  Widget _fallback(BuildContext context) {
    final bgColor = AppColors.of(context).surface3;
    final placeholder = Container(
      width: widget.size,
      height: widget.size,
      decoration: BoxDecoration(
        borderRadius: widget.borderRadius,
        color: bgColor,
      ),
    );
    if (!widget.showBorder) return placeholder;
    return ArtworkHairlineBorder(
      borderRadius: widget.borderRadius,
      child: placeholder,
    );
  }
}
