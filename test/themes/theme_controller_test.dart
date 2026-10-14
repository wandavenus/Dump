import 'package:flutter_test/flutter_test.dart';
import 'package:musicplayer/themes/theme_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('ThemeController player background style', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    test('defaults to the existing fluid background', () async {
      await ThemeController.init();

      expect(
        ThemeController.playerBackgroundStyle.value,
        PlayerBackgroundStyle.fluid,
      );
    });

    test('saves and restores the artwork blur selection', () async {
      await ThemeController.init();
      await ThemeController.setPlayerBackgroundStyle(
        PlayerBackgroundStyle.artworkBlur,
      );

      final prefs = await SharedPreferences.getInstance();
      expect(
        prefs.getInt('player_background_style'),
        PlayerBackgroundStyle.artworkBlur.index,
      );

      SharedPreferences.setMockInitialValues({
        'player_background_style': PlayerBackgroundStyle.artworkBlur.index,
      });
      await ThemeController.init();

      expect(
        ThemeController.playerBackgroundStyle.value,
        PlayerBackgroundStyle.artworkBlur,
      );
    });

    test('ignores an invalid stored style index', () async {
      SharedPreferences.setMockInitialValues({'player_background_style': 99});
      await ThemeController.init();

      expect(
        ThemeController.playerBackgroundStyle.value,
        PlayerBackgroundStyle.fluid,
      );
    });
  });
}
