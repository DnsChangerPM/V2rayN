/// Dashboard: connection state, active profile, traffic, quick actions.
library;

import 'package:flutter/material.dart' hide ConnectionState;
import 'package:provider/provider.dart';

import '../l10n/app_localizations.dart';
import '../models/connection.dart';
import '../state/connection_provider.dart';
import '../state/navigation_provider.dart';
import '../state/profile_provider.dart';
import '../utils/formatters.dart';
import '../widgets/connect_button.dart';
import '../widgets/stat_card.dart';
import '../widgets/status_dot.dart';

class DashboardScreen extends StatelessWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final connection = context.watch<ConnectionProvider>();
    final profiles = context.watch<ProfileProvider>();
    final active = connection.activeProfile;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _ConnectionCard(connection: connection),
          const SizedBox(height: 16),
          const ConnectButton(),
          if (connection.failureKey.isNotEmpty) ...[
            const SizedBox(height: 12),
            _FailureBanner(messageKey: connection.failureKey),
          ],
          const SizedBox(height: 16),
          _ProfilePicker(
            profiles: profiles,
            activeId: active?.id,
          ),
          const SizedBox(height: 16),
          _StatsGrid(connection: connection),
        ],
      ),
    );
  }
}

class _ConnectionCard extends StatelessWidget {
  const _ConnectionCard({required this.connection});

  final ConnectionProvider connection;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final (severity, stateKey) = switch (connection.state) {
      ConnectionState.connected => (StatusSeverity.ok, 'connected'),
      ConnectionState.connecting => (StatusSeverity.busy, 'connecting'),
      ConnectionState.disconnecting =>
        (StatusSeverity.busy, 'disconnecting'),
      ConnectionState.error => (StatusSeverity.error, 'connectionError'),
      ConnectionState.disconnected =>
        (StatusSeverity.idle, 'disconnected'),
    };
    final coreKey = switch (connection.coreStatus) {
      CoreStatus.running => 'coreRunning',
      CoreStatus.starting => 'coreStarting',
      CoreStatus.stopping => 'coreStopping',
      CoreStatus.crashed => 'coreCrashed',
      CoreStatus.error => 'coreError',
      CoreStatus.stopped => 'coreStopped',
    };
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            Row(
              children: [
                StatusDot(severity: severity, size: 14),
                const SizedBox(width: 12),
                Text(
                  context.l10n(stateKey),
                  style: theme.textTheme.headlineSmall,
                ),
                const Spacer(),
                Text(
                  '${context.l10n('coreVersion')}: '
                  '${connection.coreVersion.isEmpty ? context.l10n('unknown') : connection.coreVersion}',
                  style: theme.textTheme.bodySmall,
                  textDirection: TextDirection.ltr,
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Text(
                  '${context.l10n('statusCore')}: ${context.l10n(coreKey)}',
                  style: theme.textTheme.bodyMedium,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _FailureBanner extends StatelessWidget {
  const _FailureBanner({required this.messageKey});

  final String messageKey;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      color: theme.colorScheme.errorContainer,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Icon(Icons.error_outline, color: theme.colorScheme.error),
            const SizedBox(width: 8),
            Expanded(child: Text(context.l10n(messageKey))),
          ],
        ),
      ),
    );
  }
}

class _ProfilePicker extends StatelessWidget {
  const _ProfilePicker({required this.profiles, this.activeId});

  final ProfileProvider profiles;
  final String? activeId;

  @override
  Widget build(BuildContext context) {
    final all = profiles.all;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              context.l10n('currentProfile'),
              style: Theme.of(context).textTheme.labelMedium,
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<String>(
                    value: activeId != null && activeId!.isNotEmpty
                        ? activeId
                        : null,
                    hint: Text(context.l10n('noProfileSelected')),
                    items: [
                      for (final profile in all)
                        DropdownMenuItem(
                          value: profile.id,
                          child: Text(
                            '${profile.name} (${profile.protocol.name})',
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                    ],
                    onChanged: (id) {
                      if (id != null) profiles.selectProfile(id);
                    },
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  tooltip: context.l10n('navProfiles'),
                  icon: const Icon(Icons.arrow_forward),
                  onPressed: () => context
                      .read<NavigationProvider>()
                      .go(AppPages.profiles),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _StatsGrid extends StatelessWidget {
  const _StatsGrid({required this.connection});

  final ConnectionProvider connection;

  @override
  Widget build(BuildContext context) {
    final traffic = connection.traffic;
    final active = connection.activeProfile;
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth > 900 ? 4 : 2;
        final cards = [
          StatCard(
            label: context.l10n('latency'),
            value: formatLatency(active?.lastLatencyMs),
            icon: Icons.timer_outlined,
          ),
          StatCard(
            label: '${context.l10n('download')} (${formatSpeed(traffic.downloadSpeedBps)})',
            value: formatBytes(traffic.downloadBytes),
            icon: Icons.download_outlined,
          ),
          StatCard(
            label: '${context.l10n('upload')} (${formatSpeed(traffic.uploadSpeedBps)})',
            value: formatBytes(traffic.uploadBytes),
            icon: Icons.upload_outlined,
          ),
          StatCard(
            label: context.l10n('uptime'),
            value: formatUptime(traffic.uptimeSeconds),
            icon: Icons.schedule_outlined,
          ),
        ];
        return GridView.count(
          crossAxisCount: columns,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 12,
          crossAxisSpacing: 12,
          childAspectRatio: 1.8,
          children: cards,
        );
      },
    );
  }
}
