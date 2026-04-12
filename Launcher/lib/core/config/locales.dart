import 'dart:ui';

class Locales {
  Locales._();

  static const Locale fallbackLocale = Locale('en');
  static const List<String> supportedLocales = ['en', 'zh'];
  static const List<String> supportedLocaleCodes = supportedLocales;
  static const List<Locale> supportedLanguages = [
    Locale('en'),
    Locale.fromSubtags(languageCode: 'zh', countryCode: 'CN'),
  ];

  static String normalizeLanguageCode(String value) {
    final normalized = value.replaceAll('-', '_').toLowerCase();
    if (normalized.startsWith('zh')) {
      return 'zh';
    }
    return supportedLocaleCodes.contains(normalized)
        ? normalized
        : fallbackLocale.languageCode;
  }

  static Locale resolve(String? value) {
    final code = normalizeLanguageCode(value ?? fallbackLocale.languageCode);
    return supportedLanguages.firstWhere(
      (locale) => locale.languageCode == code,
      orElse: () => fallbackLocale,
    );
  }

  static String nativeName(Locale locale) {
    switch (normalizeLanguageCode(locale.languageCode)) {
      case 'zh':
        return '简体中文';
      case 'en':
      default:
        return 'English';
    }
  }
}
