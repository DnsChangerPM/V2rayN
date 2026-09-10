/// Profiles: searchable/sortable/grouped list, CRUD, import, best-profile.
library;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../l10n/app_localizations.dart';
import '../models/profile.dart';
import '../profiles/uri_codecs.dart';
import '../state/connection_provider.dart';
import '../state/profile_provider.dart';
import '../utils/formatters.dart';
import '../widgets/empty_state.dart';

class ProfilesScreen extends StatelessWidget {
  const ProfilesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final profiles = context.watch<ProfileProvider>();
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Toolbar(profiles: profiles),
          const SizedBox(height: 12),
          _GroupBar(profiles: profiles),
          const SizedBox(height: 12),
          Expanded(
            child: profiles.visible.isEmpty
                ? EmptyState(
                    icon: Icons.list_alt_outlined,
                    message: context.l10n('noProfiles'),
                    action: FilledButton.tonalIcon(
                      onPressed: () => _showImportDialog(context),
                      icon: const Icon(Icons.add),
                      label: Text(context.l10n('importProfile')),
                    ),
                  )
                : _ProfileList(profiles: profiles),
          ),
        ],
      ),
    );
  }
}

class _Toolbar extends StatelessWidget {
  const _Toolbar({required this.profiles});

  final ProfileProvider profiles;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        SizedBox(
          width: 320,
          child: TextField(
            decoration: InputDecoration(
              hintText: context.l10n('searchHint'),
              prefixIcon: const Icon(Icons.search),
              suffixIcon: profiles.search.isEmpty
                  ? null
                  : IconButton(
                      icon: const Icon(Icons.clear),
                      onPressed: () => profiles.setSearch(''),
                    ),
            ),
            onChanged: profiles.setSearch,
          ),
        ),
        PopupMenuButton<ProfileSortKey>(
          tooltip: context.l10n('sortBy'),
          icon: const Icon(Icons.sort),
          onSelected: (key) => profiles.setSort(
            key,
            profiles.sortKey == key &&
                    profiles.direction == SortDirection.ascending
                ? SortDirection.descending
                : SortDirection.ascending,
          ),
          itemBuilder: (context) => [
            for (final key in ProfileSortKey.values)
              PopupMenuItem(
                value: key,
                child: Text(context.l10n(switch (key) {
                  ProfileSortKey.name => 'sortName',
                  ProfileSortKey.latency => 'sortLatency',
                  ProfileSortKey.speed => 'sortSpeed',
                  ProfileSortKey.lastUsed => 'sortLastUsed',
                  ProfileSortKey.favorite => 'sortFavorite',
                },),),
              ),
          ],
        ),
        const Spacer(),
        FilledButton.tonalIcon(
          onPressed:
              profiles.ranking ? null : () => _runBestProfile(context),
          icon: profiles.ranking
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.auto_awesome),
          label: Text(context.l10n('bestProfile')),
        ),
        FilledButton.icon(
          onPressed: () => _showImportDialog(context),
          icon: const Icon(Icons.add),
          label: Text(context.l10n('importProfile')),
        ),
      ],
    );
  }

  Future<void> _runBestProfile(BuildContext context) async {
    final provider = context.read<ProfileProvider>();
    final ranking = await provider.rankBest();
    if (!context.mounted) return;
    if (ranking.isEmpty || !ranking.first.reachable) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l10n('connectionError'))),
      );
      return;
    }
    await provider.selectProfile(ranking.first.profile.id);
  }
}

class _GroupBar extends StatelessWidget {
  const _GroupBar({required this.profiles});

  final ProfileProvider profiles;

  @override
  Widget build(BuildContext context) {
    final chips = <Widget>[
      _groupChip(context, BuiltinGroups.all, context.l10n('allGroups')),
      _groupChip(
          context, BuiltinGroups.favorites, context.l10n('favorites'),),
    ];
    for (final group in profiles.groups) {
      final label = group.isBuiltin
          ? context.l10n(switch (group.id) {
              BuiltinGroups.gaming => 'groupGaming',
              BuiltinGroups.work => 'groupWork',
              BuiltinGroups.personal => 'groupPersonal',
              _ => 'allGroups',
            })
          : group.name;
      chips.add(_groupChip(context, group.id, label));
    }
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          ...chips,
          IconButton(
            tooltip: context.l10n('addProfile'),
            icon: const Icon(Icons.create_new_folder_outlined),
            onPressed: () => _showAddGroupDialog(context),
          ),
        ],
      ),
    );
  }

  Widget _groupChip(BuildContext context, String id, String label) {
    final selected = profiles.groupId == id;
    return Padding(
      padding: const EdgeInsetsDirectional.only(end: 8),
      child: ChoiceChip(
        label: Text(label),
        selected: selected,
        onSelected: (_) => profiles.setGroup(id),
      ),
    );
  }

  Future<void> _showAddGroupDialog(BuildContext context) async {
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(context.l10n('addProfile')),
        content: TextField(
          controller: controller,
          decoration: InputDecoration(labelText: context.l10n('profileName')),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(context.l10n('cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: Text(context.l10n('save')),
          ),
        ],
      ),
    );
    if (name != null && name.isNotEmpty && context.mounted) {
      await context.read<ProfileProvider>().addGroup(name);
    }
  }
}

class _ProfileList extends StatelessWidget {
  const _ProfileList({required this.profiles});

  final ProfileProvider profiles;

  @override
  Widget build(BuildContext context) {
    final activeId = profiles.activeProfileId;
    return Card(
      child: ListView.separated(
        itemCount: profiles.visible.length,
        separatorBuilder: (_, _) => const Divider(height: 1),
        itemBuilder: (context, index) {
          final profile = profiles.visible[index];
          final selected = profile.id == activeId;
          return ListTile(
            selected: selected,
            selectedTileColor:
                Theme.of(context).colorScheme.secondaryContainer,
            leading: Icon(
              profile.isFavorite ? Icons.star : Icons.star_border,
              color: profile.isFavorite ? Colors.amber.shade700 : null,
            ),
            title: Text(profile.name, overflow: TextOverflow.ellipsis),
            subtitle: Text(
              '${profile.protocol.name} · ${profile.address}:${profile.port} · '
              '${formatLatency(profile.lastLatencyMs)}',
              textDirection: TextDirection.ltr,
              overflow: TextOverflow.ellipsis,
            ),
            trailing: _ProfileMenu(profile: profile),
            onTap: () => profiles.selectProfile(profile.id),
            onLongPress: () => profiles.toggleFavorite(profile.id),
          );
        },
      ),
    );
  }
}

class _ProfileMenu extends StatelessWidget {
  const _ProfileMenu({required this.profile});

  final ProxyProfile profile;

  @override
  Widget build(BuildContext context) {
    final profiles = context.read<ProfileProvider>();
    return PopupMenuButton<String>(
      onSelected: (action) =>
          _handleAction(context, profiles, action),
      itemBuilder: (context) => [
        PopupMenuItem(
            value: 'connect', child: Text(context.l10n('connect')),),
        PopupMenuItem(
            value: 'favorite',
            child: Text(context.l10n(
                profile.isFavorite ? 'unfavorite' : 'favorite',),),),
        PopupMenuItem(value: 'edit', child: Text(context.l10n('edit'))),
        PopupMenuItem(
            value: 'duplicate', child: Text(context.l10n('duplicate')),),
        PopupMenuItem(
            value: 'copy', child: Text(context.l10n('copyLink')),),
        PopupMenuItem(
            value: 'delete', child: Text(context.l10n('delete')),),
      ],
    );
  }

  Future<void> _handleAction(BuildContext context,
      ProfileProvider profiles, String action,) async {
    switch (action) {
      case 'connect':
        await profiles.selectProfile(profile.id);
        if (context.mounted) {
          await context.read<ConnectionProvider>().connect();
        }
      case 'favorite':
        await profiles.toggleFavorite(profile.id);
      case 'edit':
        if (context.mounted) _showEditorDialog(context, profiles, profile);
      case 'duplicate':
        await profiles.duplicate(profile.id);
      case 'copy':
        final link = encodeShareLink(profile);
        if (link.isNotEmpty) {
          await Clipboard.setData(ClipboardData(text: link));
        }
      case 'delete':
        if (!context.mounted) return;
        final confirmed = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: Text(context.l10n('delete')),
            content: Text(context.l10n('deleteProfileConfirm')),
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
          await profiles.remove(profile.id);
        }
    }
  }

  void _showEditorDialog(BuildContext context, ProfileProvider profiles,
      ProxyProfile profile,) {
    showDialog(
      context: context,
      builder: (context) => _ProfileEditorDialog(profile: profile),
    );
  }
}

class _ProfileEditorDialog extends StatefulWidget {
  const _ProfileEditorDialog({required this.profile});

  final ProxyProfile profile;

  @override
  State<_ProfileEditorDialog> createState() => _ProfileEditorDialogState();
}

class _ProfileEditorDialogState extends State<_ProfileEditorDialog> {
  late final TextEditingController _name;
  late final TextEditingController _address;
  late final TextEditingController _port;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: widget.profile.name);
    _address = TextEditingController(text: widget.profile.address);
    _port = TextEditingController(text: '${widget.profile.port}');
  }

  @override
  void dispose() {
    _name.dispose();
    _address.dispose();
    _port.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(context.l10n('edit')),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _name,
              decoration: InputDecoration(
                  labelText: context.l10n('profileName'),),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _address,
              decoration: InputDecoration(
                  labelText: context.l10n('profileAddress'),),
              textDirection: TextDirection.ltr,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _port,
              decoration:
                  InputDecoration(labelText: context.l10n('profilePort')),
              keyboardType: TextInputType.number,
              textDirection: TextDirection.ltr,
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(context.l10n('cancel')),
        ),
        FilledButton(
          onPressed: () async {
            final port = int.tryParse(_port.text.trim()) ?? 0;
            if (port < 1 || port > 65535) return;
            await context.read<ProfileProvider>().update(
                  widget.profile.copyWith(
                    name: _name.text.trim(),
                    address: _address.text.trim(),
                    port: port,
                  ),
                );
            if (context.mounted) Navigator.pop(context);
          },
          child: Text(context.l10n('save')),
        ),
      ],
    );
  }
}

Future<void> _showImportDialog(BuildContext context) async {
  final controller = TextEditingController();
  final data = await Clipboard.getData(Clipboard.kTextPlain);
  // Don't leave pasted secrets on the clipboard (best effort).
  try {
    await Clipboard.setData(const ClipboardData(text: ''));
  } on Object {
    // Clipboard clearing is a courtesy, not a guarantee.
  }
  if (data?.text?.contains('://') == true) {
    controller.text = data!.text!;
  }
  if (!context.mounted) return;
  final profiles = context.read<ProfileProvider>();
  await showDialog(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(context.l10n('importText')),
      content: SizedBox(
        width: 520,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: controller,
              decoration: InputDecoration(
                  hintText: context.l10n('pasteHere'),),
              maxLines: 8,
              textDirection: TextDirection.ltr,
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                TextButton.icon(
                  onPressed: () async {
                    final result =
                        await FilePicker.platform.pickFiles(
                      type: FileType.custom,
                      allowedExtensions: ['png', 'jpg', 'jpeg', 'bmp', 'txt', 'json'],
                      withData: true,
                    );
                    final file = result?.files.firstOrNull;
                    final bytes = file?.bytes;
                    if (bytes == null) return;
                    if (file!.extension == 'txt' ||
                        file.extension == 'json') {
                      controller.text =
                          String.fromCharCodes(bytes);
                    } else {
                      final importResult = await profiles.importQrImage(
                          bytes,);
                      if (context.mounted) {
                        Navigator.pop(context);
                        _showImportSummary(
                            context,
                            imported: importResult.profiles.length,
                            errors: importResult.errors.length,);
                      }
                    }
                  },
                  icon: const Icon(Icons.qr_code),
                  label: Text(context.l10n('importQr')),
                ),
              ],
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(context.l10n('cancel')),
        ),
        FilledButton(
          onPressed: () async {
            final result =
                await profiles.importText(controller.text);
            if (context.mounted) {
              Navigator.pop(context);
              _showImportSummary(
                context,
                imported: result.profiles.length,
                errors: result.errors.length,
              );
            }
          },
          child: Text(context.l10n('importProfile')),
        ),
      ],
    ),
  );
}

void _showImportSummary(BuildContext context,
    {required int imported, required int errors,}) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(
        '$imported ${context.l10n('importedCount')}, '
        '$errors ${context.l10n('importErrors')}',
      ),
    ),
  );
}

extension<T> on List<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
