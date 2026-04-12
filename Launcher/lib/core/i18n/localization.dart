import 'package:flutter/widgets.dart';
import 'package:kyber_launcher/core/i18n/app_localizations.dart';

class Localization {
  Localization._();

  static AppLocalizations get current => AppLocalizations.current;
}

extension LocalizationBuildContextX on BuildContext {
  AppLocalizations get l10n => AppLocalizations.of(this);
}
