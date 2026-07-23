import 'package:flutter/material.dart';

import '../themes/app_theme_extension.dart';

/// Convenience accessor for [AppThemeExtension] semantic colors.
///
/// ```dart
/// final c = AppColors.of(context);
/// Container(color: c.surface, child: Text('Hello', style: TextStyle(color: c.primaryLabel)));
/// ```
class AppColors {
  const AppColors._();

  /// Returns the [AppThemeExtension] registered in the nearest [Theme].
  ///
  /// Throws if [AppThemeExtension] is not present — which should never happen
  /// as long as [AppThemes.light] / [AppThemes.dark] are used in [MaterialApp].
  static AppThemeExtension of(BuildContext context) =>
      Theme.of(context).extension<AppThemeExtension>()!;
}
