import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

/// Pre-renders artwork blur to a cached [ui.Image] at reduced resolution.
///
/// Calling [get] the first time triggers async GPU rendering via
/// PictureRecorder. Subsequent calls return the cached image synchronously
/// via [getSync], so every frame is just a cheap texture blit with no
/// runtime ImageFilter cost.
class BlurredImageCache {
  BlurredImageCache._();

  static final Map<int, ui.Image> _cache = {};
  static final Map<int, Completer<ui.Image?>> _pending = {};

  /// Returns the pre-blurred image synchronously if cached, otherwise null.
  static ui.Image? getSync(int songId) => _cache[songId];

  /// Returns a pre-blurred [ui.Image] for [songId], computing it if needed.
  static Future<ui.Image?> get(int songId, Uint8List bytes) {
    if (_cache.containsKey(songId)) {
      return Future.value(_cache[songId]);
    }
    if (_pending.containsKey(songId)) {
      return _pending[songId]!.future;
    }

    final completer = Completer<ui.Image?>();
    _pending[songId] = completer;
    _compute(songId, bytes).then((img) {
      if (img != null) _cache[songId] = img;
      _pending.remove(songId);
      completer.complete(img);
    }).catchError((Object _) {
      _pending.remove(songId);
      completer.complete(null);
    });

    return completer.future;
  }

  static Future<ui.Image?> _compute(int songId, Uint8List bytes) async {
    try {
      // Decode at 1/3 size — at sigma 30 blur any detail is already lost.
      final codec = await ui.instantiateImageCodec(bytes, targetWidth: 200);
      final frame = await codec.getNextFrame();
      final src = frame.image;

      final w = src.width.toDouble();
      final h = src.height.toDouble();

      // Render the image with heavy blur into a PictureRecorder.
      // tileMode.mirror prevents dark halo at edges.
      final recorder = ui.PictureRecorder();
      final canvas = ui.Canvas(
        recorder,
        ui.Rect.fromLTWH(0, 0, w, h),
      );
      canvas.drawImage(
        src,
        ui.Offset.zero,
        ui.Paint()
          ..imageFilter = ui.ImageFilter.blur(
            sigmaX: 28,
            sigmaY: 28,
            tileMode: ui.TileMode.mirror,
          ),
      );
      src.dispose();

      final picture = recorder.endRecording();
      final result = await picture.toImage(w.toInt(), h.toInt());
      picture.dispose();

      return result;
    } catch (_) {
      return null;
    }
  }

  /// Evict a single song's cache (e.g. when it is removed from library).
  static void evict(int songId) {
    _cache[songId]?.dispose();
    _cache.remove(songId);
  }

  static void clear() {
    for (final img in _cache.values) {
      img.dispose();
    }
    _cache.clear();
  }
}
