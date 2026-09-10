/// Log viewer: level filter, search, auto-scroll.
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n/app_localizations.dart';
import '../logging/log_service.dart';
import '../state/log_provider.dart';

class LogsScreen extends StatefulWidget {
  const LogsScreen({super.key});

  @override
  State<LogsScreen> createState() => _LogsScreenState();
}

class _LogsScreenState extends State<LogsScreen> {
  final ScrollController _scroll = ScrollController();
  bool _follow = true;

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final logs = context.watch<LogProvider>();
    if (_follow && _scroll.hasClients) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scroll.hasClients) {
          _scroll.jumpTo(_scroll.position.maxScrollExtent);
        }
      });
    }
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              SizedBox(
                width: 280,
                child: TextField(
                  decoration: InputDecoration(
                    hintText: context.l10n('logsSearch'),
                    prefixIcon: const Icon(Icons.search),
                  ),
                  onChanged: logs.setQuery,
                ),
              ),
              DropdownButton<LogLevel?>(
                value: logs.minLevel,
                hint: Text(context.l10n('logsLevel')),
                items: [
                  DropdownMenuItem<LogLevel?>(
                    child: Text(context.l10n('logsLevel')),
                  ),
                  for (final level in LogLevel.values)
                    DropdownMenuItem(
                      value: level,
                      child: Text(level.name),
                    ),
                ],
                onChanged: logs.setMinLevel,
              ),
              const Spacer(),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Checkbox(
                    value: _follow,
                    onChanged: (value) =>
                        setState(() => _follow = value ?? true),
                  ),
                  const Text('⇣'),
                ],
              ),
            ],
          ),
          const SizedBox(height: 12),
          Expanded(
            child: Card(
              child: logs.entries.isEmpty
                  ? Center(child: Text(context.l10n('logsSearch')))
                  : ListView.builder(
                      controller: _scroll,
                      itemCount: logs.entries.length,
                      itemBuilder: (context, index) {
                        final entry = logs.entries[index];
                        return _LogRow(entry: entry);
                      },
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

class _LogRow extends StatelessWidget {
  const _LogRow({required this.entry});

  final LogEntry entry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = switch (entry.level) {
      LogLevel.error => theme.colorScheme.error,
      LogLevel.warning => Colors.amber.shade800,
      LogLevel.debug => theme.colorScheme.onSurfaceVariant,
      LogLevel.info => null,
    };
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
      child: SelectableText(
        entry.toLine(),
        textDirection: TextDirection.ltr,
        style: theme.textTheme.bodySmall
            ?.copyWith(fontFamily: 'Consolas', color: color),
      ),
    );
  }
}
