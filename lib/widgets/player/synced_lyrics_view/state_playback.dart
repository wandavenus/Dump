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
      if (!_frameTicker.isActive) _frameTicker.start();
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

    _anchorPos = position;
    _anchorWallMs = DateTime.now().millisecondsSinceEpoch;

    if (_isPlaying && !_frameTicker.isActive) _frameTicker.start();

    _maybeUpdateCurrentLine(position, allowBinarySearch: true);
    _karaokeController.updatePosition(position);
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
