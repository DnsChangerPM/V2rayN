import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'core/app_controller.dart';
import 'core/model/enums.dart';
import 'l10n/strings.dart';
import 'ui/home_shell.dart';

/// Root widget.
class RadinApp extends StatelessWidget {
  const RadinApp({super.key, required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    return StringsScope(
      controller: controller,
      child: Builder(
        builder: (context) {
          final strings = StringsScope.stringsOf(context);
          final locale = switch (controller.settings.language) {
            AppLanguage.persian => const Locale('fa'),
            AppLanguage.english => const Locale('en'),
            AppLanguage.system => null,
          };

          return MaterialApp(
            title: strings.appTitle,
            debugShowCheckedModeBanner: false,
            locale: locale,
            supportedLocales: const <Locale>[Locale('fa'), Locale('en')],
            localizationsDelegates: const <LocalizationsDelegate<Object>>[
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            theme: _buildTheme(Brightness.light),
            darkTheme: _buildTheme(Brightness.dark),
            themeMode: switch (controller.settings.themeMode) {
              'light' => ThemeMode.light,
              'dark' => ThemeMode.dark,
              _ => ThemeMode.system,
            },
            home: HomeShell(controller: controller),
          );
        },
      ),
    );
  }

  static ThemeData _buildTheme(Brightness brightness) {
    const seed = Color(0xFF00B39F);
    final scheme = ColorScheme.fromSeed(
      seedColor: seed,
      brightness: brightness,
    );
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      snackBarTheme: const SnackBarThemeData(behavior: SnackBarBehavior.floating),
      cardTheme: const CardThemeData(margin: EdgeInsets.zero),
    );
  }
}

/// Makes the [Strings] instance and the [AppController] available to the tree.
class StringsScope extends InheritedWidget {
  const StringsScope({
    super.key,
    required this.controller,
    required super.child,
  });

  final AppController controller;

  static StringsScope of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<StringsScope>();
    assert(scope != null, 'StringsScope is missing from the widget tree');
    return scope!;
  }

  static Strings stringsOf(BuildContext context) {
    final locale = Localizations.localeOf(context);
    return Strings.of(locale);
  }

  @override
  bool updateShouldNotify(StringsScope oldWidget) =>
      oldWidget.controller != controller;
}
