/// IranLink root widget: providers, theme, locale, navigation shell.
library;

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';

import 'src/l10n/app_localizations.dart';
import 'src/models/settings.dart';
import 'src/screens/app_shell.dart';
import 'src/state/connection_provider.dart';
import 'src/state/log_provider.dart';
import 'src/state/navigation_provider.dart';
import 'src/state/profile_provider.dart';
import 'src/state/service_locator.dart';
import 'src/state/settings_provider.dart';
import 'src/state/subscription_provider.dart';
import 'src/theme/app_theme.dart';

class IranLinkApp extends StatelessWidget {
  const IranLinkApp({super.key, required this.services});

  final AppServices services;

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        Provider<AppServices>.value(value: services),
        ChangeNotifierProvider(
          create: (_) => SettingsProvider(
            repository: services.settings,
            autostart: services.autostart,
            log: services.log,
          ),
        ),
        ChangeNotifierProvider(
          create: (_) => ProfileProvider(
            repository: services.profiles,
            importer: services.importer,
            selector: services.selector,
            settings: services.settings,
          )..refresh(),
        ),
        ChangeNotifierProvider(
          create: (_) => SubscriptionProvider(manager: services.subscriptions),
        ),
        ChangeNotifierProvider(
          create: (_) => ConnectionProvider(
            core: services.core,
            systemProxy: services.systemProxy,
            settings: services.settings,
            profiles: services.profiles,
            log: services.log,
          ),
        ),
        ChangeNotifierProvider(
          create: (_) => LogProvider(log: services.log),
        ),
        ChangeNotifierProvider<NavigationProvider>.value(
            value: globalNavigation,),
      ],
      child: Consumer<SettingsProvider>(
        builder: (context, settingsProvider, _) {
          final settings = settingsProvider.settings;
          return MaterialApp(
            title: 'IranLink',
            debugShowCheckedModeBanner: false,
            theme: AppTheme.light(),
            darkTheme: AppTheme.dark(),
            themeMode: switch (settings.theme) {
              ThemeModeSetting.light => ThemeMode.light,
              ThemeModeSetting.dark => ThemeMode.dark,
              ThemeModeSetting.system => ThemeMode.system,
            },
            locale: resolveLocale(
              settings.locale.name,
              WidgetsBinding.instance.platformDispatcher.locale,
            ),
            supportedLocales: AppLocalizations.supportedLocales,
            localizationsDelegates: const [
              AppLocalizationsDelegate(),
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            home: const AppShell(),
          );
        },
      ),
    );
  }
}
