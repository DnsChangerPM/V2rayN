/// Application shell: sidebar navigation + pages + status bar.
library;

import 'package:flutter/material.dart' hide ConnectionState;
import 'package:provider/provider.dart';

import '../l10n/app_localizations.dart';
import '../models/connection.dart';
import '../state/connection_provider.dart';
import '../state/navigation_provider.dart';
import '../widgets/status_dot.dart';
import 'about_screen.dart';
import 'dashboard_screen.dart';
import 'diagnostics_screen.dart';
import 'logs_screen.dart';
import 'profiles_screen.dart';
import 'settings_screen.dart';
import 'speed_test_screen.dart';
import 'subscriptions_screen.dart';

class AppShell extends StatelessWidget {
  const AppShell({super.key});

  static const _pages = [
    DashboardScreen(),
    ProfilesScreen(),
    SubscriptionsScreen(),
    SpeedTestScreen(),
    DiagnosticsScreen(),
    LogsScreen(),
    SettingsScreen(),
    AboutScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    final navigation = context.watch<NavigationProvider>();
    final destinations = [
      (Icons.dashboard_outlined, Icons.dashboard, 'navDashboard'),
      (Icons.list_alt_outlined, Icons.list_alt, 'navProfiles'),
      (Icons.rss_feed_outlined, Icons.rss_feed, 'navSubscriptions'),
      (Icons.speed_outlined, Icons.speed, 'navSpeedTest'),
      (Icons.monitor_heart_outlined, Icons.monitor_heart, 'navDiagnostics'),
      (Icons.terminal_outlined, Icons.terminal, 'navLogs'),
      (Icons.settings_outlined, Icons.settings, 'navSettings'),
      (Icons.info_outlined, Icons.info, 'navAbout'),
    ];
    return Scaffold(
      body: Row(
        children: [
          NavigationRail(
            selectedIndex: navigation.index,
            onDestinationSelected: navigation.go,
            labelType: NavigationRailLabelType.all,
            leading: Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Column(
                children: [
                  Image.asset(
                    'assets/images/app_icon_master.png',
                    width: 40,
                    height: 40,
                    errorBuilder: (_, _, _) => const Icon(
                      Icons.link,
                      size: 40,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    context.l10n('appName'),
                    style: Theme.of(context).textTheme.labelSmall,
                  ),
                ],
              ),
            ),
            destinations: [
              for (final destination in destinations)
                NavigationRailDestination(
                  icon: Icon(destination.$1),
                  selectedIcon: Icon(destination.$2),
                  label: Text(context.l10n(destination.$3)),
                ),
            ],
          ),
          const VerticalDivider(thickness: 1, width: 1),
          Expanded(
            child: Column(
              children: [
                Expanded(child: _pages[navigation.index]),
                const _StatusBar(),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _StatusBar extends StatelessWidget {
  const _StatusBar();

  @override
  Widget build(BuildContext context) {
    final connection = context.watch<ConnectionProvider>();
    final theme = Theme.of(context);
    final (severity, labelKey) = switch (connection.state) {
      ConnectionState.connected => (StatusSeverity.ok, 'connected'),
      ConnectionState.connecting => (StatusSeverity.busy, 'connecting'),
      ConnectionState.disconnecting =>
        (StatusSeverity.busy, 'disconnecting'),
      ConnectionState.error => (StatusSeverity.error, 'connectionError'),
      ConnectionState.disconnected =>
        (StatusSeverity.idle, 'disconnected'),
    };
    final profile = connection.activeProfile;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: theme.dividerColor)),
        // ignore: deprecated_member_use (withOpacity is correct on Flutter 3.19)
        color: theme.colorScheme.surfaceContainerHighest.withOpacity(0.4),
      ),
      child: Row(
        children: [
          StatusDot(severity: severity),
          const SizedBox(width: 8),
          Text(context.l10n(labelKey), style: theme.textTheme.labelMedium),
          const SizedBox(width: 16),
          Expanded(
            child: Text(
              profile?.name ?? context.l10n('noProfileSelected'),
              style: theme.textTheme.labelMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (connection.failureKey.isNotEmpty)
            Flexible(
              child: Text(
                context.l10n(connection.failureKey),
                style: theme.textTheme.labelMedium?.copyWith(
                  color: theme.colorScheme.error,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
        ],
      ),
    );
  }
}
