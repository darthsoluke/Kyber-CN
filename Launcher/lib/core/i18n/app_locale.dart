import 'dart:ui';

import 'package:jiffy/jiffy.dart' hide Locale;
import 'package:kyber_launcher/core/config/locales.dart';
import 'package:kyber_launcher/core/services/app_settings.dart';
import 'package:logging/logging.dart';

class AppLocale {
  AppLocale._();

  static Locale getLocale() {
    try {
      return Locales.resolve(Preferences.general.locale);
    } catch (e, s) {
      Logger.root.severe('Failed to get locale', e, s);
      return Locales.fallbackLocale;
    }
  }

  static Future<void> setLocale(Locale locale) async {
    final normalized = Locales.normalizeLanguageCode(locale.languageCode);
    try {
      await Jiffy.setLocale(normalized == 'zh' ? 'zh_cn' : normalized);
    } catch (e, s) {
      Logger.root.warning('Failed to set Jiffy locale', e, s);
    }
    Preferences.general.locale = normalized;
  }
}
