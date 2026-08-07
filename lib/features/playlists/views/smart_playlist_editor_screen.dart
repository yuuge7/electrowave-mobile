import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/database_provider.dart';
import '../models/smart_playlist.dart';
import '../providers/playlist_providers.dart';

/// Rule editor for a smart playlist. [smartPlaylistId] null creates a new one.
class SmartPlaylistEditorScreen extends ConsumerStatefulWidget {
  const SmartPlaylistEditorScreen({super.key, this.smartPlaylistId});

  final int? smartPlaylistId;

  @override
  ConsumerState<SmartPlaylistEditorScreen> createState() =>
      _SmartPlaylistEditorScreenState();
}

class _SmartPlaylistEditorScreenState
    extends ConsumerState<SmartPlaylistEditorScreen> {
  final _nameController = TextEditingController();
  final _limitController = TextEditingController();

  SmartPlaylistDefinition _definition = const SmartPlaylistDefinition(
    rules: [
      SmartRule(
        field: SmartField.playCount,
        operator: SmartOperator.greaterThan,
      ),
    ],
  );

  /// Set once the existing playlist has been read, so the live row rebuilding
  /// doesn't overwrite edits in progress.
  bool _loaded = false;

  /// Debounced copy of the definition: the preview query runs off this rather
  /// than off every keystroke.
  String _previewKey = const SmartPlaylistDefinition().encode();
  Timer? _previewDebounce;

  @override
  void dispose() {
    _previewDebounce?.cancel();
    _nameController.dispose();
    _limitController.dispose();
    super.dispose();
  }

  void _update(SmartPlaylistDefinition next) {
    setState(() => _definition = next);
    _previewDebounce?.cancel();
    _previewDebounce = Timer(const Duration(milliseconds: 400), () {
      if (mounted) setState(() => _previewKey = _definition.encode());
    });
  }

  Future<void> _save() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(content: Text('Give the playlist a name')),
        );
      return;
    }
    final db = ref.read(databaseProvider);
    final navigator = Navigator.of(context);
    final id = widget.smartPlaylistId;
    if (id == null) {
      await db.createSmartPlaylist(name, _definition.encode());
    } else {
      await db.updateSmartPlaylist(id, name, _definition.encode());
    }
    navigator.pop();
  }

  @override
  Widget build(BuildContext context) {
    final id = widget.smartPlaylistId;
    if (id != null && !_loaded) {
      final row = ref.watch(smartPlaylistProvider(id)).value;
      if (row != null) {
        _loaded = true;
        _nameController.text = row.name;
        _definition = SmartPlaylistDefinition.decode(row.rulesJson);
        _limitController.text = _definition.limit?.toString() ?? '';
        _previewKey = _definition.encode();
      }
    }

    final preview = ref.watch(smartPlaylistPreviewProvider(_previewKey));

    return Scaffold(
      appBar: AppBar(
        title: Text(id == null ? 'New smart playlist' : 'Edit smart playlist'),
        actions: [
          IconButton(
            icon: const Icon(Icons.check),
            tooltip: 'Save',
            onPressed: _save,
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          TextField(
            controller: _nameController,
            decoration: const InputDecoration(
              labelText: 'Name',
              hintText: 'e.g. Neglected favourites',
            ),
            textCapitalization: TextCapitalization.sentences,
          ),
          const SizedBox(height: 20),
          SegmentedButton<bool>(
            segments: const [
              ButtonSegment(value: true, label: Text('Match all rules')),
              ButtonSegment(value: false, label: Text('Match any rule')),
            ],
            selected: {_definition.matchAll},
            onSelectionChanged: (selection) =>
                _update(_definition.copyWith(matchAll: selection.first)),
          ),
          const SizedBox(height: 16),
          for (var index = 0; index < _definition.rules.length; index++)
            _RuleCard(
              key: ValueKey(index),
              rule: _definition.rules[index],
              onChanged: (rule) {
                final rules = List.of(_definition.rules)..[index] = rule;
                _update(_definition.copyWith(rules: rules));
              },
              onRemoved: () {
                final rules = List.of(_definition.rules)..removeAt(index);
                _update(_definition.copyWith(rules: rules));
              },
            ),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              icon: const Icon(Icons.add),
              label: const Text('Add rule'),
              onPressed: () => _update(
                _definition.copyWith(
                  rules: [
                    ..._definition.rules,
                    const SmartRule(
                      field: SmartField.genre,
                      operator: SmartOperator.contains,
                    ),
                  ],
                ),
              ),
            ),
          ),
          const Divider(height: 32),
          DropdownButtonFormField<SmartSort>(
            initialValue: _definition.sort,
            decoration: const InputDecoration(labelText: 'Sort by'),
            items: [
              for (final sort in SmartSort.values)
                DropdownMenuItem(value: sort, child: Text(sort.label)),
            ],
            onChanged: (sort) =>
                sort == null ? null : _update(_definition.copyWith(sort: sort)),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Descending'),
            value: _definition.descending,
            onChanged: _definition.sort == SmartSort.random
                ? null
                : (value) => _update(_definition.copyWith(descending: value)),
          ),
          TextField(
            controller: _limitController,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: const InputDecoration(
              labelText: 'Limit',
              hintText: 'No limit',
              helperText: 'Keep only the first N tracks after sorting',
            ),
            onChanged: (value) {
              final limit = int.tryParse(value.trim());
              _update(
                limit == null || limit <= 0
                    ? _definition.copyWith(clearLimit: true)
                    : _definition.copyWith(limit: limit),
              );
            },
          ),
          const SizedBox(height: 24),
          Text(
            switch (preview) {
              AsyncData(:final value) =>
                'Matches ${value.length} track${value.length == 1 ? '' : 's'} right now',
              AsyncError(:final error) => 'Rule error: $error',
              _ => 'Counting…',
            },
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Theme.of(context).colorScheme.primary,
            ),
          ),
        ],
      ),
    );
  }
}

class _RuleCard extends StatelessWidget {
  const _RuleCard({
    super.key,
    required this.rule,
    required this.onChanged,
    required this.onRemoved,
  });

  final SmartRule rule;
  final ValueChanged<SmartRule> onChanged;
  final VoidCallback onRemoved;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 4, 4, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: DropdownButton<SmartField>(
                    value: rule.field,
                    isExpanded: true,
                    underline: const SizedBox.shrink(),
                    items: [
                      for (final field in SmartField.values)
                        DropdownMenuItem(
                          value: field,
                          child: Text(field.label),
                        ),
                    ],
                    onChanged: (field) => field == null
                        ? null
                        : onChanged(rule.copyWith(field: field, value: '')),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  tooltip: 'Remove rule',
                  onPressed: onRemoved,
                ),
              ],
            ),
            Row(
              children: [
                Expanded(
                  child: DropdownButton<SmartOperator>(
                    value: rule.operator,
                    isExpanded: true,
                    underline: const SizedBox.shrink(),
                    items: [
                      for (final operator in rule.field.operators)
                        DropdownMenuItem(
                          value: operator,
                          child: Text(operator.label),
                        ),
                    ],
                    onChanged: (operator) => operator == null
                        ? null
                        : onChanged(rule.copyWith(operator: operator)),
                  ),
                ),
                if (rule.operator.takesValue) ...[
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextFormField(
                      // Rebuilt from scratch when the field or operator
                      // changes, so the keyboard type and cleared value match.
                      key: ValueKey('${rule.field.name}:${rule.operator.name}'),
                      initialValue: rule.value,
                      keyboardType: rule.field.kind == SmartFieldKind.text
                          ? TextInputType.text
                          : TextInputType.number,
                      decoration: InputDecoration(
                        isDense: true,
                        hintText: switch (rule.field.kind) {
                          SmartFieldKind.date => 'days',
                          SmartFieldKind.number => 'value',
                          _ => 'text',
                        },
                      ),
                      onChanged: (value) =>
                          onChanged(rule.copyWith(value: value)),
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}
