part of '../playback_manager.dart';

// ── Artwork prefetch ───────────────────────────────────────────────────────

  static Future<void> _prefetchArtwork(int index) async {
    try {
      if (index < 0 || index >= _currentQueue.length) return;

      final song = _currentQueue[index];

      if (!_prefetchingSongs.add(song.id)) {
        return;
      }

      if (_activePrefetches >= _maxConcurrentPrefetches) {
        _prefetchingSongs.remove(song.id);
        return;
      }

      _activePrefetches++;

      if (PaletteExtractor.getSync(song.id) != null) {
        return;
      }

      final bytes = await ArtworkRepository.instance.getBytes(song.id);
      if (bytes == null) return;

      if (PaletteExtractor.getSync(song.id) != null) {
        return;
      }

      await PaletteExtractor.get(song.id, bytes);
    } catch (_) {
      // Ignore prefetch failures.
    } finally {
      if (index >= 0 && index < _currentQueue.length) {
        _prefetchingSongs.remove(_currentQueue[index].id);
        if (_activePrefetches > 0) {
          _activePrefetches--;
        }
      }
    }
  }
