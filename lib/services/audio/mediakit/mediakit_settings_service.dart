import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:media_kit/media_kit.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../log_service.dart';

/// Pengaturan native khusus untuk engine media_kit (libmpv).
///
/// Setiap setting disimpan ke SharedPreferences dan diterapkan ke
/// [NativePlayer] via setProperty() saat engine aktif.
///
/// Dipanggil oleh [MediaKitEngine.initialize()] setelah player dibuat.
///
/// Fitur yang dikelola:
///   1. Gapless Playback (mpv: gapless-audio)
///   2. Pitch Shifting proper — diaktifkan via PlayerConfiguration(pitch:true)
///      di engine; tidak ada setting di sini.
///   3. Multi-format — otomatis via libmpv; info saja di UI.
///   4. ReplayGain native (mpv: replaygain / replaygain-preamp)
///   5. Cache & Buffer (mpv: cache / demuxer-readahead-secs)
class MediaKitSettingsService {
  MediaKitSettingsService._();

  // ── Kunci SharedPreferences ──────────────────────────────────────────────

  static const _kGapless      = 'mk_gapless';
  static const _kRgEnabled    = 'mk_rg_enabled';
  static const _kRgMode       = 'mk_rg_mode';       // 'track' | 'album'
  static const _kRgPreamp     = 'mk_rg_preamp';     // double, dB
  static const _kRgClip       = 'mk_rg_clip';
  static const _kCacheEnabled = 'mk_cache_enabled';
  static const _kCacheSecs    = 'mk_cache_secs';    // int

  // ── ValueNotifiers ───────────────────────────────────────────────────────

  /// Transisi mulus antar lagu (mpv gapless-audio).
  static final gaplessEnabled     = ValueNotifier<bool>(true);

  /// ReplayGain aktif — baca tag dari file secara native.
  static final replayGainEnabled  = ValueNotifier<bool>(false);

  /// Mode ReplayGain: 'track' atau 'album'.
  static final replayGainMode     = ValueNotifier<String>('track');

  /// Preamp ReplayGain dalam dB (rentang −15 … +15).
  static final replayGainPreampDb = ValueNotifier<double>(0.0);

  /// Cegah clipping saat gain tinggi.
  static final replayGainClip     = ValueNotifier<bool>(true);

  /// Aktifkan prebuffer demuxer.
  static final cacheEnabled       = ValueNotifier<bool>(true);

  /// Durasi readahead buffer dalam detik (5 … 60).
  static final cacheReadaheadSecs = ValueNotifier<int>(30);

  // ── Referensi ke player aktif ─────────────────────────────────────────────

  /// Diset oleh [MediaKitEngine.initialize()], dikosongkan oleh dispose().
  static Player? _activePlayer;

  static void registerPlayer(Player player) {
    _activePlayer = player;
  }

  static void unregisterPlayer() {
    _activePlayer = null;
  }

  // ── Init ─────────────────────────────────────────────────────────────────

  static Future<void> initialize() async {
    final prefs = await SharedPreferences.getInstance();

    gaplessEnabled.value     = prefs.getBool(_kGapless)      ?? true;
    replayGainEnabled.value  = prefs.getBool(_kRgEnabled)    ?? false;
    replayGainMode.value     = prefs.getString(_kRgMode)     ?? 'track';
    replayGainPreampDb.value = prefs.getDouble(_kRgPreamp)   ?? 0.0;
    replayGainClip.value     = prefs.getBool(_kRgClip)       ?? true;
    cacheEnabled.value       = prefs.getBool(_kCacheEnabled) ?? true;
    cacheReadaheadSecs.value = prefs.getInt(_kCacheSecs)     ?? 30;

    LogService.log('MediaKitSettings', 'Loaded from prefs');
  }

  // ── Apply to player ───────────────────────────────────────────────────────

  /// Terapkan semua setting ke [player] yang baru diinisialisasi.
  ///
  /// Dipanggil oleh [MediaKitEngine.initialize()] setelah player dibuat.
  ///
  /// Menggunakan `dynamic` untuk memanggil setProperty() agar web compiler
  /// tidak error pada NativePlayer stub yang tidak memiliki method tersebut.
  static Future<void> applyAll(Player player) async {
    if (kIsWeb) return;
    final p = player.platform;
    if (p is! NativePlayer) return;
    // Cast ke dynamic untuk menghindari kompilasi web-stub type error.
    final native = p as dynamic;

    await _applyGapless(native);
    await _applyReplayGain(native);
    await _applyCache(native);

    LogService.log('MediaKitSettings', 'All settings applied to player');
  }

  static Future<void> _applyGapless(dynamic p) async {
    await p.setProperty(
      'gapless-audio',
      gaplessEnabled.value ? 'yes' : 'no',
    );
  }

  static Future<void> _applyReplayGain(dynamic p) async {
    if (replayGainEnabled.value) {
      await p.setProperty('replaygain', replayGainMode.value);
      await p.setProperty(
        'replaygain-preamp',
        replayGainPreampDb.value.toStringAsFixed(1),
      );
      await p.setProperty(
        'replaygain-clip',
        replayGainClip.value ? 'yes' : 'no',
      );
    } else {
      await p.setProperty('replaygain', 'no');
    }
  }

  static Future<void> _applyCache(dynamic p) async {
    if (cacheEnabled.value) {
      await p.setProperty('cache', 'yes');
      await p.setProperty(
        'demuxer-readahead-secs',
        '${cacheReadaheadSecs.value}',
      );
    } else {
      await p.setProperty('cache', 'no');
    }
  }

  // ── Setters ───────────────────────────────────────────────────────────────

  static Future<void> setGapless(bool v) async {
    gaplessEnabled.value = v;
    await _saveBool(_kGapless, v);
    await _withNative(_applyGapless);
    LogService.log('MediaKitSettings', 'gapless=$v');
  }

  static Future<void> setReplayGainEnabled(bool v) async {
    replayGainEnabled.value = v;
    await _saveBool(_kRgEnabled, v);
    await _withNative(_applyReplayGain);
    LogService.log('MediaKitSettings', 'replayGain enabled=$v');
  }

  static Future<void> setReplayGainMode(String mode) async {
    replayGainMode.value = mode;
    await _saveString(_kRgMode, mode);
    if (replayGainEnabled.value) await _withNative(_applyReplayGain);
    LogService.log('MediaKitSettings', 'replayGain mode=$mode');
  }

  static Future<void> setReplayGainPreamp(double db) async {
    final v = db.clamp(-15.0, 15.0);
    replayGainPreampDb.value = v;
    await _saveDouble(_kRgPreamp, v);
    if (replayGainEnabled.value) await _withNative(_applyReplayGain);
    LogService.log('MediaKitSettings', 'replayGain preamp=${v}dB');
  }

  static Future<void> setReplayGainClip(bool v) async {
    replayGainClip.value = v;
    await _saveBool(_kRgClip, v);
    if (replayGainEnabled.value) await _withNative(_applyReplayGain);
    LogService.log('MediaKitSettings', 'replayGain clip=$v');
  }

  static Future<void> setCacheEnabled(bool v) async {
    cacheEnabled.value = v;
    await _saveBool(_kCacheEnabled, v);
    await _withNative(_applyCache);
    LogService.log('MediaKitSettings', 'cache=$v');
  }

  static Future<void> setCacheReadahead(int secs) async {
    cacheReadaheadSecs.value = secs;
    await _saveInt(_kCacheSecs, secs);
    if (cacheEnabled.value) await _withNative(_applyCache);
    LogService.log('MediaKitSettings', 'cacheReadahead=${secs}s');
  }

  // ── Internal helpers ──────────────────────────────────────────────────────

  static Future<void> _withNative(
    Future<void> Function(dynamic) fn,
  ) async {
    if (kIsWeb) return;
    final player = _activePlayer;
    if (player == null) return;
    final p = player.platform;
    if (p is NativePlayer) await fn(p as dynamic);
  }

  // ── Persistence ───────────────────────────────────────────────────────────

  static Future<void> _saveBool(String key, bool v) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(key, v);
  }

  static Future<void> _saveString(String key, String v) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(key, v);
  }

  static Future<void> _saveDouble(String key, double v) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(key, v);
  }

  static Future<void> _saveInt(String key, int v) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(key, v);
  }
}
