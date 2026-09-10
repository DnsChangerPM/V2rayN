import 'package:flutter/material.dart';

import '../../core/app_controller.dart';
import '../../l10n/strings.dart';

class LogsPage extends StatelessWidget {
  const LogsPage({super.key, required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    final strings = Strings.of(Localizations.localeOf(context));
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final lines = controller.logLines;
        return Scaffold(
          body: Column(
            children: <Widget>[
              Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: <Widget>[
                    Text(strings.logs,
                        style: Theme.of(context).textTheme.titleMedium),
                    const Spacer(),
                    OutlinedButton.icon(
                      onPressed: () => controller.clearLogs(),
                      icon: const Icon(Icons.clear_all),
                      label: Text(strings.clearLogs),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: lines.isEmpty
                    ? Center(child: Text(strings.logsEmpty))
                    : ListView.builder(
                        padding: const EdgeInsets.all(12),
                        itemCount: lines.length,
                        itemBuilder: (context, index) => Padding(
                          padding: const EdgeInsets.symmetric(vertical: 1),
                          child: SelectableText(
                            lines[index],
                            style: const TextStyle(
                              fontFamily: 'Consolas',
                              fontSize: 12,
                            ),
                          ),
                        ),
                      ),
              ),
            ],
          ),
        );
      },
    );
  }
}
