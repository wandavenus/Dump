import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class WatermarkService {
  WatermarkService._();

  // ── Konfigurasi ─────────────────────────────────────────────────────────────
  // Ubah dua konstanta di bawah ini untuk mengatur teks dan status awal WM.

  /// Teks yang ditampilkan sebagai watermark.
  static const String text = 'IG : Wndavenznchole';

  /// Default visibility saat fresh install (true = muncul, false = tersembunyi).
  static const bool defaultVisible = true;

  // ── Internal ─────────────────────────────────────────────────────────────────
  static const _kKey = 'watermark_visible';

  static final ValueNotifier<bool> visible = ValueNotifier(defaultVisible);

  static Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    visible.value = prefs.getBool(_kKey) ?? defaultVisible;
  }

  static Future<void> setVisible(bool value) async {
    visible.value = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kKey, value);
  }
}
