import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class WatermarkService {
  WatermarkService._();

  static const _kKey = 'watermark_visible';

  static final ValueNotifier<bool> visible = ValueNotifier(true);

  static Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    visible.value = prefs.getBool(_kKey) ?? true;
  }

  static Future<void> setVisible(bool value) async {
    visible.value = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kKey, value);
  }
}
