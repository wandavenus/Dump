import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';

/// Rasterizes a decoded artwork into a blurred image with an edge-extended
/// gutter. The gutter keeps the blur kernel away from the raster bounds so
/// the viewport edges do not fade toward transparent/black pixels.
class ArtworkBlurImageRenderer {
  static Future<ui.Image?> create({
    required ImageProvider provider,
    required double sigma,
  }) async {
    final completer = Completer<ui.Image?>();
    ImageStream? stream;
    ImageStreamListener? listener;

    try {
      stream = provider.resolve(ImageConfiguration.empty);
      listener = ImageStreamListener(
        (info, _) {
          if (!completer.isCompleted) completer.complete(info.image);
        },
        onError: (Object _, StackTrace? __) {
          if (!completer.isCompleted) completer.complete(null);
        },
      );
      stream.addListener(listener);

      // Keep the stream listener alive until rasterization finishes so the
      // source image remains live if Flutter's global ImageCache is pressured.
      final source = await completer.future.timeout(
        const Duration(seconds: 6),
        onTimeout: () => null,
      );
      if (source == null) return null;
      return await _renderBlur(source, sigma);
    } catch (_) {
      return null;
    } finally {
      if (stream != null && listener != null) {
        stream.removeListener(listener);
      }
    }
  }

  static Future<ui.Image?> _renderBlur(ui.Image source, double sigma) async {
    final width = source.width;
    final height = source.height;
    if (width <= 0 || height <= 0) return null;

    // A Gaussian blur needs pixels outside the visible source bounds. Without
    // a gutter, the blur output is clipped at all four edges and can look like
    // a dark vignette around the screen. Extend edge pixels by ~3 sigma first.
    final padding = (sigma * 3).ceil().clamp(1, 96).toInt();
    final outputWidth = width + padding * 2;
    final outputHeight = height + padding * 2;
    final outputBounds = ui.Rect.fromLTWH(
      0,
      0,
      outputWidth.toDouble(),
      outputHeight.toDouble(),
    );
    final sourceBounds = ui.Rect.fromLTWH(
      0,
      0,
      width.toDouble(),
      height.toDouble(),
    );
    final recorder = ui.PictureRecorder();

    try {
      final canvas = ui.Canvas(recorder);
      canvas.saveLayer(
        outputBounds,
        ui.Paint()
          ..imageFilter = ui.ImageFilter.blur(
            sigmaX: sigma,
            sigmaY: sigma,
            tileMode: ui.TileMode.clamp,
          ),
      );

      final paint = ui.Paint()..filterQuality = FilterQuality.low;
      final center = ui.Rect.fromLTWH(
        padding.toDouble(),
        padding.toDouble(),
        width.toDouble(),
        height.toDouble(),
      );
      canvas.drawImageRect(source, sourceBounds, center, paint);

      // Extend the outermost rows and columns instead of leaving transparent
      // pixels in the blur kernel's sampling area.
      canvas.drawImageRect(
        source,
        ui.Rect.fromLTWH(0, 0, width.toDouble(), 1),
        ui.Rect.fromLTWH(
          padding.toDouble(),
          0,
          width.toDouble(),
          padding.toDouble(),
        ),
        paint,
      );
      canvas.drawImageRect(
        source,
        ui.Rect.fromLTWH(0, height - 1, width.toDouble(), 1),
        ui.Rect.fromLTWH(
          padding.toDouble(),
          (padding + height).toDouble(),
          width.toDouble(),
          padding.toDouble(),
        ),
        paint,
      );
      canvas.drawImageRect(
        source,
        ui.Rect.fromLTWH(0, 0, 1, height.toDouble()),
        ui.Rect.fromLTWH(
          0,
          padding.toDouble(),
          padding.toDouble(),
          height.toDouble(),
        ),
        paint,
      );
      canvas.drawImageRect(
        source,
        ui.Rect.fromLTWH(width - 1, 0, 1, height.toDouble()),
        ui.Rect.fromLTWH(
          (padding + width).toDouble(),
          padding.toDouble(),
          padding.toDouble(),
          height.toDouble(),
        ),
        paint,
      );

      // Fill the four corners with their corresponding edge pixels.
      canvas.drawImageRect(
        source,
        const ui.Rect.fromLTWH(0, 0, 1, 1),
        ui.Rect.fromLTWH(0, 0, padding.toDouble(), padding.toDouble()),
        paint,
      );
      canvas.drawImageRect(
        source,
        ui.Rect.fromLTWH(width - 1, 0, 1, 1),
        ui.Rect.fromLTWH(
          (padding + width).toDouble(),
          0,
          padding.toDouble(),
          padding.toDouble(),
        ),
        paint,
      );
      canvas.drawImageRect(
        source,
        ui.Rect.fromLTWH(0, height - 1, 1, 1),
        ui.Rect.fromLTWH(
          0,
          (padding + height).toDouble(),
          padding.toDouble(),
          padding.toDouble(),
        ),
        paint,
      );
      canvas.drawImageRect(
        source,
        ui.Rect.fromLTWH(width - 1, height - 1, 1, 1),
        ui.Rect.fromLTWH(
          (padding + width).toDouble(),
          (padding + height).toDouble(),
          padding.toDouble(),
          padding.toDouble(),
        ),
        paint,
      );

      canvas.restore();

      final picture = recorder.endRecording();
      try {
        return await picture.toImage(outputWidth, outputHeight);
      } finally {
        picture.dispose();
      }
    } catch (_) {
      return null;
    }
  }
}
