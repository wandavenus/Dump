import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class UpNextSettings {
  UpNextSettings._();

  static const _kShowUpNextCard = 'up_next_card_enabled';

  static final ValueNotifier<bool> showUpNextCard = ValueNotifier(true);

  static Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    showUpNextCard.value = prefs.getBool(_kShowUpNextCard) ?? true;
  }

  static Future<void> setShowUpNextCard(bool value) async {
    showUpNextCard.value = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kShowUpNextCard, value);
  }
}
