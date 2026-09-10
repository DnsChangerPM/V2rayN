/// Speed test screen (user-triggered measurements only).
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n/app_localizations.dart';
import '../speedtest/speed_test.dart';
import '../state/connection_provider.dart';
import '../state/service_locator.dart';
import '../state/settings_provider.dart';
import '../utils/formatters.dart';
import '../widgets/stat_card.dart';

class SpeedTestScreen extends StatefulWidget {
  const SpeedTestScreen({super.key});

  @override
  State<SpeedTestScreen> createState() => _SpeedTestScreenState();
}

class _SpeedTestScreenState extends State<SpeedTestScreen> {
  bool _running = false;
  bool _includeThroughput = true;
  SpeedTestResult? _result;

  @override
  Widget build(BuildContext context) {
    final connection = context.watch<ConnectionProvider>();
    final profile = connection.activeProfile;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            context.l10n('speedTestTitle'),
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 8),
          Text(profile?.name ?? context.l10n('noProfileSelected')),
          const SizedBox(height: 16),
          SwitchListTile(
            title: Text(context.l10n('speedTestThroughput')),
            value: _includeThroughput,
            onChanged: _running
                ? null
                : (value) => setState(() => _includeThroughput = value),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: !connection.isConnected || _running || profile == null
                ? null
                : _run,
            icon: _running
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.speed),
            label: Text(context.l10n(
                _running ? 'speedTestRunning' : 'speedTestRun',),),
          ),
          if (!connection.isConnected) ...[
            const SizedBox(height: 8),
            Text(context.l10n('speedTestNotConnected')),
          ],
          if (_result != null) ...[
            const SizedBox(height: 16),
            _ResultGrid(result: _result!),
          ],
        ],
      ),
    );
  }

  Future<void> _run() async {
    final connection = context.read<ConnectionProvider>();
    final profile = connection.activeProfile;
    if (profile == null) return;
    setState(() {
      _running = true;
      _result = null;
    });
    try {
      final services = context.read<AppServices>();
      final settings = context.read<SettingsProvider>().settings;
      final result = await SpeedTestService(log: services.log).run(
        profile: profile,
        settings: settings,
        includeThroughput: _includeThroughput,
      );
      if (mounted) setState(() => _result = result);
    } finally {
      if (mounted) setState(() => _running = false);
    }
  }
}

class _ResultGrid extends StatelessWidget {
  const _ResultGrid({required this.result});

  final SpeedTestResult result;

  @override
  Widget build(BuildContext context) {
    String kbps(int? value) =>
        value == null ? '–' : '${formatBytes(value * 1024)}/s';
    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 12,
      crossAxisSpacing: 12,
      childAspectRatio: 2.2,
      children: [
        StatCard(
          label: context.l10n('speedTestPing'),
          value: formatLatency(result.serverPingMs),
          icon: Icons.timer_outlined,
        ),
        StatCard(
          label: context.l10n('speedTestChain'),
          value: formatLatency(result.chainLatencyMs),
          icon: Icons.route_outlined,
        ),
        StatCard(
          label: context.l10n('speedTestDownload'),
          value: kbps(result.downloadKbps),
          icon: Icons.download_outlined,
        ),
        StatCard(
          label: context.l10n('speedTestUpload'),
          value: kbps(result.uploadKbps),
          icon: Icons.upload_outlined,
        ),
      ],
    );
  }
}
