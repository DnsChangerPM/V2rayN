import 'package:flutter/material.dart';

import '../../core/app_controller.dart';
import '../../core/model/profile.dart';
import '../../core/net/subscription.dart';
import '../../l10n/strings.dart';
import '../dialogs/profile_editor.dart';
import '../dialogs/subscription_dialog.dart';

class ServersPage extends StatelessWidget {
  const ServersPage({super.key, required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    final strings = Strings.of(Localizations.localeOf(context));

    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final profiles = controller.profiles;
        return Scaffold(
          body: Column(
            children: <Widget>[
              _Toolbar(controller: controller, strings: strings),
              const Divider(height: 1),
              if (controller.subscriptions.isNotEmpty)
                _SubscriptionStrip(controller: controller),
              const Divider(height: 1),
              Expanded(
                child: profiles.isEmpty
                    ? _EmptyState(controller: controller, strings: strings)
                    : ListView.separated(
                        padding: const EdgeInsets.all(16),
                        itemCount: profiles.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 8),
                        itemBuilder: (context, index) =>
                            _ServerTile(profile: profiles[index], controller: controller),
                      ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _Toolbar extends StatelessWidget {
  const _Toolbar({required this.controller, required this.strings});

  final AppController controller;
  final Strings strings;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: <Widget>[
          FilledButton.icon(
            onPressed: () async {
              final profile = await showProfileEditor(context, Profile());
              if (profile != null) {
                await controller.addProfile(profile);
              }
            },
            icon: const Icon(Icons.add),
            label: Text(strings.add),
          ),
          OutlinedButton.icon(
            onPressed: () async {
              final count = await controller.importFromClipboard();
              if (!context.mounted) {
                return;
              }
              _snack(
                context,
                count > 0
                    ? '${strings.importClipboardDone}: $count'
                    : strings.importClipboardEmpty,
              );
            },
            icon: const Icon(Icons.content_paste_go),
            label: Text(strings.importClipboard),
          ),
          OutlinedButton.icon(
            onPressed: () => controller.testAllDelays(),
            icon: const Icon(Icons.network_ping),
            label: Text(strings.testAll),
          ),
          OutlinedButton.icon(
            onPressed: () async {
              final result = await showSubscriptionDialog(context);
              if (result != null && context.mounted) {
                await controller.addSubscription(
                  result.url,
                  name: result.name,
                );
              }
            },
            icon: const Icon(Icons.cloud_download_outlined),
            label: Text(strings.addSubscription),
          ),
          OutlinedButton.icon(
            onPressed: () => controller.updateAllSubscriptions(),
            icon: const Icon(Icons.sync),
            label: Text(strings.updateAll),
          ),
        ],
      ),
    );
  }
}

class _SubscriptionStrip extends StatelessWidget {
  const _SubscriptionStrip({required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 64,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        itemCount: controller.subscriptions.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final subscription = controller.subscriptions[index];
          final remaining = subscription.totalBytes != null &&
                  subscription.usedBytes != null
              ? subscription.totalBytes! - subscription.usedBytes!
              : null;
          return Chip(
            avatar: subscription.lastError != null
                ? const Icon(Icons.error_outline, color: Colors.red, size: 18)
                : const Icon(Icons.cloud_done_outlined, size: 18),
            label: Text(
              '${subscription.name} • ${subscription.serverCount}'
              '${remaining != null ? ' • ${_format(remaining)}' : ''}',
            ),
            onDeleted: () async {
              await controller.updateSubscription(subscription);
            },
            deleteIcon: const Icon(Icons.sync, size: 18),
          );
        },
      ),
    );
  }

  static String _format(int bytes) {
    final mb = bytes / (1024 * 1024);
    if (mb >= 1024) {
      return '${(mb / 1024).toStringAsFixed(2)} GB';
    }
    return '${mb.toStringAsFixed(0)} MB';
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.controller, required this.strings});

  final AppController controller;
  final Strings strings;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          const Icon(Icons.dns_outlined, size: 56),
          const SizedBox(height: 12),
          Text(strings.noServers, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 6),
          Text(strings.noServersHint),
        ],
      ),
    );
  }
}

class _ServerTile extends StatelessWidget {
  const _ServerTile({required this.profile, required this.controller});

  final Profile profile;
  final AppController controller;

  @override
  Widget build(BuildContext context) {
    final strings = Strings.of(Localizations.localeOf(context));
    final selected = controller.settings.selectedProfileId == profile.id;
    final active = controller.isConnected &&
        controller.activeProfile?.id == profile.id;

    return Card(
      color: active
          ? Theme.of(context).colorScheme.primaryContainer.withOpacity(0.35)
          : null,
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: _delayColor(profile.lastDelayMs),
          child: Text(
            _delayText(profile.lastDelayMs),
            style: const TextStyle(fontSize: 11, color: Colors.white),
          ),
        ),
        title: Row(
          children: <Widget>[
            Expanded(
              child: Text(
                profile.displayName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (active)
              const Padding(
                padding: EdgeInsetsDirectional.only(start: 8),
                child: Icon(Icons.check_circle, size: 16, color: Colors.green),
              ),
          ],
        ),
        subtitle: Text(
          '${profile.protocol.id.toUpperCase()} • ${profile.transportLabel.toUpperCase()}'
          '${profile.isReality ? ' • REALITY' : (profile.isTls ? ' • TLS' : '')}'
          ' • ${profile.address}:${profile.port}',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        selected: selected,
        onTap: () => controller.selectProfile(profile),
        trailing: Wrap(
          spacing: 4,
          children: <Widget>[
            IconButton(
              tooltip: strings.testDelay,
              icon: const Icon(Icons.network_ping, size: 18),
              onPressed: () => controller.testDelay(profile),
            ),
            IconButton(
              tooltip: strings.copyLink,
              icon: const Icon(Icons.link, size: 18),
              onPressed: () {
                controller.copyToClipboard(profile.toShareLink());
                _snack(context, strings.copyLinkDone);
              },
            ),
            IconButton(
              tooltip: strings.edit,
              icon: const Icon(Icons.edit_outlined, size: 18),
              onPressed: () async {
                final updated =
                    await showProfileEditor(context, profile.copyWith());
                if (updated != null) {
                  await controller.updateProfile(updated);
                }
              },
            ),
            IconButton(
              tooltip: strings.delete,
              icon: const Icon(Icons.delete_outline, size: 18),
              onPressed: () => _confirmDelete(context, profile),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmDelete(BuildContext context, Profile profile) async {
    final strings = Strings.of(Localizations.localeOf(context));
    final ok = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: Text(strings.deleteTitle),
            content: Text(strings.deleteMessage),
            actions: <Widget>[
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: Text(strings.cancel),
              ),
              FilledButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: Text(strings.confirm),
              ),
            ],
          ),
        ) ??
        false;
    if (ok) {
      await controller.removeProfile(profile);
    }
  }

  static Color _delayColor(int? delay) {
    if (delay == null) {
      return Colors.grey;
    }
    if (delay < 300) {
      return Colors.green;
    }
    if (delay < 800) {
      return Colors.orange;
    }
    return Colors.red;
  }

  static String _delayText(int? delay) =>
      delay == null ? '?' : (delay > 9999 ? '9999+' : '$delay');
}

void _snack(BuildContext context, String message) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message)));
}

/// Convenience used by [SubscriptionResult] imports.
typedef SubscriptionDialogResult = ({String url, String? name});
