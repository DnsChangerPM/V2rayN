/// Settings: general, proxy, routing, DNS, network, core, backup.
library;

import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n/app_localizations.dart';
import '../models/settings.dart';
import '../state/service_locator.dart';
import '../state/settings_provider.dart';
import '../widgets/section_header.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<SettingsProvider>();
    final settings = provider.settings;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            context.l10n('settingsTitle'),
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          SectionHeader(title: context.l10n('sectionGeneral')),
          _DropdownRow<ThemeModeSetting>(
            label: context.l10n('theme'),
            value: settings.theme,
            items: const [
              ThemeModeSetting.system,
              ThemeModeSetting.light,
              ThemeModeSetting.dark,
            ],
            labelFor: (mode) => context.l10n(switch (mode) {
              ThemeModeSetting.system => 'themeSystem',
              ThemeModeSetting.light => 'themeLight',
              ThemeModeSetting.dark => 'themeDark',
            },),
            onChanged: provider.setTheme,
          ),
          _DropdownRow<LocaleSetting>(
            label: context.l10n('language'),
            value: settings.locale,
            items: const [
              LocaleSetting.system,
              LocaleSetting.english,
              LocaleSetting.persian,
            ],
            labelFor: (locale) => switch (locale) {
              LocaleSetting.system => context.l10n('languageSystem'),
              LocaleSetting.english => 'English',
              LocaleSetting.persian => 'فارسی',
            },
            onChanged: provider.setLocale,
          ),
          SwitchListTile(
            title: Text(context.l10n('startWithWindows')),
            value: settings.startWithWindows,
            onChanged: (value) async {
              try {
                await provider.setStartWithWindows(value);
              } on Object {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                        content:
                            Text(context.l10n('connectionError')),),
                  );
                }
              }
            },
          ),
          SwitchListTile(
            title: Text(context.l10n('startMinimized')),
            value: settings.startMinimized,
            onChanged: (value) =>
                provider.update((s) => s.copyWith(startMinimized: value)),
          ),
          SwitchListTile(
            title: Text(context.l10n('autoConnect')),
            value: settings.autoConnect,
            onChanged: (value) =>
                provider.update((s) => s.copyWith(autoConnect: value)),
          ),
          SwitchListTile(
            title: Text(context.l10n('minimizeToTray')),
            value: settings.minimizeToTray,
            onChanged: (value) =>
                provider.update((s) => s.copyWith(minimizeToTray: value)),
          ),
          SectionHeader(title: context.l10n('sectionProxy')),
          _DropdownRow<ProxyMode>(
            label: context.l10n('proxyMode'),
            value: settings.proxyMode,
            items: ProxyMode.values,
            labelFor: (mode) => context.l10n(switch (mode) {
              ProxyMode.system => 'proxyModeSystem',
              ProxyMode.socks => 'proxyModeSocks',
              ProxyMode.http => 'proxyModeHttp',
              ProxyMode.tun => 'proxyModeTun',
            },),
            onChanged: provider.setProxyMode,
          ),
          _PortRow(
            socksPort: settings.inbounds.socksPort,
            httpPort: settings.inbounds.httpPort,
            onSaved: (socks, http) => provider.update((s) => s.copyWith(
                inbounds: s.inbounds
                    .copyWith(socksPort: socks, httpPort: http),),),
          ),
          SectionHeader(title: context.l10n('sectionRouting')),
          _DropdownRow<RoutingMode>(
            label: context.l10n('routingMode'),
            value: settings.routing.mode,
            items: RoutingMode.values,
            labelFor: (mode) => context.l10n(switch (mode) {
              RoutingMode.global => 'routingGlobal',
              RoutingMode.direct => 'routingDirect',
              RoutingMode.proxy => 'routingProxy',
              RoutingMode.ruleBased => 'routingRuleBased',
            },),
            onChanged: (mode) => provider.update((s) => s.copyWith(
                routing: s.routing.copyWith(mode: mode),),),
          ),
          SwitchListTile(
            title: Text(context.l10n('bypassLan')),
            value: settings.routing.bypassLan,
            onChanged: (value) => provider.update((s) => s.copyWith(
                routing: s.routing.copyWith(bypassLan: value),),),
          ),
          SwitchListTile(
            title: Text(context.l10n('bypassIran')),
            value: settings.routing.bypassIran,
            onChanged: (value) => provider.update((s) => s.copyWith(
                routing: s.routing.copyWith(bypassIran: value),),),
          ),
          SectionHeader(title: context.l10n('sectionDns')),
          _DnsRow(provider: provider, settings: settings),
          SectionHeader(title: context.l10n('sectionNetwork')),
          _DropdownRow<NetworkPreset>(
            label: context.l10n('networkPreset'),
            value: settings.tuning.preset,
            items: NetworkPreset.values,
            labelFor: (preset) => context.l10n(switch (preset) {
              NetworkPreset.stable => 'presetStable',
              NetworkPreset.balanced => 'presetBalanced',
              NetworkPreset.highLatency => 'presetHighLatency',
              NetworkPreset.unstable => 'presetUnstable',
            },),
            onChanged: provider.applyNetworkPreset,
          ),
          _DropdownRow<IpPreference>(
            label: context.l10n('ipPreference'),
            value: settings.tuning.ipPreference,
            items: IpPreference.values,
            labelFor: (preference) => context.l10n(switch (preference) {
              IpPreference.auto => 'ipAuto',
              IpPreference.preferIpv4 => 'ipPrefer4',
              IpPreference.preferIpv6 => 'ipPrefer6',
            },),
            onChanged: (preference) => provider.update((s) => s.copyWith(
                tuning: s.tuning.copyWith(ipPreference: preference),),),
          ),
          SectionHeader(title: context.l10n('sectionCore')),
          SwitchListTile(
            title: Text(context.l10n('preferLegacyCore')),
            value: settings.preferLegacyCore,
            onChanged: (value) => provider.update(
                (s) => s.copyWith(preferLegacyCore: value),),
          ),
          SwitchListTile(
            title: Text(context.l10n('checkUpdates')),
            value: settings.checkUpdatesOnStartup,
            onChanged: (value) => provider.update(
                (s) => s.copyWith(checkUpdatesOnStartup: value),),
          ),
          SectionHeader(title: context.l10n('sectionBackup')),
          _BackupRow(),
          const SizedBox(height: 32),
        ],
      ),
    );
  }
}

class _DropdownRow<T> extends StatelessWidget {
  const _DropdownRow({
    required this.label,
    required this.value,
    required this.items,
    required this.labelFor,
    required this.onChanged,
  });

  final String label;
  final T value;
  final List<T> items;
  final String Function(T) labelFor;
  final Future<void> Function(T) onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          SizedBox(width: 220, child: Text(label)),
          Expanded(
            child: DropdownButtonFormField<T>(
              value: value,
              // Long localized labels (Ahem test font is full-width) must
              // ellipsize instead of overflowing the decorator's inner Row.
              isExpanded: true,
              items: [
                for (final item in items)
                  DropdownMenuItem(value: item, child: Text(labelFor(item))),
              ],
              onChanged: (selected) {
                if (selected != null) onChanged(selected);
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _PortRow extends StatefulWidget {
  const _PortRow({
    required this.socksPort,
    required this.httpPort,
    required this.onSaved,
  });

  final int socksPort;
  final int httpPort;
  final Future<void> Function(int socks, int http) onSaved;

  @override
  State<_PortRow> createState() => _PortRowState();
}

class _PortRowState extends State<_PortRow> {
  late final TextEditingController _socks;
  late final TextEditingController _http;

  @override
  void initState() {
    super.initState();
    _socks = TextEditingController(text: '${widget.socksPort}');
    _http = TextEditingController(text: '${widget.httpPort}');
  }

  @override
  void didUpdateWidget(covariant _PortRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.socksPort != widget.socksPort) {
      _socks.text = '${widget.socksPort}';
    }
    if (oldWidget.httpPort != widget.httpPort) {
      _http.text = '${widget.httpPort}';
    }
  }

  @override
  void dispose() {
    _socks.dispose();
    _http.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _socks,
              decoration: InputDecoration(
                  labelText: context.l10n('socksPort'),),
              keyboardType: TextInputType.number,
              textDirection: TextDirection.ltr,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: TextField(
              controller: _http,
              decoration: InputDecoration(
                  labelText: context.l10n('httpPort'),),
              keyboardType: TextInputType.number,
              textDirection: TextDirection.ltr,
            ),
          ),
          const SizedBox(width: 12),
          FilledButton.tonal(
            onPressed: () {
              final socks = int.tryParse(_socks.text.trim()) ?? 0;
              final http = int.tryParse(_http.text.trim()) ?? 0;
              if (socks < 1 ||
                  socks > 65535 ||
                  http < 1 ||
                  http > 65535 ||
                  socks == http) {
                return;
              }
              widget.onSaved(socks, http);
            },
            child: Text(context.l10n('save')),
          ),
        ],
      ),
    );
  }
}

class _DnsRow extends StatefulWidget {
  const _DnsRow({required this.provider, required this.settings});

  final SettingsProvider provider;
  final AppSettings settings;

  @override
  State<_DnsRow> createState() => _DnsRowState();
}

class _DnsRowState extends State<_DnsRow> {
  late final TextEditingController _servers;

  @override
  void initState() {
    super.initState();
    _servers = TextEditingController(
        text: widget.settings.dns.servers.join(', '),);
  }

  @override
  void dispose() {
    _servers.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _servers,
                decoration: InputDecoration(
                    labelText: context.l10n('dnsServers'),),
                textDirection: TextDirection.ltr,
              ),
            ),
            const SizedBox(width: 12),
            FilledButton.tonal(
              onPressed: () {
                final servers = _servers.text
                    .split(',')
                    .map((s) => s.trim())
                    .where((s) => s.isNotEmpty)
                    .toList();
                if (servers.isEmpty) return;
                widget.provider.update((s) => s.copyWith(
                    dns: s.dns.copyWith(servers: servers),),);
              },
              child: Text(context.l10n('save')),
            ),
          ],
        ),
        SwitchListTile(
          title: Text(context.l10n('useSystemDns')),
          value: widget.settings.dns.useSystemDns,
          onChanged: (value) => widget.provider.update((s) => s.copyWith(
              dns: s.dns.copyWith(useSystemDns: value),),),
        ),
        SwitchListTile(
          title: Text(context.l10n('enableDoh')),
          value: widget.settings.dns.enableDoh,
          onChanged: (value) => widget.provider.update((s) => s.copyWith(
              dns: s.dns.copyWith(enableDoh: value),),),
        ),
      ],
    );
  }
}

class _BackupRow extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        FilledButton.tonalIcon(
          onPressed: () => _export(context),
          icon: const Icon(Icons.save_alt),
          label: Text(context.l10n('exportBackup')),
        ),
        const SizedBox(width: 12),
        FilledButton.tonalIcon(
          onPressed: () => _import(context),
          icon: const Icon(Icons.restore),
          label: Text(context.l10n('importBackup')),
        ),
      ],
    );
  }

  Future<String?> _askPassword(BuildContext context) async {
    final controller = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(context.l10n('exportBackup')),
        content: TextField(
          controller: controller,
          decoration: InputDecoration(
              labelText: context.l10n('backupPassword'),),
          obscureText: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(context.l10n('cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text),
            child: Text(context.l10n('confirm')),
          ),
        ],
      ),
    );
  }

  Future<void> _export(BuildContext context) async {
    final password = await _askPassword(context);
    if (password == null || !context.mounted) return;
    final path = await FilePicker.platform.saveFile(
      dialogTitle: context.l10n('exportBackup'),
      fileName: 'iranlink-backup.json',
      type: FileType.custom,
      allowedExtensions: ['json'],
    );
    if (path == null || !context.mounted) return;
    try {
      final services = context.read<AppServices>();
      await services.backup.exportToFile(
        file: File(path),
        settings: services.settings.current,
        profiles: services.profiles.profiles,
        subscriptions: services.subscriptions.subscriptions,
        password: password,
      );
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.l10n('diagnosticsExported'))),
        );
      }
    } on Object {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.l10n('connectionError'))),
        );
      }
    }
  }

  Future<void> _import(BuildContext context) async {
    final picked = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['json'],
      withData: true,
    );
    final files = picked?.files;
    final bytes =
        (files != null && files.isNotEmpty) ? files.first.bytes : null;
    if (bytes == null || !context.mounted) return;
    final password = await _askPassword(context);
    if (password == null || !context.mounted) return;
    try {
      final services = context.read<AppServices>();
      final tempDir =
          await Directory.systemTemp.createTemp('iranlink-backup-');
      final tempFile = File('${tempDir.path}/backup.json');
      await tempFile.writeAsBytes(bytes);
      final data = await services.backup.importFromFile(
        tempFile,
        password: password,
      );
      await tempDir.delete(recursive: true).catchError((_) => tempDir);
      await services.settings.save(data.settings);
      for (final profile in data.profiles) {
        await services.profiles.add(profile);
      }
      for (final subscription in data.subscriptions) {
        await services.subscriptions.add(
          name: subscription.name,
          url: subscription.url,
        );
      }
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.l10n('diagnosticsExported'))),
        );
      }
    } on Object {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.l10n('connectionError'))),
        );
      }
    }
  }
}
