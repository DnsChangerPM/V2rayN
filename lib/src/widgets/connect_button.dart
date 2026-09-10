/// The big CONNECT / DISCONNECT button (dashboard + app bar).
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n/app_localizations.dart';
import '../state/connection_provider.dart';

class ConnectButton extends StatelessWidget {
  const ConnectButton({super.key, this.expanded = true});

  final bool expanded;

  @override
  Widget build(BuildContext context) {
    final connection = context.watch<ConnectionProvider>();
    final connected = connection.isConnected;
    final busy = connection.isBusy;
    final label = busy
        ? context.l10n(connected ? 'disconnecting' : 'connecting')
        : context.l10n(connected ? 'disconnect' : 'connect');
    final button = FilledButton.icon(
      onPressed: busy ? null : () => connection.toggle(),
      icon: busy
          ? const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : Icon(connected ? Icons.link_off : Icons.link),
      label: Text(label),
      style: FilledButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
      ),
    );
    if (!expanded) return button;
    return SizedBox(width: double.infinity, child: button);
  }
}
