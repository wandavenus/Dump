part of '../playback_manager.dart';

// ── Transport ─────────────────────────────────────────────────────────────

  static Future<void> play()           => Media3PlaybackBridge.play();
  static Future<void> pause()          => Media3PlaybackBridge.pause();
  static Future<void> stop()           => Media3PlaybackBridge.stop();
  static Future<void> seek(Duration p) => Media3PlaybackBridge.seek(p);
  static Future<void> skipNext()       => Media3PlaybackBridge.skipNext();
  static Future<void> skipPrevious()   => Media3PlaybackBridge.skipPrevious();
  static Future<void> setTrack(int i)  => Media3PlaybackBridge.setTrack(i);

  // ── Mode ──────────────────────────────────────────────────────────────────

  static Future<void> setRepeatMode(String m) =>
      Media3PlaybackBridge.setRepeatMode(m);
  static Future<void> setShuffleMode(bool e) =>
      Media3PlaybackBridge.setShuffleMode(e);

  // ── Playback parameters ───────────────────────────────────────────────────

  static Future<void> setVolume(double v) => Media3PlaybackBridge.setVolume(v);
  static Future<void> setSpeed(double v)  => Media3PlaybackBridge.setSpeed(v);
  static Future<void> setPitch(double v)  => Media3PlaybackBridge.setPitch(v);

  // ── Queue mutations ───────────────────────────────────────────────────────

  static Future<void> setQueue(List<LocalSong> q, int i) =>
      Media3PlaybackBridge.setQueue(q, i);
  static Future<void> insertNext(LocalSong s) =>
      Media3PlaybackBridge.insertNext(s);
  static Future<void> appendToQueue(LocalSong s) =>
      Media3PlaybackBridge.appendToQueue(s);
  static Future<void> removeFromQueue(int i) =>
      Media3PlaybackBridge.removeFromQueue(i);
  static Future<void> reorderQueue(int o, int n) =>
      Media3PlaybackBridge.reorderQueue(o, n);
