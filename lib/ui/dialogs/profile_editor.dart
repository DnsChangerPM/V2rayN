import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/model/enums.dart';
import '../../core/model/profile.dart';
import '../../l10n/strings.dart';

/// Shows the server editor and returns the edited profile (or `null`).
Future<Profile?> showProfileEditor(BuildContext context, Profile initial) {
  return showDialog<Profile>(
    context: context,
    builder: (context) => _ProfileEditorDialog(initial: initial),
  );
}

class _ProfileEditorDialog extends StatefulWidget {
  const _ProfileEditorDialog({required this.initial});

  final Profile initial;

  @override
  State<_ProfileEditorDialog> createState() => _ProfileEditorDialogState();
}

class _ProfileEditorDialogState extends State<_ProfileEditorDialog> {
  late Profile _profile;
  final _formKey = GlobalKey<FormState>();

  late final TextEditingController _remark;
  late final TextEditingController _address;
  late final TextEditingController _port;
  late final TextEditingController _uuid;
  late final TextEditingController _password;
  late final TextEditingController _security;
  late final TextEditingController _flow;
  late final TextEditingController _host;
  late final TextEditingController _path;
  late final TextEditingController _sni;
  late final TextEditingController _fingerprint;
  late final TextEditingController _publicKey;
  late final TextEditingController _shortId;

  @override
  void initState() {
    super.initState();
    _profile = widget.initial;
    _remark = TextEditingController(text: _profile.remark);
    _address = TextEditingController(text: _profile.address);
    _port = TextEditingController(text: '${_profile.port}');
    _uuid = TextEditingController(text: _profile.uuid);
    _password = TextEditingController(text: _profile.password);
    _security = TextEditingController(text: _profile.security);
    _flow = TextEditingController(text: _profile.flow);
    _host = TextEditingController(text: _profile.host);
    _path = TextEditingController(text: _profile.path);
    _sni = TextEditingController(text: _profile.sni);
    _fingerprint = TextEditingController(text: _profile.fingerprint);
    _publicKey = TextEditingController(text: _profile.realityPublicKey);
    _shortId = TextEditingController(text: _profile.realityShortId);
  }

  @override
  void dispose() {
    for (final controller in <TextEditingController>[
      _remark,
      _address,
      _port,
      _uuid,
      _password,
      _security,
      _flow,
      _host,
      _path,
      _sni,
      _fingerprint,
      _publicKey,
      _shortId,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  void _apply() {
    _profile
      ..remark = _remark.text.trim()
      ..address = _address.text.trim()
      ..port = int.tryParse(_port.text.trim()) ?? 443
      ..uuid = _uuid.text.trim()
      ..password = _password.text.trim()
      ..security = _security.text.trim()
      ..flow = _flow.text.trim()
      ..host = _host.text.trim()
      ..path = _path.text.trim()
      ..sni = _sni.text.trim()
      ..fingerprint = _fingerprint.text.trim()
      ..realityPublicKey = _publicKey.text.trim()
      ..realityShortId = _shortId.text.trim();
  }

  @override
  Widget build(BuildContext context) {
    final strings = Strings.of(Localizations.localeOf(context));
    final isVmess = _profile.protocol == ProtocolType.vmess;
    final isVless = _profile.protocol == ProtocolType.vless;
    final isTrojan = _profile.protocol == ProtocolType.trojan;
    final isSs = _profile.protocol == ProtocolType.shadowsocks;
    final isReality = _profile.securityType == SecurityType.reality;

    return AlertDialog(
      title: Text(widget.initial.remark.isEmpty ? strings.add : strings.edit),
      content: SizedBox(
        width: 620,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                _field(_remark, strings.remark),
                const SizedBox(height: 10),
                Row(
                  children: <Widget>[
                    Expanded(
                      child: DropdownButtonFormField<ProtocolType>(
                        initialValue: _profile.protocol,
                        decoration: InputDecoration(labelText: strings.protocol),
                        items: ProtocolType.values
                            .map((e) => DropdownMenuItem<ProtocolType>(
                                  value: e,
                                  child: Text(e.id),
                                ))
                            .toList(),
                        onChanged: (value) {
                          if (value != null) {
                            setState(() => _profile = _profile.copyWith(protocol: value));
                          }
                        },
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(child: _field(_address, strings.address)),
                    const SizedBox(width: 12),
                    SizedBox(
                      width: 110,
                      child: _field(
                        _port,
                        strings.port,
                        numeric: true,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                if (isVless || isVmess) _field(_uuid, strings.uuid),
                if (isTrojan) _field(_password, strings.password),
                if (isSs) ...<Widget>[
                  _field(_security, strings.method),
                  const SizedBox(height: 10),
                  _field(_password, strings.password),
                ],
                if (isVless) ...<Widget>[
                  const SizedBox(height: 10),
                  DropdownButtonFormField<String>(
                    initialValue: _profile.flow.isEmpty ? '' : _profile.flow,
                    decoration: InputDecoration(labelText: strings.flow),
                    items: const <DropdownMenuItem<String>>[
                      DropdownMenuItem<String>(value: '', child: Text('none')),
                      DropdownMenuItem<String>(
                          value: 'xtls-rprx-vision',
                          child: Text('xtls-rprx-vision')),
                    ],
                    onChanged: (value) => _flow.text = value ?? '',
                  ),
                ],
                const SizedBox(height: 10),
                Row(
                  children: <Widget>[
                    Expanded(
                      child: DropdownButtonFormField<TransportType>(
                        initialValue: _profile.network,
                        decoration: InputDecoration(labelText: strings.transport),
                        items: TransportType.values
                            .map((e) => DropdownMenuItem<TransportType>(
                                  value: e,
                                  child: Text(e.id),
                                ))
                            .toList(),
                        onChanged: (value) {
                          if (value != null) {
                            setState(() => _profile = _profile.copyWith(network: value));
                          }
                        },
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: DropdownButtonFormField<SecurityType>(
                        initialValue: _profile.securityType,
                        decoration: InputDecoration(labelText: strings.security),
                        items: SecurityType.values
                            .map((e) => DropdownMenuItem<SecurityType>(
                                  value: e,
                                  child: Text(e.id),
                                ))
                            .toList(),
                        onChanged: (value) {
                          if (value != null) {
                            setState(() =>
                                _profile = _profile.copyWith(security: value.id));
                          }
                        },
                      ),
                    ),
                  ],
                ),
                if (_profile.network.needsHost) ...<Widget>[
                  const SizedBox(height: 10),
                  _field(_host, strings.host),
                ],
                if (_profile.network.needsPath) ...<Widget>[
                  const SizedBox(height: 10),
                  _field(_path, strings.path),
                ],
                if (_profile.isTls || isReality) ...<Widget>[
                  const SizedBox(height: 10),
                  Row(
                    children: <Widget>[
                      Expanded(child: _field(_sni, strings.sni)),
                      const SizedBox(width: 12),
                      Expanded(child: _field(_fingerprint, strings.fingerprint)),
                    ],
                  ),
                ],
                if (isReality) ...<Widget>[
                  const SizedBox(height: 10),
                  _field(_publicKey, strings.publicKey),
                  const SizedBox(height: 10),
                  _field(_shortId, strings.shortId),
                ],
                const SizedBox(height: 10),
                Row(
                  children: <Widget>[
                    Expanded(
                      child: DropdownButtonFormField<FragmentPreset>(
                        initialValue: _profile.fragment,
                        decoration: InputDecoration(labelText: strings.fragment),
                        items: FragmentPreset.values
                            .map((e) => DropdownMenuItem<FragmentPreset>(
                                  value: e,
                                  child: Text(e.id),
                                ))
                            .toList(),
                        onChanged: (value) {
                          if (value != null) {
                            setState(() =>
                                _profile = _profile.copyWith(fragment: value));
                          }
                        },
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(strings.udp),
                        value: _profile.enableUdp,
                        onChanged: (value) => setState(
                            () => _profile = _profile.copyWith(enableUdp: value)),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(strings.cancel),
        ),
        FilledButton(
          onPressed: () {
            if (_formKey.currentState?.validate() ?? false) {
              _apply();
              Navigator.of(context).pop(_profile);
            }
          },
          child: Text(strings.save),
        ),
      ],
    );
  }

  Widget _field(TextEditingController controller, String label,
          {bool numeric = false}) =>
      TextFormField(
        controller: controller,
        decoration: InputDecoration(labelText: label),
        inputFormatters:
            numeric ? <TextInputFormatter>[FilteringTextInputFormatter.digitsOnly] : null,
        validator: (value) {
          if (label.isNotEmpty && (value == null || value.trim().isEmpty)) {
            return '';
          }
          return null;
        },
      );
}
