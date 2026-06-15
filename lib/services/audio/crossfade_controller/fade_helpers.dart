part of '../crossfade_controller.dart';

// ─── Crossfade tick/fade library functions ────────────────────────────────────
//
//  Library-level functions extracted from CrossfadeController.
//  They access CrossfadeController private static fields directly, which is
//  valid because part files share the same library scope.
// ─────────────────────────────────────────────────────────────────────────────

void _cfOnTick(Timer _) {
  final crossSec = AudioEffectsService.crossfadeDuration.value;
  final active   = AudioEngine.activePlayer;

  if (active.processingState == ProcessingState.idle ||
      active.processingState == ProcessingState.completed) {
    if (CrossfadeController._crossfading) CrossfadeController._crossfading = false;
    return;
  }

  final pos = active.position;
  final dur = active.duration;
  if (dur == null || dur.inMilliseconds <= 0) return;

  final remainingMs = (dur - pos).inMilliseconds;
  if (remainingMs < 0) return;

  if (crossSec <= 0) {
    if (CrossfadeController._crossfading) CrossfadeController.cancel();
    return;
  }

  final crossMs = (crossSec * 1000).round();

  if (!CrossfadeController._crossfading && remainingMs > 0 && remainingMs <= crossMs) {
    final nextIdx  = CrossfadeController._getNextIndex?.call();
    final nextSong = nextIdx != null ? CrossfadeController._getSong?.call(nextIdx) : null;
    if (nextIdx != null && nextSong != null) {
      CrossfadeController._pendingIndex = nextIdx;
      CrossfadeController._crossfading  = true;
      CrossfadeController._standbyReady = false;
      _cfStartStandby(nextSong);
    }
    return;
  }

  if (CrossfadeController._crossfading && CrossfadeController._standbyReady) {
    if (remainingMs <= 0) {
      _cfComplete();
      return;
    }
    final ratio = (remainingMs / crossMs).clamp(0.0, 1.0);
    AudioEngine.activeSlot.setVolume(_cfEaseOut(ratio));
    AudioEngine.standbySlot.setVolume(_cfEaseIn(1.0 - ratio));

    if (ratio <= 0.01) _cfComplete();
  }
}

Future<void> _cfStartStandby(LocalSong song) async {
  try {
    final standby = AudioEngine.standbyPlayer;
    AudioEngine.standbySlot.setVolume(0.0);
    await standby.setAudioSource(buildAudioSource(song));
    await standby.play();
    CrossfadeController._standbyReady = true;
    LogService.log('Crossfade', 'Standby loaded: ${song.title}');
  } catch (e) {
    LogService.warn('Crossfade', 'startStandby failed: $e');
    CrossfadeController._crossfading  = false;
    CrossfadeController._standbyReady = false;
    CrossfadeController._pendingIndex = null;
  }
}

void _cfComplete() {
  final prevActivePlayer = AudioEngine.activePlayer;
  final nextIdx          = CrossfadeController._pendingIndex;

  AudioEngine.handoff();
  AudioEngine.activeSlot.setVolume(1.0);

  try {
    prevActivePlayer.stop();
    prevActivePlayer.setVolume(1.0);
  } catch (_) {}

  CrossfadeController._crossfading  = false;
  CrossfadeController._standbyReady = false;
  CrossfadeController._pendingIndex = null;

  if (nextIdx != null) {
    CrossfadeController._onHandoffComplete?.call(nextIdx);
    LogService.log('Crossfade', 'Complete → index $nextIdx');
  }
}

double _cfEaseIn(double t)  => t * t;
double _cfEaseOut(double t) => 1.0 - (1.0 - t) * (1.0 - t);
