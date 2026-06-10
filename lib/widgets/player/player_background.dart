import 'dart:typed_data';
import 'dart:ui';

import 'package:flutter/material.dart';

import '../../services/media_store_service.dart';

class AnimatedBlurredPlayerBackground extends StatefulWidget {
  final int songId;

  const AnimatedBlurredPlayerBackground({super.key, required this.songId});

  @override
  State<AnimatedBlurredPlayerBackground> createState() =>
      _AnimatedBlurredPlayerBackgroundState();
}

class _AnimatedBlurredPlayerBackgroundState
    extends State<AnimatedBlurredPlayerBackground> {
  Future<Uint8List?>? _artworkFuture;

  @override
  void initState() {
    super.initState();
    _updateArtworkFuture();
  }

  @override
  void didUpdateWidget(AnimatedBlurredPlayerBackground oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.songId != widget.songId) {
      _updateArtworkFuture();
    }
  }

  void _updateArtworkFuture() {
    _artworkFuture = widget.songId > 0
        ? MediaStoreService.getArtwork(widget.songId)
        : Future<Uint8List?>.value();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Uint8List?>(
      key: ValueKey<int>(widget.songId),
      future: _artworkFuture,
      builder: (context, snapshot) {
        final artwork = snapshot.data;
        final child = artwork == null || artwork.isEmpty
            ? const PlayerFallbackBackground(key: ValueKey<String>('fallback'))
            : BlurredArtworkBackground(
                key: ValueKey<int>(widget.songId),
                artwork: artwork,
              );

        return AnimatedSwitcher(
          duration: const Duration(milliseconds: 420),
          switchInCurve: Curves.easeOutCubic,
          switchOutCurve: Curves.easeOutCubic,
          child: child,
        );
      },
    );
  }
}

class BlurredArtworkBackground extends StatelessWidget {
  final Uint8List artwork;

  const BlurredArtworkBackground({super.key, required this.artwork});

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final cacheWidth =
        (width * MediaQuery.of(context).devicePixelRatio / 2).round();

    return Stack(
      fit: StackFit.expand,
      children: [
        Transform.scale(
          scale: 1.16,
          child: ImageFiltered(
            imageFilter: ImageFilter.blur(sigmaX: 32, sigmaY: 32),
            child: Image.memory(
              artwork,
              fit: BoxFit.cover,
              gaplessPlayback: true,
              cacheWidth: cacheWidth,
              filterQuality: FilterQuality.low,
            ),
          ),
        ),
        const ColoredBox(color: Color.fromARGB(130, 0, 0, 0)),
      ],
    );
  }
}

class PlayerFallbackBackground extends StatelessWidget {
  const PlayerFallbackBackground({super.key});

  @override
  Widget build(BuildContext context) {
    return const DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(0xFF2A2A2E),
            Color(0xFF111113),
            Color(0xFF000000),
          ],
        ),
      ),
    );
  }
}
