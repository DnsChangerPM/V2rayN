/// Sidebar navigation state (also driven by the tray menu).
library;

import 'package:flutter/foundation.dart';

class NavigationProvider extends ChangeNotifier {
  int _index = 0;
  int get index => _index;

  void go(int index) {
    if (_index == index) return;
    _index = index;
    notifyListeners();
  }
}

/// Page indices in [AppShell] (kept in sync with the rail destinations).
abstract final class AppPages {
  static const int dashboard = 0;
  static const int profiles = 1;
  static const int subscriptions = 2;
  static const int speedTest = 3;
  static const int diagnostics = 4;
  static const int logs = 5;
  static const int settings = 6;
  static const int about = 7;
}

/// Shared instance so headless entry points (tray) can navigate.
final NavigationProvider globalNavigation = NavigationProvider();
