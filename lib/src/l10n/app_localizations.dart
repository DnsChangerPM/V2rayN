/// Localization lookup + delegate (hand-written, no codegen).
///
/// Usage in widgets: `context.l10n('navDashboard')`.
/// Non-widget code receives the localized string from the caller; services
/// only produce stable message keys.
library;

import 'package:flutter/material.dart';

import 'strings.dart';

class AppLocalizations {
  const AppLocalizations(this.locale);

  final Locale locale;

  static const List<Locale> supportedLocales = [
    Locale('en'),
    Locale('fa'),
  ];

  static AppLocalizations of(BuildContext context) {
    final localizations =
        Localizations.of<AppLocalizations>(context, AppLocalizations);
    return localizations ?? const AppLocalizations(Locale('en'));
  }

  bool get isRtl => locale.languageCode == 'fa';

  /// Localized text for [key]. Falls back to English, then to the key itself.
  String get(String key) {
    if (locale.languageCode == 'fa') {
      final fa = Strings.fa[key];
      if (fa != null) return fa;
    }
    return Strings.en[key] ?? key;
  }

  String operator [](String key) => get(key);
}

extension L10nContext on BuildContext {
  AppLocalizations get l10nInstance => AppLocalizations.of(this);

  /// Shorthand: `context.l10n('connect')`.
  String l10n(String key) => AppLocalizations.of(this).get(key);
}

class AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const AppLocalizationsDelegate();

  @override
  bool isSupported(Locale locale) =>
      ['en', 'fa'].contains(locale.languageCode);

  @override
  Future<AppLocalizations> load(Locale locale) async =>
      AppLocalizations(locale);

  @override
  bool shouldReload(AppLocalizationsDelegate old) => false;
}

/// Resolve the effective locale from settings + device locale.
Locale resolveLocale(String languageCode, Locale deviceLocale) {
  switch (languageCode) {
    case 'english':
      return const Locale('en');
    case 'persian':
      return const Locale('fa');
    default:
      return deviceLocale.languageCode == 'fa'
          ? const Locale('fa')
          : const Locale('en');
  }
}
