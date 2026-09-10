/// Diagnostics: environment report + connectivity checks + export.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../diagnostics/diagnostics.dart';
import '../l10n/app_localizations.dart';
import '../state/service_locator.dart';
import '../state/settings_provider.dart';
import '../widgets/section_header.dart';

class DiagnosticsScreen extends StatefulWidget {
  const DiagnosticsScreen({super.key});

  @override
  State<DiagnosticsScreen> createState() => _DiagnosticsScreenState();
}

class _DiagnosticsScreenState extends State<DiagnosticsScreen> {
  DiagnosticsReport? _report;
  bool _loading = false;

  Future<void> _collect(bool runProbes) async {
    setState(() => _loading = true);
    try {
      final services = context.read<AppServices>();
      final settings = context.read<SettingsProvider>().settings;
      final report =
          await services.diagnostics.collect(settings, runProbes: runProbes);
      if (mounted) setState(() => _report = report);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final report = _report;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Text(
                context.l10n('diagnosticsTitle'),
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const Spacer(),
              FilledButton.tonalIcon(
                onPressed: _loading ? null : () => _collect(true),
                icon: const Icon(Icons.play_arrow),
                label: Text(context.l10n('diagnosticsRun')),
              ),
              const SizedBox(width: 8),
              FilledButton.icon(
                onPressed: report == null ? null : () => _export(report),
                icon: const Icon(Icons.save_alt),
                label: Text(context.l10n('diagnosticsExport')),
              ),
            ],
          ),
          if (_loading) ...[
            const SizedBox(height: 16),
            const LinearProgressIndicator(),
          ],
          if (report != null) ...[
            SectionHeader(title: context.l10n('osVersion')),
            _InfoCard(rows: {
              context.l10n('osVersion'): report.os,
              context.l10n('coreVersion'):
                  '${report.coreVersion} (${report.coreStatus.name})',
              context.l10n('vaultBackend'): report.vaultBackend,
              context.l10n('portableMode'): report.portableMode ? '✓' : '–',
              context.l10n('tunState'): report.tunAvailable
                  ? '✓'
                  : context.l10n(report.tunReason),
              context.l10n('systemProxyState'): report.systemProxy == null
                  ? context.l10n('unknown')
                  : '${report.systemProxy!.enabled ? context.l10n('connected') : context.l10n('disconnected')}'
                      ' ${report.systemProxy!.server}',
            },),
            SectionHeader(title: context.l10n('localPorts')),
            _InfoCard(rows: {
              for (final port in report.ports)
                '${port.label} ${port.port}': port.free
                    ? context.l10n('portFree')
                    : '${context.l10n('portBusy')} (pid=${port.ownerPid ?? '?'})',
            },),
            SectionHeader(title: context.l10n('localAddresses')),
            _InfoCard(rows: {
              for (var i = 0; i < report.localAddresses.length; i++)
                '#$i': report.localAddresses[i],
            },),
            if (report.probes.isNotEmpty) ...[
              SectionHeader(title: context.l10n('connectivityChecks')),
              _InfoCard(rows: {
                for (final probe in report.probes)
                  probe.name:
                      '${probe.success ? 'OK' : 'FAIL'}${probe.latencyMs == null ? '' : ' ${probe.latencyMs}ms'}${probe.detail.isEmpty ? '' : ' (${probe.detail})'}',
              },),
            ],
          ],
        ],
      ),
    );
  }

  Future<void> _export(DiagnosticsReport report) async {
    try {
      final path = await FilePicker.platform.saveFile(
        dialogTitle: context.l10n('diagnosticsExport'),
        fileName: 'iranlink-diagnostics.md',
        type: FileType.custom,
        allowedExtensions: ['md'],
        bytes: Uint8List.fromList(utf8.encode(report.toMarkdown())),
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(context.l10n(
              path == null ? 'cancel' : 'diagnosticsExported',),),
        ),
      );
    } on Object {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l10n('connectionError'))),
      );
    }
  }
}

class _InfoCard extends StatelessWidget {
  const _InfoCard({required this.rows});

  final Map<String, String> rows;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            for (final entry in rows.entries)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: 220,
                      child: Text(
                        entry.key,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                    Expanded(
                      child: SelectableText(
                        entry.value,
                        textDirection: TextDirection.ltr,
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}
