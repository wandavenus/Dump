part of '../synced_lyrics_view.dart';

extension _SyncedLyricsViewPlaybackState on _SyncedLyricsViewState {
  // ── Playback state ────────────────────────────────────────────────────────

  void _syncFromPlaybackState(AudioPlaybackState s) {
    _isPlaying = s.isPlaying;
    _speed = s.speed.clamp(0.1, 4.0);
  }

  void _onPlaybackState() {
    final s = AudioService.playbackState.value;
    final wasPlaying = _isPlaying;
    _syncFromPlaybackState(s);

    if (_isPlaying) {
      if (!_frameTicker.isActive) unawaited(_frameTicker.start());
    } else {
      if (_frameTicker.isActive) _frameTicker.stop();
      if (wasPlaying) {
        _anchorPos = s.position;
        _anchorWallMs = DateTime.now().millisecondsSinceEpoch;
        _karaokeController.updatePosition(s.position);
      }
    }
  }

  void _onPosition(Duration position) {
    // ── Media3 Proximity Guard: Sumbat data purba pasca seek ───────────
    if (_pendingSeekPos != null) {
      final delta = (position - _pendingSeekPos!).inMilliseconds.abs();
      if (delta > 1000) {
        return; // Cuekin data lama yang selisihnya jauh dari target bby (ᵔ◡ᵔ)
      } else {
        _pendingSeekPos = null; // Udah sinkron ama target, open guard!
      }
    }
    // ─────────────────────────────────────────────────────────────────

    final nowMs = DateTime.now().millisecondsSinceEpoch;
    final wasPlaying = _isPlaying;

    if (!wasPlaying) {
      _anchorPos = position;
      _anchorWallMs = nowMs;
    } else {
      // Native position events arrive every 200 ms and may already be slightly
      // stale by the time they cross the platform channel. Re-anchoring
      // directly to every event causes the 60 FPS interpolation to jump back.
      // Apply only a small bounded correction so the visual clock remains
      // continuous while still converging to the real audio position.
      final predicted = _interpolatedPosition;
      final deltaMs = position.inMilliseconds - predicted.inMilliseconds;
      if (deltaMs.abs() > 1000) {
        // Large discontinuities are intentional seeks or track changes.
        _anchorPos = position;
      } else {
        final correctionMs = (deltaMs * 0.18).round().clamp(-40, 40);
        _anchorPos = predicted + Duration(milliseconds: correctionMs);
      }
      _anchorWallMs = nowMs;
    }

    if (_isPlaying && !_frameTicker.isActive) unawaited(_frameTicker.start());

    // Keep line selection on the same corrected clock as the painter.
    // Using raw native timestamps here can switch the line ahead of the
    // smoothly interpolated word highlight.
    _maybeUpdateCurrentLine(_anchorPos, allowBinarySearch: true);
    // Use the corrected anchor, NOT the raw native position.
    // Raw position causes a 200 ms snap every time the EventChannel fires,
    // which is what made the highlight appear to jump.
    _karaokeController.updatePosition(_anchorPos);
  }

  void _onFrameTick(Duration _) {
    if (!mounted || widget.lyrics.isEmpty) return;
    final position = _interpolatedPosition;
    _maybeUpdateCurrentLine(position, allowBinarySearch: false);
    _karaokeController.updatePosition(position);
  }

  Duration get _interpolatedPosition {
    if (!_isPlaying) return _anchorPos;
    final wallElapsedMs = DateTime.now().millisecondsSinceEpoch - _anchorWallMs;
    final audioElapsedMs = (wallElapsedMs * _speed).round();
    return _anchorPos + Duration(milliseconds: audioElapsedMs);
  }
}
