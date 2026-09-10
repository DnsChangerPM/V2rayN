import 'package:flutter/material.dart';

import '../../l10n/strings.dart';

/// Result of the "add subscription" dialog.
typedef SubscriptionDialogResult = ({String url, String? name});

Future<SubscriptionDialogResult?> showSubscriptionDialog(BuildContext context) {
  return showDialog<SubscriptionDialogResult>(
    context: context,
    builder: (context) => const _SubscriptionDialog(),
  );
}

class _SubscriptionDialog extends StatefulWidget {
  const _SubscriptionDialog();

  @override
  State<_SubscriptionDialog> createState() => _SubscriptionDialogState();
}

class _SubscriptionDialogState extends State<_SubscriptionDialog> {
  final _url = TextEditingController();
  final _name = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  @override
  void dispose() {
    _url.dispose();
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final strings = Strings.of(Localizations.localeOf(context));
    return AlertDialog(
      title: Text(strings.addSubscription),
      content: SizedBox(
        width: 520,
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              TextFormField(
                controller: _url,
                decoration: InputDecoration(labelText: strings.subscriptionUrl),
                validator: (value) => (value == null || value.trim().isEmpty)
                    ? strings.subscriptionUrl
                    : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _name,
                decoration: InputDecoration(labelText: strings.subscriptionName),
              ),
            ],
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
              Navigator.of(context).pop((
                url: _url.text.trim(),
                name: _name.text.trim().isEmpty ? null : _name.text.trim(),
              ));
            }
          },
          child: Text(strings.save),
        ),
      ],
    );
  }
}
