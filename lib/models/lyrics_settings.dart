import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Pengaturan tampilan halaman lirik — disimpan ke SharedPreferences.
class LyricsSettings {
  LyricsSettings._();

  // ── Value notifiers ─────────────────────────────────────────────────────────

  /// Ukuran font teks lirik aktif (14 / 18 / 22 / 26).
  static final ValueNotifier<double> fontSize = ValueNotifier(46.0);

  /// Jarak vertikal di atas dan di bawah setiap baris lirik dalam logical px.
  static final ValueNotifier<double> lineSpacing = ValueNotifier(20.0);

  /// Rata teks: 'left' / 'center' / 'right'.
  static final ValueNotifier<String> textAlign = ValueNotifier('left');

  /// Opasitas overlay gelap di atas latar blur (0.0 = transparan, 1.0 = hitam penuh).
  static final ValueNotifier<double> bgDim = ValueNotifier(0.0);

  /// Kekuatan blur latar (0 = tanpa blur, 40 = sangat buram).
  static final ValueNotifier<double> blurStrength = ValueNotifier(0.0);

  /// Warna teks aktif: 'white' / 'accent' / 'yellow'.
  static final ValueNotifier<String> activeColor = ValueNotifier('white');

  /// Tampilkan lencana sumber lirik (Dari Internet / Dari File / Dari Tag).
  static final ValueNotifier<bool> showSource = ValueNotifier(false);

  /// Aktifkan animasi karaoke (highlight kata per kata — hanya jika data tersedia).
  static final ValueNotifier<bool> karaokeMode = ValueNotifier(true);

  // ── Init ────────────────────────────────────────────────────────────────────

  static Future<void> init() async {
    final p = await SharedPreferences.getInstance();
    fontSize.value = p.getDouble('lyr_fontSize') ?? 46.0;
    lineSpacing.value = p.getDouble('lyr_lineSpacing') ?? 20.0;
    textAlign.value = p.getString('lyr_textAlign') ?? 'left';
    bgDim.value = p.getDouble('lyr_bgDim') ?? 0.0;
    blurStrength.value = p.getDouble('lyr_blur') ?? 0.0;
    activeColor.value = p.getString('lyr_activeColor') ?? 'white';
    showSource.value = p.getBool('lyr_showSource') ?? false;
    karaokeMode.value = p.getBool('lyr_karaoke') ?? true;
  }

  // ── Setters ─────────────────────────────────────────────────────────────────
  //
  // Persist ke SharedPreferences di-debounce 400ms per key: notifier di-update
  // langsung (UI tetap responsif real-time), tapi disk write hanya terjadi
  // setelah user berhenti menggeser/mengubah nilai sejenak. Mencegah I/O
  // storm saat slider di-drag terus-menerus.

  static final Map<String, Timer> _debounceTimers = {};
  static const _debounceDelay = Duration(milliseconds: 400);

  static void _persistDebounced(String key, Future<void> Function() write) {
    _debounceTimers[key]?.cancel();
    _debounceTimers[key] = Timer(_debounceDelay, () {
      _debounceTimers.remove(key);
      write().catchError((_) {
        /* SharedPreferences write failed — ignored */
      });
    });
  }

  /// Membatalkan semua debounce timer tertunda dan langsung menulis nilai
  /// saat ini ke disk. Panggil saat halaman ditutup / app dijeda agar
  /// perubahan terakhir tidak hilang.
  static Future<void> flush() async {
    final timers = _debounceTimers.values.toList();
    _debounceTimers.clear();
    for (final t in timers) {
      t.cancel();
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble('lyr_fontSize', fontSize.value);
    await prefs.setDouble('lyr_lineSpacing', lineSpacing.value);
    await prefs.setString('lyr_textAlign', textAlign.value);
    await prefs.setDouble('lyr_bgDim', bgDim.value);
    await prefs.setDouble('lyr_blur', blurStrength.value);
    await prefs.setString('lyr_activeColor', activeColor.value);
    await prefs.setBool('lyr_showSource', showSource.value);
    await prefs.setBool('lyr_karaoke', karaokeMode.value);
  }

  static void setFontSize(double v) {
    fontSize.value = v;
    _persistDebounced('lyr_fontSize', () async {
      await (await SharedPreferences.getInstance()).setDouble(
        'lyr_fontSize',
        v,
      );
    });
  }

  static void setLineSpacing(double v) {
    lineSpacing.value = v;
    _persistDebounced('lyr_lineSpacing', () async {
      await (await SharedPreferences.getInstance()).setDouble(
        'lyr_lineSpacing',
        v,
      );
    });
  }

  static void setTextAlign(String v) {
    textAlign.value = v;
    _persistDebounced('lyr_textAlign', () async {
      await (await SharedPreferences.getInstance()).setString(
        'lyr_textAlign',
        v,
      );
    });
  }

  static void setBgDim(double v) {
    bgDim.value = v;
    _persistDebounced('lyr_bgDim', () async {
      await (await SharedPreferences.getInstance()).setDouble('lyr_bgDim', v);
    });
  }

  static void setBlurStrength(double v) {
    blurStrength.value = v;
    _persistDebounced('lyr_blur', () async {
      await (await SharedPreferences.getInstance()).setDouble('lyr_blur', v);
    });
  }

  static void setActiveColor(String v) {
    activeColor.value = v;
    _persistDebounced('lyr_activeColor', () async {
      await (await SharedPreferences.getInstance()).setString(
        'lyr_activeColor',
        v,
      );
    });
  }

  static void setShowSource(bool v) {
    showSource.value = v;
    _persistDebounced('lyr_showSource', () async {
      await (await SharedPreferences.getInstance()).setBool(
        'lyr_showSource',
        v,
      );
    });
  }

  static void setKaraokeMode(bool v) {
    karaokeMode.value = v;
    _persistDebounced('lyr_karaoke', () async {
      await (await SharedPreferences.getInstance()).setBool('lyr_karaoke', v);
    });
  }

  // ── Helpers ─────────────────────────────────────────────────────────────────

  static TextAlign get resolvedTextAlign => switch (textAlign.value) {
    'center' => TextAlign.center,
    'right' => TextAlign.right,
    _ => TextAlign.left,
  };

  static Color get resolvedActiveColor => switch (activeColor.value) {
    'accent' => const Color(0xFFF92D48),
    'yellow' => const Color(0xFFFFD60A),
    _ => Colors.white,
  };
}
