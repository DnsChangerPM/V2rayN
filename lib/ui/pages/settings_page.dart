import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/app_controller.dart';
import '../../core/model/enums.dart';
import '../../core/model/settings.dart';
import '../../l10n/strings.dart';
import '../../utils/paths.dart';

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key, required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) => _SettingsBody(controller: controller),
    );
  }
}

class _SettingsBody extends StatelessWidget {
  const _SettingsBody({required this.controller});

  final AppController controller;

  AppSettings get s => controller.settings;

  @override
  Widget build(BuildContext context) {
    final strings = Strings.of(Localizations.localeOf(context));
    return ListView(
      padding: const EdgeInsets.all(20),
      children: <Widget>[
        _section(context, strings.general, <Widget>[
          _dropdown<AppLanguage>(
            context,
            strings.language,
            s.language,
            AppLanguage.values,
            (v) => v == AppLanguage.persian
                ? strings.persian
                : (v == AppLanguage.english ? strings.english : strings.system),
            (v) => controller.patchSettings(s.copyWith(language: v)),
          ),
          _dropdown<String>(
            context,
            strings.theme,
            s.themeMode,
            const <String>['system', 'light', 'dark'],
            (v) => v == 'light'
                ? strings.themeLight
                : (v == 'dark' ? strings.themeDark : strings.themeSystem),
            (v) => controller.patchSettings(s.copyWith(themeMode: v)),
          ),
          _switch(context, strings.closeToTray, s.closeToTray,
              (v) => controller.patchSettings(s.copyWith(closeToTray: v))),
          _switch(context, strings.startMinimized, s.startMinimized,
              (v) => controller.patchSettings(s.copyWith(startMinimized: v))),
          _switch(context, strings.autoStart, s.autoStartEnabled,
              (v) => controller.patchSettings(s.copyWith(autoStartEnabled: v))),
          _switch(context, strings.autoConnect, s.autoConnect,
              (v) => controller.patchSettings(s.copyWith(autoConnect: v))),
          _switch(context, strings.autoReconnect, s.autoReconnect,
              (v) => controller.patchSettings(s.copyWith(autoReconnect: v))),
        ]),
        _section(context, strings.core, <Widget>[
          _dropdown<CoreType>(
            context,
            strings.core,
            s.coreType,
            CoreType.values,
            (v) => v.label,
            (v) => controller.updateSettings(s.copyWith(coreType: v)),
          ),
          _dropdown<CoreFlavour>(
            context,
            strings.coreFlavour,
            s.coreFlavour,
            CoreFlavour.values,
            (v) => v == CoreFlavour.auto
                ? strings.flavourAuto
                : (v == CoreFlavour.legacy
                    ? strings.flavourLegacy
                    : strings.flavourModern),
            (v) => controller.updateSettings(s.copyWith(coreFlavour: v)),
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(strings.coreVersionLabel),
            subtitle: Text(controller.coreVersionText.isEmpty
                ? strings.unknown
                : controller.coreVersionText),
          ),
        ]),
        _section(context, strings.networkSection, <Widget>[
          _dropdown<ProxyMode>(
            context,
            strings.proxyMode,
            s.proxyMode,
            ProxyMode.values,
            (v) => v == ProxyMode.systemProxy
                ? strings.modeSystemProxy
                : (v == ProxyMode.tun ? strings.modeTun : strings.modeBoth),
            (v) => controller.updateSettings(s.copyWith(proxyMode: v)),
          ),
          if (s.proxyMode.usesTun)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                strings.tunHint,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          Row(
            children: <Widget>[
              Expanded(
                child: _numberField(context, strings.httpPort, s.httpPort,
                    (v) => controller.updateSettings(s.copyWith(httpPort: v))),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _numberField(context, strings.socksPort, s.socksPort,
                    (v) => controller.updateSettings(s.copyWith(socksPort: v))),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _numberField(context, strings.apiPort, s.apiPort,
                    (v) => controller.updateSettings(s.copyWith(apiPort: v))),
              ),
            ],
          ),
          _switch(context, strings.allowLan, s.allowLan,
              (v) => controller.updateSettings(s.copyWith(allowLan: v))),
        ]),
        _section(context, strings.routing, <Widget>[
          _dropdown<RoutingMode>(
            context,
            strings.routing,
            s.routingMode,
            RoutingMode.values,
            (v) => v == RoutingMode.global
                ? strings.routingGlobal
                : (v == RoutingMode.smartIran
                    ? strings.routingSmartIran
                    : strings.routingCustom),
            (v) => controller.updateSettings(s.copyWith(routingMode: v)),
          ),
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              strings.routingHint,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
          _switch(context, strings.bypassIran, s.bypassIran,
              (v) => controller.updateSettings(s.copyWith(bypassIran: v))),
          _switch(context, strings.blockAds, s.blockAds,
              (v) => controller.updateSettings(s.copyWith(blockAds: v))),
          _switch(context, strings.blockQuic, s.blockQuic,
              (v) => controller.updateSettings(s.copyWith(blockQuic: v))),
          _textField(context, strings.customBypass,
              s.customBypassDomains.join(', '),
              (v) => controller.updateSettings(s.copyWith(
                  customBypassDomains: _splitList(v)))),
          _textField(context, strings.customProxy,
              s.customProxyDomains.join(', '),
              (v) => controller.updateSettings(
                  s.copyWith(customProxyDomains: _splitList(v)))),
          if (s.routingMode == RoutingMode.custom)
            _textField(
              context,
              strings.customRules,
              s.customRulesJson,
              (v) =>
                  controller.updateSettings(s.copyWith(customRulesJson: v)),
              maxLines: 6,
              hint: strings.customRulesHint,
            ),
        ]),
        _section(context, strings.dns, <Widget>[
          _textField(context, strings.dnsRemote, s.dnsRemoteDoh,
              (v) => controller.updateSettings(s.copyWith(dnsRemoteDoh: v.trim()))),
          _textField(context, strings.dnsIran, s.dnsIran,
              (v) => controller.updateSettings(s.copyWith(dnsIran: v.trim()))),
          _switch(context, strings.dnsIpv4Only, s.dnsUseIpv4Only,
              (v) => controller.updateSettings(s.copyWith(dnsUseIpv4Only: v))),
          _switch(context, strings.dnsCache, s.enableDnsCache,
              (v) => controller.updateSettings(s.copyWith(enableDnsCache: v))),
        ]),
        _section(context, strings.advancedSection, <Widget>[
          _switch(context, strings.fragment, s.enableFragment,
              (v) => controller.updateSettings(s.copyWith(enableFragment: v))),
          if (s.enableFragment) ...<Widget>[
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                strings.fragmentHint,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
            Row(
              children: <Widget>[
                Expanded(
                  child: _textField(context, strings.fragmentLength,
                      s.fragmentLength,
                      (v) => controller.updateSettings(
                          s.copyWith(fragmentLength: v.trim()))),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _textField(context, strings.fragmentInterval,
                      s.fragmentInterval,
                      (v) => controller.updateSettings(
                          s.copyWith(fragmentInterval: v.trim()))),
                ),
              ],
            ),
          ],
          _switch(context, strings.autoSelect, s.autoSelectFastest,
              (v) => controller.updateSettings(s.copyWith(autoSelectFastest: v))),
          if (s.autoSelectFastest)
            _textField(context, strings.probeUrl, s.probeUrl,
                (v) => controller.updateSettings(s.copyWith(probeUrl: v.trim()))),
          _switch(context, strings.muxEnabled, s.muxEnabled,
              (v) => controller.updateSettings(s.copyWith(muxEnabled: v))),
          _dropdown<String>(
            context,
            strings.logLevel,
            s.logLevel,
            const <String>['debug', 'info', 'warning', 'error', 'none'],
            (v) => v,
            (v) => controller.updateSettings(s.copyWith(logLevel: v)),
          ),
          if (s.proxyMode.usesTun) ...<Widget>[
            const Divider(),
            _textField(context, strings.tunName, s.tunName,
                (v) => controller.updateSettings(s.copyWith(tunName: v.trim()))),
            _textField(context, strings.tunAddress, s.tunAddress,
                (v) => controller.updateSettings(s.copyWith(tunAddress: v.trim()))),
            _textField(context, strings.tunGateway, s.tunGateway,
                (v) => controller.updateSettings(s.copyWith(tunGateway: v.trim()))),
            _textField(context, strings.tunDns, s.tunDns,
                (v) => controller.updateSettings(s.copyWith(tunDns: v.trim()))),
            _numberField(context, strings.mtuLabel, s.tunMtu,
                (v) => controller.updateSettings(s.copyWith(tunMtu: v))),
            _switch(context, strings.tunAutoRoute, s.tunAutoRoute,
                (v) => controller.updateSettings(s.copyWith(tunAutoRoute: v))),
          ],
        ]),
        _section(context, strings.about, <Widget>[
          Wrap(
            spacing: 8,
            children: <Widget>[
              OutlinedButton(
                onPressed: () => controller.open(AppPaths.dataDir.path),
                child: Text(strings.openDataFolder),
              ),
              OutlinedButton(
                onPressed: () => controller.open(AppPaths.coreDir.path),
                child: Text(strings.openCoreFolder),
              ),
              OutlinedButton(
                onPressed: () => controller.open(AppPaths.logDir.path),
                child: Text(strings.openLogsFolder),
              ),
            ],
          ),
        ]),
        const SizedBox(height: 24),
      ],
    );
  }

  static List<String> _splitList(String value) => value
      .split(',')
      .map((e) => e.trim())
      .where((e) => e.isNotEmpty)
      .toList();

  static Widget _section(BuildContext context, String title, List<Widget> children) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            title,
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  color: Theme.of(context).colorScheme.primary,
                ),
          ),
          const SizedBox(height: 6),
          Card(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Column(children: children),
            ),
          ),
        ],
      ),
    );
  }

  static Widget _switch(
    BuildContext context,
    String label,
    bool value,
    ValueChanged<bool> onChanged,
  ) =>
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        title: Text(label),
        value: value,
        onChanged: onChanged,
      );

  static Widget _dropdown<T>(
    BuildContext context,
    String label,
    T value,
    List<T> values,
    String Function(T) display,
    ValueChanged<T> onChanged,
  ) =>
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: DropdownButtonFormField<T>(
          initialValue: value,
          decoration: InputDecoration(labelText: label),
          items: values
              .map((e) => DropdownMenuItem<T>(value: e, child: Text(display(e))))
              .toList(),
          onChanged: (v) {
            if (v != null) {
              onChanged(v);
            }
          },
        ),
      );

  static Widget _textField(
    BuildContext context,
    String label,
    String value,
    ValueChanged<String> onSubmitted, {
    int maxLines = 1,
    String? hint,
  }) {
    final controller = TextEditingController(text: value);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: TextField(
        controller: controller,
        maxLines: maxLines,
        decoration: InputDecoration(labelText: label, hintText: hint),
        onSubmitted: onSubmitted,
        onEditingComplete: () => onSubmitted(controller.text),
      ),
    );
  }

  static Widget _numberField(
    BuildContext context,
    String label,
    int value,
    ValueChanged<int> onSubmitted,
  ) {
    final controller = TextEditingController(text: '$value');
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: TextField(
        controller: controller,
        keyboardType: TextInputType.number,
        inputFormatters: <TextInputFormatter>[
          FilteringTextInputFormatter.digitsOnly,
        ],
        decoration: InputDecoration(labelText: label),
        onSubmitted: (v) => onSubmitted(int.tryParse(v) ?? value),
        onEditingComplete: () =>
            onSubmitted(int.tryParse(controller.text) ?? value),
      ),
    );
  }
}
