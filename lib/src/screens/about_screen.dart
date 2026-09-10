/// About: version, core, links, update check.
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/app_version.dart';
import '../l10n/app_localizations.dart';
import '../state/connection_provider.dart';
import '../state/service_locator.dart';
import '../update/update_service.dart';
import '../widgets/section_header.dart';

class AboutScreen extends StatefulWidget {
  const AboutScreen({super.key});

  @override
  State<AboutScreen> createState() => _AboutScreenState();
}

class _AboutScreenState extends State<AboutScreen> {
  UpdateInfo? _update;
  bool _checking = false;
  bool _checkedOnce = false;

  Future<void> _check() async {
    setState(() {
      _checking = true;
    });
    try {
      final info =
          await context.read<AppServices>().updates.checkForUpdates();
      if (mounted) {
        setState(() {
          _update = info;
          _checkedOnce = true;
        });
      }
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final coreVersion = context.watch<ConnectionProvider>().coreVersion;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Image.asset(
                'assets/images/app_icon_master.png',
                width: 64,
                height: 64,
                errorBuilder: (_, _, _) =>
                    const Icon(Icons.link, size: 64),
              ),
              const SizedBox(width: 16),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    context.l10n('appName'),
                    style: theme.textTheme.headlineMedium,
                  ),
                  SelectableText(
                    '${context.l10n('aboutVersion')}: $kAppVersion',
                    textDirection: TextDirection.ltr,
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(context.l10n('aboutDescription')),
          SectionHeader(title: context.l10n('sectionAboutUpdate')),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SelectableText(
                    '${context.l10n('coreVersion')}: '
                    '${coreVersion.isEmpty ? context.l10n('unknown') : 'Xray $coreVersion'}',
                    textDirection: TextDirection.ltr,
                  ),
                  const SizedBox(height: 8),
                  if (_checking) const LinearProgressIndicator(),
                  if (_checkedOnce && !_checking)
                    Text(
                      _update == null
                          ? context.l10n('updateCheckFailed')
                          : _update!.isAvailable
                              ? '${context.l10n('updateAvailable')}: ${_update!.latest}'
                              : context.l10n('upToDate'),
                    ),
                  const SizedBox(height: 8),
                  FilledButton.tonalIcon(
                    onPressed: _checking ? null : _check,
                    icon: const Icon(Icons.system_update),
                    label: Text(context.l10n('checkNow')),
                  ),
                ],
              ),
            ),
          ),
          SectionHeader(title: context.l10n('aboutTitle')),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SelectableText(
                    'https://github.com/DnsChangerPM/V2rayN',
                    textDirection: TextDirection.ltr,
                  ),
                  const SizedBox(height: 4),
                  Text(context.l10n('aboutLicense')),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
