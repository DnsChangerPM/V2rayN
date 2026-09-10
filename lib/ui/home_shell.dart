import 'package:flutter/material.dart';

import '../core/app_controller.dart';
import '../core/model/enums.dart';
import '../core/process/stats_client.dart';
import '../l10n/strings.dart';
import '../utils/app_version.dart';
import 'pages/about_page.dart';
import 'pages/logs_page.dart';
import 'pages/servers_page.dart';
import 'pages/settings_page.dart';

/// Main window: a header with the connection status plus a navigation rail.
class HomeShell extends StatefulWidget {
  const HomeShell({super.key, required this.controller});

  final AppController controller;

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    final strings = Strings.of(Localizations.localeOf(context));
    final controller = widget.controller;

    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        return Scaffold(
          body: Column(
            children: <Widget>[
              _Header(controller: controller),
              const Divider(height: 1),
              Expanded(
                child: Row(
                  textDirection: TextDirection.ltr,
                  children: <Widget>[
                    NavigationRail(
                      selectedIndex: _index,
                      extended: false,
                      minExtendedWidth: 180,
                      onDestinationSelected: (value) =>
                          setState(() => _index = value),
                      labelType: NavigationRailLabelType.selected,
                      destinations: <NavigationRailDestination>[
                        NavigationRailDestination(
                          icon: const Icon(Icons.dns_outlined),
                          selectedIcon: const Icon(Icons.dns),
                          label: Text(strings.servers),
                        ),
                        NavigationRailDestination(
                          icon: const Icon(Icons.tune_outlined),
                          selectedIcon: const Icon(Icons.tune),
                          label: Text(strings.settings),
                        ),
                        NavigationRailDestination(
                          icon: const Icon(Icons.article_outlined),
                          selectedIcon: const Icon(Icons.article),
                          label: Text(strings.logs),
                        ),
                        NavigationRailDestination(
                          icon: const Icon(Icons.info_outline),
                          selectedIcon: const Icon(Icons.info),
                          label: Text(strings.about),
                        ),
                      ],
                    ),
                    const VerticalDivider(width: 1),
                    Expanded(
                      child: switch (_index) {
                        0 => ServersPage(controller: controller),
                        1 => SettingsPage(controller: controller),
                        2 => LogsPage(controller: controller),
                        _ => AboutPage(controller: controller),
                      },
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    final strings = Strings.of(Localizations.localeOf(context));
    final theme = Theme.of(context);
    final state = controller.connectionState;
    final connected = state == ConnectionState.connected;
    final busy = state.isBusy;

    final Color accent;
    final String statusText;
    switch (state) {
      case ConnectionState.connected:
        accent = Colors.green;
        statusText = connected
            ? '${strings.connectedTo}: ${controller.activeProfile?.displayName ?? ''}'
            : strings.statusRunning;
        break;
      case ConnectionState.connecting:
        accent = Colors.amber;
        statusText = strings.connecting;
        break;
      case ConnectionState.disconnecting:
        accent = Colors.amber;
        statusText = strings.disconnecting;
        break;
      case ConnectionState.failed:
        accent = Colors.red;
        statusText = controller.errorMessage ?? strings.connectionFailed;
        break;
      case ConnectionState.disconnected:
        accent = theme.colorScheme.outline;
        statusText = strings.statusStopped;
        break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      child: Row(
        children: <Widget>[
          Container(
            width: 12,
            height: 12,
            decoration: BoxDecoration(color: accent, shape: BoxShape.circle),
          ),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Text(
                '${AppVersion.name} ${AppVersion.version}',
                style: theme.textTheme.titleMedium,
              ),
              const SizedBox(height: 2),
              SizedBox(
                width: 420,
                child: Text(
                  statusText,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(color: accent),
                ),
              ),
            ],
          ),
          const SizedBox(width: 16),
          _TrafficChip(controller: controller),
          const Spacer(),
          FilledButton.icon(
            onPressed: busy ? null : () => controller.toggleConnection(),
            icon: Icon(connected ? Icons.stop_rounded : Icons.play_arrow_rounded),
            label: Text(busy
                ? (connected ? strings.disconnecting : strings.connecting)
                : (connected ? strings.disconnect : strings.connect)),
          ),
        ],
      ),
    );
  }
}

class _TrafficChip extends StatelessWidget {
  const _TrafficChip({required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    final strings = Strings.of(Localizations.localeOf(context));
    if (!controller.isConnected) {
      return const SizedBox.shrink();
    }
    final traffic = controller.traffic;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          const Icon(Icons.arrow_upward_rounded, size: 14),
          const SizedBox(width: 4),
          Text(StatsClient.formatBytes(traffic.uplink)),
          const SizedBox(width: 12),
          const Icon(Icons.arrow_downward_rounded, size: 14),
          const SizedBox(width: 4),
          Text(StatsClient.formatBytes(traffic.downlink)),
          const SizedBox(width: 8),
          Text('(${strings.traffic})'),
        ],
      ),
    );
  }
}
