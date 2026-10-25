import 'package:flutter_test/flutter_test.dart';
import 'package:musicplayer/themes/theme_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('ThemeController Liquid Glass settings', () {
    test('fresh install defaults to Bawaan and a collapsed section', () async {
      await ThemeController.init();

      expect(ThemeController.navBarStyle.value, NavBarStyle.solid);
      expect(ThemeController.glassTheme.value, isFalse);
      expect(ThemeController.liquidGlassSectionExpanded.value, isFalse);
    });

    test('Glass and Floating Pill do not change the section expansion state',
        () async {
      await ThemeController.init();

      await ThemeController.setNavBarStyle(NavBarStyle.glass);
      expect(ThemeController.liquidGlassSectionExpanded.value, isFalse);

      await ThemeController.setNavBarStyle(NavBarStyle.pill);
      expect(ThemeController.liquidGlassSectionExpanded.value, isFalse);

      await ThemeController.init();
      expect(ThemeController.navBarStyle.value, NavBarStyle.pill);
      expect(ThemeController.liquidGlassSectionExpanded.value, isFalse);
    });

    test('persists section expanded and collapsed state independently',
        () async {
      await ThemeController.init();
      await ThemeController.setNavBarStyle(NavBarStyle.glass);

      await ThemeController.setLiquidGlassSectionExpanded(false);
      await ThemeController.init();
      expect(ThemeController.navBarStyle.value, NavBarStyle.glass);
      expect(ThemeController.liquidGlassSectionExpanded.value, isFalse);

      await ThemeController.setLiquidGlassSectionExpanded(true);
      await ThemeController.init();
      expect(ThemeController.navBarStyle.value, NavBarStyle.glass);
      expect(ThemeController.liquidGlassSectionExpanded.value, isTrue);
    });
  });

  group('ThemeController player background style', () {
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
