import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';

import 'artwork_blur_image_renderer.dart';

class _BlurredArtworkFrame {
  _BlurredArtworkFrame(this.image);

  final ui.Image image;
  int users = 0;
}

class _PendingBlurredArtwork {
  final Completer<_BlurredArtworkFrame?> completer =
      Completer<_BlurredArtworkFrame?>();
  int waiters = 1;
}

/// Lease for a cached blurred image. A frame cannot be disposed while leased.
class ArtworkBlurImageLease {
  ArtworkBlurImageLease._(this._frame);

  final _BlurredArtworkFrame _frame;
  bool _released = false;

  ui.Image get image => _frame.image;

  void release() {
    if (_released) return;
    _released = true;
    ArtworkBlurCache._release(_frame);
  }
}

/// Small memory-only LRU of pre-rendered blur frames.
///
/// It intentionally caches only generated 384px images. The source artwork
/// remains owned by ArtworkRepository, and no blurred frame is written to disk.
class ArtworkBlurCache {
  ArtworkBlurCache._();

  static const int _maxEntries = 3;
  static final Map<String, _BlurredArtworkFrame> _frames = {};
  static final Map<String, _PendingBlurredArtwork> _pending = {};
  static bool _evictionScheduled = false;

  static Future<ArtworkBlurImageLease?> acquire({
    required String key,
    required ImageProvider provider,
    required double sigma,
  }) async {
    final cached = _frames.remove(key);
    if (cached != null) {
      _frames[key] = cached;
      cached.users++;
      return ArtworkBlurImageLease._(cached);
    }

    final existingPending = _pending[key];
    if (existingPending != null) {
      existingPending.waiters++;
      final frame = await existingPending.completer.future;
      if (frame == null) return null;
      final current = _frames.remove(key);
      if (identical(current, frame)) _frames[key] = frame;
      return ArtworkBlurImageLease._(frame);
    }

    final pending = _PendingBlurredArtwork();
    _pending[key] = pending;
    try {
      final image = await ArtworkBlurImageRenderer.create(
        provider: provider,
        sigma: sigma,
      );
      if (image == null) {
        pending.completer.complete(null);
        return null;
      }

      // Every caller waiting on this in-flight key receives a reserved lease.
      final frame = _BlurredArtworkFrame(image)..users = pending.waiters;
      _frames[key] = frame;
      pending.completer.complete(frame);
      _evict();
      return ArtworkBlurImageLease._(frame);
    } on Object catch (_) {
      if (!pending.completer.isCompleted) pending.completer.complete(null);
      return null;
    } finally {
      if (identical(_pending[key], pending)) _pending.remove(key);
    }
  }

  static void _release(_BlurredArtworkFrame frame) {
    if (frame.users > 0) frame.users--;
    _evict();
  }

  static void _evict() {
    if (_frames.length <= _maxEntries || _evictionScheduled) return;
    if (!_frames.values.any((frame) => frame.users == 0)) return;

    // Defer disposal until after Flutter has completed the current paint, so a
    // RawImage from the previous frame can never reference a disposed ui.Image.
    _evictionScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _evictionScheduled = false;
      while (_frames.length > _maxEntries) {
        String? victimKey;
        for (final entry in _frames.entries) {
          if (entry.value.users == 0) {
            victimKey = entry.key;
            break;
          }
        }
        if (victimKey == null) return;

        final victim = _frames.remove(victimKey);
        victim?.image.dispose();
      }
    });
    WidgetsBinding.instance.scheduleFrame();
  }
}
