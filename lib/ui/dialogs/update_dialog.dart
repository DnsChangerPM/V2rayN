import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:win_shell/win_shell.dart';

import '../../l10n/strings.dart';
import '../../utils/app_version.dart';

/// Queries the GitHub releases API and offers the newest installer.
Future<void> showUpdateDialog(BuildContext context) async {
  final strings = Strings.of(Localizations.localeOf(context));
  await showDialog<void>(
    context: context,
    builder: (context) => _UpdateDialog(strings: strings),
  );
}

class _UpdateDialog extends StatefulWidget {
  const _UpdateDialog({required this.strings});

  final Strings strings;

  @override
  State<_UpdateDialog> createState() => _UpdateDialogState();
}

class _UpdateDialogState extends State<_UpdateDialog> {
  String? _latest;
  String? _url;
  String? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _check();
  }

  Future<void> _check() async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 10);
    try {
      final request = await client
          .getUrl(Uri.parse('https://api.github.com/repos/DnsChangerPM/V2rayN/releases/latest'))
          .timeout(const Duration(seconds: 15));
      request.headers.set(HttpHeaders.userAgentHeader, 'Radin');
      final response = await request.close();
      final body = await response.transform(utf8.decoder).join();
      if (response.statusCode == 200) {
        final json = jsonDecode(body);
        if (json is Map) {
          final tag = (json['tag_name'] ?? '').toString();
          final assets = json['assets'];
          if (assets is List) {
            for (final asset in assets) {
              if (asset is Map &&
                  (asset['name'] ?? '').toString().endsWith('.exe')) {
                _url = (asset['browser_download_url'] ?? '').toString();
                break;
              }
            }
          }
          setState(() {
            _latest = tag.replaceFirst(RegExp(r'^[vV]'), '');
            _loading = false;
          });
          return;
        }
      }
      setState(() {
        _error = 'HTTP ${response.statusCode}';
        _loading = false;
      });
    } on Object catch (error) {
      setState(() {
        _error = '$error';
        _loading = false;
      });
    } finally {
      client.close(force: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final strings = widget.strings;
    final latest = _latest;
    final isNewer = latest != null &&
        AppVersion.compare(latest, AppVersion.version) > 0;

    return AlertDialog(
      title: Text(strings.checkUpdate),
      content: SizedBox(
        width: 420,
        child: _loading
            ? const SizedBox(
                height: 60,
                child: Center(child: CircularProgressIndicator()),
              )
            : Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text('${strings.version}: ${AppVersion.version}'),
                  const SizedBox(height: 4),
                  Text(
                    latest == null
                        ? (strings.error +
                            (_error != null ? ': $_error' : ''))
                        : '${strings.updateAvailable}: $latest',
                  ),
                  if (latest != null && !isNewer) ...<Widget>[
                    const SizedBox(height: 8),
                    Text(strings.upToDate),
                  ],
                ],
              ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(strings.close),
        ),
        if (isNewer && _url != null)
          FilledButton(
            onPressed: () {
              winShell.openUrl(_url!);
              Navigator.of(context).pop();
            },
            child: Text(strings.download),
          ),
      ],
    );
  }
}
