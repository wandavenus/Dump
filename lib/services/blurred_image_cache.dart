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

  static const int _maxEntries = 100;
  class BlurredPair {
  final ui.Image front;
  final ui.Image back;

  const BlurredPair({
    required this.front,
    required this.back,
  });
  }

  static final Map<int, BlurredPair> _cache = {};
  static final Map<int, Completer<BlurredPair?>> _pending = {};

  /// Returns the pre-blurred image synchronously if cached, otherwise null.
  static BlurredPair? getSync(int songId) => _cache[songId];
  /// Returns a pre-blurred [ui.Image] for [songId], computing it if needed.
  static Future<BlurredPair?> get(int songId, Uint8List bytes) {
    if (_cache.containsKey(songId)) {
      return Future.value(_cache[songId]);
    }
    if (_pending.containsKey(songId)) {
      return _pending[songId]!.future;
    }

    final completer = Completer<BlurredPair?>();
    _pending[songId] = completer;
    _compute(songId, bytes).then((img) {
            if (img != null) {
        if (_cache.length >= _maxEntries) {
          final oldestKey = _cache.keys.first;
          _cache.remove(oldestKey)?.dispose();
        }
        _cache[songId] = img;
      }
      _pending.remove(songId);
      completer.complete(img);
    }).catchError((Object _) {
      _pending.remove(songId);
      completer.complete(null);
    });

    return completer.future;
  }

  static Future<BlurredPair?> _compute(int songId, Uint8List bytes) async {
    try {
      // Decode at 1/3 size — at sigma 30 blur any detail is already lost.
      final codec = await ui.instantiateImageCodec(bytes, targetWidth: 200);
      final frame = await codec.getNextFrame();
      final src = frame.image;

      final w = src.width.toDouble();
      final h = src.height.toDouble();

      // Render the image with heavy blur into a PictureRecorder.
      // tileMode.mirror prevents dark halo at edges.
      Future<ui.Image> renderBlur(double sigma) async {
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
        sigmaX: sigma,
        sigmaY: sigma,
        tileMode: ui.TileMode.mirror,
      ),
  );

  final picture = recorder.endRecording();
  final image = await picture.toImage(w.toInt(), h.toInt());
  picture.dispose();

  return image;
}

final front = await renderBlur(24);
final back = await renderBlur(60);

src.dispose();

return BlurredPair(
  front: front,
  back: back,
);
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
