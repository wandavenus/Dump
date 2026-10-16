import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';

/// Rasterizes a decoded artwork into a blurred image at source resolution.
///
/// The UI layer chooses the sigma in source pixels so scaling the result to the
/// full-screen viewport preserves the requested on-screen blur radius.
class ArtworkBlurImageRenderer {
  static Future<ui.Image?> create({
    required ImageProvider provider,
    required double sigma,
  }) async {
    final source = await _resolveSource(provider);
    if (source == null) return null;
    return _renderBlur(source, sigma);
  }

  static Future<ui.Image?> _resolveSource(ImageProvider provider) async {
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
      return await completer.future.timeout(
        const Duration(seconds: 6),
        onTimeout: () => null,
      );
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

    final bounds = ui.Rect.fromLTWH(
      0,
      0,
      width.toDouble(),
      height.toDouble(),
    );
    final recorder = ui.PictureRecorder();

    try {
      final canvas = ui.Canvas(recorder);
      canvas.saveLayer(
        bounds,
        ui.Paint()
          ..imageFilter = ui.ImageFilter.blur(
            sigmaX: sigma,
            sigmaY: sigma,
            tileMode: ui.TileMode.clamp,
          ),
      );
      canvas.drawImageRect(
        source,
        bounds,
        bounds,
        ui.Paint()..filterQuality = FilterQuality.low,
      );
      canvas.restore();

      final picture = recorder.endRecording();
      try {
        return await picture.toImage(width, height);
      } finally {
        picture.dispose();
      }
    } catch (_) {
      return null;
    }
  }
}
