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

  // Hoisting Paint & Filter ke level statis biar gak re-alokasi di memory terus-menerus
  static final ui.Paint _frontPaint = ui.Paint()
    ..imageFilter = ui.ImageFilter.blur(
      sigmaX: 30,
      sigmaY: 30,
      tileMode: ui.TileMode.mirror,
    );

  static final ui.Paint _backPaint = ui.Paint()
    ..imageFilter = ui.ImageFilter.blur(
      sigmaX: 20,
      sigmaY: 20,
      tileMode: ui.TileMode.mirror,
    );  

  static BlurredPair? _touch(int songId) {
    final value = _cache.remove(songId);
    if (value != null) {
      _cache[songId] = value;
    }
    return value;
  }
  
  static BlurredPair? getSync(int songId) => _touch(songId);

  static void preload(int songId, Uint8List bytes) {
    if (_cache.containsKey(songId) || _pending.containsKey(songId)) return;
    get(songId, bytes);
  }

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

    _compute(bytes).then((img) {
      // Guard race condition aman
      if (_pending[songId] != completer) {
        img?.dispose();
        if (!completer.isCompleted) completer.complete(null);
        return;
      }

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
      if (_pending[songId] == completer) {
        _pending.remove(songId);
      }
      if (!completer.isCompleted) completer.complete(null);
    });

    return completer.future;
  }

  static Future<BlurredPair?> _compute(Uint8List bytes) async {
    if (bytes.isEmpty) return null;

    try {
      final codec = await ui.instantiateImageCodec(bytes, targetWidth: 128);
      final frame = await codec.getNextFrame();
      codec.dispose();

      final src = frame.image;
      final width = src.width;
      final height = src.height;
      final bounds = ui.Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble());
   
      Future<ui.Image> renderBlur(ui.Paint paint) async {
        final recorder = ui.PictureRecorder();
        final canvas = ui.Canvas(recorder, bounds);

        canvas.drawImage(src, ui.Offset.zero, paint);

        final picture = recorder.endRecording();
        final image = await picture.toImage(width, height);
        picture.dispose();

        return image;
      }

      // Concurrency super ngebut pake static paint yang udah di-cache
      final blurredImages = await Future.wait([
        renderBlur(_frontPaint),
        renderBlur(_backPaint),
      ]);

      src.dispose();

      return BlurredPair(
        front: blurredImages[0],
        back: blurredImages[1],
      );
    } catch (_) {
      return null;
    }
  }

  static void evict(int songId) {
    _cache[songId]?.dispose();
    _cache.remove(songId);
    _pending.remove(songId); 
  }

  static void clear() {
    for (final img in _cache.values) {
      img.dispose();
    }
    _cache.clear();
    _pending.clear(); 
  }
}
