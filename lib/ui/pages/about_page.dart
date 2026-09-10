import 'package:flutter/material.dart';

import '../../core/app_controller.dart';
import '../../l10n/strings.dart';
import '../../utils/app_version.dart';
import '../dialogs/update_dialog.dart';

class AboutPage extends StatelessWidget {
  const AboutPage({super.key, required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    final strings = Strings.of(Localizations.localeOf(context));
    final theme = Theme.of(context);
    final os = controller.osVersion;

    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        return ListView(
          padding: const EdgeInsets.all(24),
          children: <Widget>[
            Row(
              children: <Widget>[
                Image.asset(
                  'assets/app_icon_256.png',
                  width: 72,
                  height: 72,
                  errorBuilder: (_, __, ___) => const Icon(Icons.shield, size: 72),
                ),
                const SizedBox(width: 16),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(AppVersion.name, style: theme.textTheme.headlineSmall),
                    Text(
                      '${strings.version} ${AppVersion.display}',
                      style: theme.textTheme.bodySmall,
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 20),
            Text(strings.aboutBody),
            const SizedBox(height: 20),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: <Widget>[
                    _row(context, strings.osLabel,
                        os == null ? strings.unknown : os.toString()),
                    _row(context, strings.coreLabel,
                        controller.coreVersionText.isEmpty
                            ? strings.unknown
                            : controller.coreVersionText),
                    _row(context, strings.build, AppVersion.build),
                    _row(context, 'Git', AppVersion.gitSha.isEmpty
                        ? strings.notAvailable
                        : AppVersion.gitSha.substring(
                            0, AppVersion.gitSha.length > 12 ? 12 : AppVersion.gitSha.length)),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              children: <Widget>[
                OutlinedButton.icon(
                  onPressed: () => showUpdateDialog(context),
                  icon: const Icon(Icons.system_update_alt),
                  label: Text(strings.checkUpdate),
                ),
                OutlinedButton.icon(
                  onPressed: () => controller.open(AppVersion.repository),
                  icon: const Icon(Icons.open_in_new),
                  label: Text(strings.repository),
                ),
              ],
            ),
          ],
        );
      },
    );
  }

  static Widget _row(BuildContext context, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: <Widget>[
          Text(label, style: Theme.of(context).textTheme.bodySmall),
          const Spacer(),
          Text(value),
        ],
      ),
    );
  }
}
