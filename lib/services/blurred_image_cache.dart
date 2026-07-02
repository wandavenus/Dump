import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

class BlurredPair {
  final ui.Image front;
  final ui.Image back;

  const BlurredPair({
    required this.front,
    required this.back,
  });
 
  void dispose() {
    front.dispose();
    back.dispose();
    }
  }

class BlurredImageCache {
  BlurredImageCache._();

  static const int _maxEntries = 80;
  

  static final Map<int, BlurredPair> _cache = {};
  static final Map<int, Completer<BlurredPair?>> _pending = {};

  static BlurredPair? _touch(int songId) {
  final value = _cache.remove(songId);
  if (value != null) {
    _cache[songId] = value;
  }
  return value;
  }
  
  /// Returns the pre-blurred image synchronously if cached, otherwise null.
  static BlurredPair? getSync(int songId) => _touch(songId);
  /// Returns a pre-blurred [ui.Image] for [songId], computing it if needed.
  static Future<BlurredPair?> get(int songId, Uint8List bytes) {
  final cached = _touch(songId);
  if (cached != null) {
    return Future.value(cached);
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
  if (bytes.isEmpty) return null;

  try {
      // Decode at 1/3 size — at sigma 30 blur any detail is already lost.
      final codec = await ui.instantiateImageCodec(bytes, targetWidth: 192);
      final frame = await codec.getNextFrame();
      codec.dispose();
      final src = frame.image;

      final w = src.width.toDouble();
      final h = src.height.toDouble();
      final width = src.width;
      final height = src.height;
      final bounds = ui.Rect.fromLTWH(
      0,
      0,
      width.toDouble(),
      height.toDouble(),
      );
   
      final frontPaint = ui.Paint()
  ..imageFilter = ui.ImageFilter.blur(
    sigmaX: 40,
    sigmaY: 40,
    tileMode: ui.TileMode.mirror,
  );

final backPaint = ui.Paint()
  ..imageFilter = ui.ImageFilter.blur(
    sigmaX: 30,
    sigmaY: 30,
    tileMode: ui.TileMode.mirror,
  );  
    
    // Render the image with heavy blur into a PictureRecorder.
      // tileMode.mirror prevents dark halo at edges.
      Future<ui.Image> renderBlur(ui.Paint paint) async {
      final recorder = ui.PictureRecorder();
      final canvas = ui.Canvas(
      recorder,
      bounds,
      );

      canvas.drawImage(
  src,
  ui.Offset.zero,
  paint,
);

  final picture = recorder.endRecording();
  final image = await picture.toImage(
  width,
  height,
);
  picture.dispose();

  return image;
}

final front = await renderBlur(frontPaint);
final back = await renderBlur(backPaint);

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
