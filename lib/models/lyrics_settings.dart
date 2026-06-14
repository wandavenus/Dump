import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Pengaturan tampilan halaman lirik — disimpan ke SharedPreferences.
class LyricsSettings {
  LyricsSettings._();

  // ── Value notifiers ─────────────────────────────────────────────────────────

  /// Ukuran font teks lirik aktif (14 / 18 / 22 / 26).
  static final ValueNotifier<double> fontSize = ValueNotifier(22.0);

  /// Rata teks: 'left' / 'center' / 'right'.
  static final ValueNotifier<String> textAlign = ValueNotifier('left');

  /// Opasitas overlay gelap di atas latar blur (0.0 = transparan, 1.0 = hitam penuh).
  static final ValueNotifier<double> bgDim = ValueNotifier(0.55);

  /// Kekuatan blur latar (0 = tanpa blur, 40 = sangat buram).
  static final ValueNotifier<double> blurStrength = ValueNotifier(28.0);

  /// Warna teks aktif: 'white' / 'accent' / 'yellow'.
  static final ValueNotifier<String> activeColor = ValueNotifier('white');

  /// Tampilkan lencana sumber lirik (Dari Internet / Dari File / Dari Tag).
  static final ValueNotifier<bool> showSource = ValueNotifier(true);

  /// Aktifkan animasi karaoke (highlight kata per kata — hanya jika data tersedia).
  static final ValueNotifier<bool> karaokeMode = ValueNotifier(false);

  // ── Init ────────────────────────────────────────────────────────────────────

  static Future<void> init() async {
    final p = await SharedPreferences.getInstance();
    fontSize.value     = p.getDouble('lyr_fontSize')    ?? 22.0;
    textAlign.value    = p.getString('lyr_textAlign')   ?? 'left';
    bgDim.value        = p.getDouble('lyr_bgDim')       ?? 0.55;
    blurStrength.value = p.getDouble('lyr_blur')        ?? 28.0;
    activeColor.value  = p.getString('lyr_activeColor') ?? 'white';
    showSource.value   = p.getBool('lyr_showSource')    ?? true;
    karaokeMode.value  = p.getBool('lyr_karaoke')       ?? false;
  }

  // ── Setters ─────────────────────────────────────────────────────────────────

  static Future<void> setFontSize(double v) async {
    fontSize.value = v;
    (await SharedPreferences.getInstance()).setDouble('lyr_fontSize', v);
  }

  static Future<void> setTextAlign(String v) async {
    textAlign.value = v;
    (await SharedPreferences.getInstance()).setString('lyr_textAlign', v);
  }

  static Future<void> setBgDim(double v) async {
    bgDim.value = v;
    (await SharedPreferences.getInstance()).setDouble('lyr_bgDim', v);
  }

  static Future<void> setBlurStrength(double v) async {
    blurStrength.value = v;
    (await SharedPreferences.getInstance()).setDouble('lyr_blur', v);
  }

  static Future<void> setActiveColor(String v) async {
    activeColor.value = v;
    (await SharedPreferences.getInstance()).setString('lyr_activeColor', v);
  }

  static Future<void> setShowSource(bool v) async {
    showSource.value = v;
    (await SharedPreferences.getInstance()).setBool('lyr_showSource', v);
  }

  static Future<void> setKaraokeMode(bool v) async {
    karaokeMode.value = v;
    (await SharedPreferences.getInstance()).setBool('lyr_karaoke', v);
  }

  // ── Helpers ─────────────────────────────────────────────────────────────────

  static TextAlign get resolvedTextAlign {
    switch (textAlign.value) {
      case 'center': return TextAlign.center;
      case 'right':  return TextAlign.right;
      default:       return TextAlign.left;
    }
  }

  static Color get resolvedActiveColor {
    switch (activeColor.value) {
      case 'accent': return const Color(0xFFF92D48);
      case 'yellow': return const Color(0xFFFFD60A);
      default:       return Colors.white;
    }
  }
}
