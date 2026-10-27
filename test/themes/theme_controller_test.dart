import 'package:flutter_test/flutter_test.dart';
import 'package:musicplayer/themes/theme_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('ThemeController navbar styles', () {
    test('fresh install defaults to Default and a collapsed section', () async {
      await ThemeController.init();

      expect(ThemeController.navBarStyle.value, NavBarStyle.solid);
      expect(ThemeController.glassTheme.value, isFalse);
      expect(ThemeController.liquidGlassSectionExpanded.value, isFalse);
    });

    test('persists Default and Floating Pill without shifting stored values',
        () async {
      await ThemeController.init();
      await ThemeController.setNavBarStyle(NavBarStyle.pill);
      expect(ThemeController.liquidGlassSectionExpanded.value, isFalse);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getInt('navbar_style'), 2);

      await ThemeController.init();
      expect(ThemeController.navBarStyle.value, NavBarStyle.pill);

      await ThemeController.setNavBarStyle(NavBarStyle.solid);
      expect(prefs.getInt('navbar_style'), 0);
      await ThemeController.init();
      expect(ThemeController.navBarStyle.value, NavBarStyle.solid);
    });

    test('migrates a saved legacy Glass selection to Default', () async {
      SharedPreferences.setMockInitialValues({
        'navbar_style': 1,
        'glass_theme': false,
      });
      await ThemeController.init();

      expect(ThemeController.navBarStyle.value, NavBarStyle.solid);
      expect(ThemeController.glassTheme.value, isFalse);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getInt('navbar_style'), 0);
    });

    test('preserves a previously saved Floating Pill selection', () async {
      SharedPreferences.setMockInitialValues({
        'navbar_style': 2,
        'glass_theme': false,
      });
      await ThemeController.init();

      expect(ThemeController.navBarStyle.value, NavBarStyle.pill);
      expect(ThemeController.glassTheme.value, isTrue);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getInt('navbar_style'), 2);
    });

    test('legacy glass_navbar flag falls back to Default', () async {
      SharedPreferences.setMockInitialValues({'glass_navbar': true});
      await ThemeController.init();

      expect(ThemeController.navBarStyle.value, NavBarStyle.solid);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getInt('navbar_style'), 0);
      expect(prefs.getBool('glass_navbar'), isNull);
    });

    test('section expanded state is independent of navbar selection',
        () async {
      await ThemeController.init();
      await ThemeController.setNavBarStyle(NavBarStyle.pill);
      await ThemeController.setLiquidGlassSectionExpanded(true);
      await ThemeController.init();

      expect(ThemeController.navBarStyle.value, NavBarStyle.pill);
      expect(ThemeController.liquidGlassSectionExpanded.value, isTrue);

      await ThemeController.setLiquidGlassSectionExpanded(false);
      await ThemeController.init();
      expect(ThemeController.navBarStyle.value, NavBarStyle.pill);
      expect(ThemeController.liquidGlassSectionExpanded.value, isFalse);
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
