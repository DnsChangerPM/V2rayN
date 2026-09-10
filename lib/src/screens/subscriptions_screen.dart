/// Subscriptions: list, CRUD, manual/auto refresh with honest statuses.
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n/app_localizations.dart';
import '../models/subscription.dart';
import '../state/subscription_provider.dart';
import '../utils/validators.dart';
import '../widgets/empty_state.dart';

class SubscriptionsScreen extends StatelessWidget {
  const SubscriptionsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final subscriptions = context.watch<SubscriptionProvider>();
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Text(
                context.l10n('subscriptionsTitle'),
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const Spacer(),
              FilledButton.tonalIcon(
                onPressed: subscriptions.subscriptions.isEmpty
                    ? null
                    : () => subscriptions.refreshAll(),
                icon: const Icon(Icons.refresh),
                label: Text(context.l10n('refreshAll')),
              ),
              const SizedBox(width: 8),
              FilledButton.icon(
                onPressed: () => _showEditDialog(context, null),
                icon: const Icon(Icons.add),
                label: Text(context.l10n('addSubscription')),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Expanded(
            child: subscriptions.subscriptions.isEmpty
                ? EmptyState(
                    icon: Icons.rss_feed_outlined,
                    message: context.l10n('subscriptionsTitle'),
                    action: FilledButton.tonalIcon(
                      onPressed: () => _showEditDialog(context, null),
                      icon: const Icon(Icons.add),
                      label: Text(context.l10n('addSubscription')),
                    ),
                  )
                : ListView.separated(
                    itemCount: subscriptions.subscriptions.length,
                    separatorBuilder: (context, index) => const SizedBox(height: 8),
                    itemBuilder: (context, index) => _SubscriptionCard(
                      subscription: subscriptions.subscriptions[index],
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

class _SubscriptionCard extends StatelessWidget {
  const _SubscriptionCard({required this.subscription});

  final Subscription subscription;

  @override
  Widget build(BuildContext context) {
    final provider = context.read<SubscriptionProvider>();
    final theme = Theme.of(context);
    final refreshing =
        subscription.lastStatus == SubscriptionStatus.refreshing;
    final updated = subscription.lastUpdatedAt;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    subscription.name,
                    style: theme.textTheme.titleMedium,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                _StatusChip(subscription: subscription),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              maskUrl(subscription.url),
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
              textDirection: TextDirection.ltr,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 8),
            Text(
              '${context.l10n('lastUpdated')}: '
              '${updated == null ? context.l10n('never') : updated.toLocal().toString().substring(0, 16)} · '
              '${subscription.profileCount} ${context.l10n('profilesCount')}',
              style: theme.textTheme.bodySmall,
            ),
            if (subscription.lastStatus == SubscriptionStatus.error &&
                subscription.lastError.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                '${context.l10n('subscriptionError')}: ${subscription.lastError}',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.error,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],
            const SizedBox(height: 8),
            Row(
              children: [
                TextButton.icon(
                  onPressed: refreshing
                      ? null
                      : () => provider.refresh(subscription.id),
                  icon: refreshing
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child:
                              CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.refresh, size: 18),
                  label: Text(context.l10n('refresh')),
                ),
                TextButton.icon(
                  onPressed: () =>
                      _showEditDialog(context, subscription),
                  icon: const Icon(Icons.edit_outlined, size: 18),
                  label: Text(context.l10n('edit')),
                ),
                TextButton.icon(
                  onPressed: () => _confirmDelete(context, provider),
                  icon: const Icon(Icons.delete_outline, size: 18),
                  label: Text(context.l10n('delete')),
                ),
                const Spacer(),
                Switch(
                  value: subscription.enabled,
                  onChanged: (value) => provider.update(
                    subscription.copyWith(enabled: value),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmDelete(
      BuildContext context, SubscriptionProvider provider,) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(context.l10n('delete')),
        content: Text(context.l10n('deleteSubscriptionConfirm')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(context.l10n('cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(context.l10n('delete')),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await provider.remove(subscription.id);
    }
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.subscription});

  final Subscription subscription;

  @override
  Widget build(BuildContext context) {
    final (color, label) = switch (subscription.lastStatus) {
      SubscriptionStatus.ok => (Colors.green, '✓'),
      SubscriptionStatus.error => (Colors.red, '!'),
      SubscriptionStatus.refreshing => (Colors.amber.shade700, '…'),
      SubscriptionStatus.idle => (Colors.grey, '–'),
    };
    return Container(
      width: 28,
      height: 28,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        // ignore: deprecated_member_use (withOpacity is correct on Flutter 3.19)
        color: color.withOpacity(0.15),
        shape: BoxShape.circle,
      ),
      child: Text(label,
          style: TextStyle(color: color, fontWeight: FontWeight.bold),),
    );
  }
}

Future<void> _showEditDialog(
    BuildContext context, Subscription? existing,) async {
  final nameController =
      TextEditingController(text: existing?.name ?? '');
  final urlController = TextEditingController(text: existing?.url ?? '');
  var autoRefresh = existing?.autoRefresh ?? false;
  final intervalController = TextEditingController(
      text: '${existing?.refreshIntervalMinutes ?? 240}',);
  var allowInsecure = existing?.allowInsecure ?? false;

  final saved = await showDialog<bool>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setState) => AlertDialog(
        title: Text(context.l10n(
            existing == null ? 'addSubscription' : 'edit',),),
        content: SizedBox(
          width: 460,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameController,
                decoration: InputDecoration(
                    labelText: context.l10n('subscriptionName'),),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: urlController,
                decoration: InputDecoration(
                    labelText: context.l10n('subscriptionUrl'),),
                textDirection: TextDirection.ltr,
                maxLines: 2,
              ),
              SwitchListTile(
                title: Text(context.l10n('autoRefresh')),
                value: autoRefresh,
                onChanged: (value) => setState(() => autoRefresh = value),
              ),
              TextField(
                controller: intervalController,
                decoration: InputDecoration(
                    labelText: context.l10n('refreshInterval'),),
                keyboardType: TextInputType.number,
                textDirection: TextDirection.ltr,
              ),
              SwitchListTile(
                title: Text(context.l10n('allowInsecureCerts')),
                value: allowInsecure,
                onChanged: (value) =>
                    setState(() => allowInsecure = value),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(context.l10n('cancel')),
          ),
          FilledButton(
            onPressed: () {
              if (!isValidUrl(urlController.text)) return;
              Navigator.pop(context, true);
            },
            child: Text(context.l10n('save')),
          ),
        ],
      ),
    ),
  );
  if (saved != true || !context.mounted) return;
  final provider = context.read<SubscriptionProvider>();
  final interval =
      int.tryParse(intervalController.text.trim()) ?? 240;
  if (existing == null) {
    final subscription = await provider.add(
      name: nameController.text,
      url: urlController.text,
      autoRefresh: autoRefresh,
      refreshIntervalMinutes: interval.clamp(5, 24 * 60),
    );
    await provider.refresh(subscription.id);
  } else {
    await provider.update(existing.copyWith(
      name: nameController.text.trim().isEmpty
          ? maskUrl(urlController.text.trim())
          : nameController.text.trim(),
      url: urlController.text.trim(),
      autoRefresh: autoRefresh,
      refreshIntervalMinutes: interval.clamp(5, 24 * 60),
      allowInsecure: allowInsecure,
    ),);
  }
}
