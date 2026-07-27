import 'package:flutter/widgets.dart';
import 'package:musicplayer/l10n/app_localizations.dart';

extension LocalizationExtension on BuildContext {
  AppLocalizations get l10n => AppLocalizations.of(this)!;
}
