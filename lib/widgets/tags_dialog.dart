import 'package:flutter/material.dart';

import '../core/api/api_exception.dart';
import '../core/theme/app_text.dart';
import '../models/common.dart';
import '../models/meta.dart';
import 'app_dialog.dart';
import 'app_sheet.dart';
import 'selection_check.dart';

/// Loads the tags currently applied to the ticket/task (`GET /{obj}/{id}/tags`).
typedef AppliedTagsLoader = Future<List<Tag>> Function();

/// Loads the shared tag vocabulary (`GET /meta/tags`).
typedef SharedTagsLoader = Future<List<MetaItem>> Function();

/// Applies or clears one tag, returning the object's new tag list.
typedef TagMutation = Future<List<Tag>> Function(int tagId);

/// **Tags** dialog: the whole shared tag list in one multi-select, with the
/// tags already on the object pre-ticked, and a single **Save** that commits
/// the difference.
///
/// It replaces the earlier add-one-at-a-time sheet (an "Add tag" button that
/// opened a second picker dialog on top of the first, plus chips that deleted
/// instantly). That shape had no save step at all, so a removal looked unsaved
/// even though it had already gone to the server, and a rejected add reported
/// nothing the agent could act on.
///
/// Resolves to the object's tag list when the agent saves, or `null` when the
/// dialog is dismissed without saving. Shared by the ticket and task detail
/// screens so the two flows stay identical.
Future<List<Tag>?> showTagsDialog(
  BuildContext context, {
  required AppliedTagsLoader loadApplied,
  required SharedTagsLoader loadShared,
  required TagMutation addTag,
  required TagMutation removeTag,
}) {
  return showDialog<List<Tag>>(
    context: context,
    builder: (_) => _TagsDialog(
      loadApplied: loadApplied,
      loadShared: loadShared,
      addTag: addTag,
      removeTag: removeTag,
    ),
  );
}

class _TagsDialog extends StatefulWidget {
  const _TagsDialog({
    required this.loadApplied,
    required this.loadShared,
    required this.addTag,
    required this.removeTag,
  });

  final AppliedTagsLoader loadApplied;
  final SharedTagsLoader loadShared;
  final TagMutation addTag;
  final TagMutation removeTag;

  @override
  State<_TagsDialog> createState() => _TagsDialogState();
}

class _TagsDialogState extends State<_TagsDialog> {
  final _searchCtrl = TextEditingController();

  /// Every tag the agent can tick: the shared list, plus any tag already on the
  /// object that the shared list doesn't carry. Tags are department-scoped
  /// server-side (`Tag::visibilityQ`), so a tag applied by another team can sit
  /// on the object without being offered — it still has to be removable.
  List<MetaItem> _options = const [];

  /// The object's tags as the server last reported them.
  List<Tag> _applied = const [];

  Set<int> _saved = const {}; // ids the server has
  Set<int> _picked = {}; // ids ticked in this dialog

  bool _loading = true;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final List<Tag> applied;
    try {
      applied = await widget.loadApplied();
    } on ApiException catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = _reason(e, "Could not load this item's tags");
        });
      }
      return;
    }

    List<MetaItem> shared = const [];
    String? sharedError;
    try {
      shared = await widget.loadShared();
    } on ApiException catch (e) {
      sharedError = _reason(e, 'Could not load the shared tag list');
    }

    if (!mounted) return;
    setState(() {
      _applied = applied;
      _saved = applied.map((t) => t.id).toSet();
      _picked = {..._saved};
      _options = _merge(shared, applied);
      _loading = false;
      _error = sharedError;
    });
  }

  /// Shared list first (the server orders it by name), then any
  /// applied-but-unlisted tag appended so it can still be unticked.
  static List<MetaItem> _merge(List<MetaItem> shared, List<Tag> applied) {
    final ids = shared.map((m) => m.id).toSet();
    return [
      ...shared,
      for (final t in applied)
        if (!ids.contains(t.id))
          MetaItem(id: t.id, name: t.name, color: t.color),
    ];
  }

  bool get _dirty => !_setEquals(_picked, _saved);

  static bool _setEquals(Set<int> a, Set<int> b) =>
      a.length == b.length && a.containsAll(b);

  bool get _searchable => _options.length > 8;

  List<MetaItem> get _filtered {
    final query = _searchCtrl.text.trim().toLowerCase();
    if (query.isEmpty) return _options;
    return _options
        .where((item) => item.name.toLowerCase().contains(query))
        .toList();
  }

  void _toggle(int id) {
    setState(() {
      if (!_picked.remove(id)) _picked.add(id);
      _error = null;
    });
  }

  String _nameFor(int id) {
    for (final option in _options) {
      if (option.id == id) return option.name;
    }
    return 'tag';
  }

  /// Commits the difference — removals first, then additions. Every call
  /// returns the object's full tag list, so the last one that succeeded is the
  /// truth to close on.
  Future<void> _save() async {
    if (!_dirty) {
      Navigator.pop(context, _applied);
      return;
    }
    final toRemove = _saved.difference(_picked).toList();
    final toAdd = _picked.difference(_saved).toList();

    setState(() {
      _saving = true;
      _error = null;
    });

    var latest = _applied;
    final failures = <String>[];
    for (final id in toRemove) {
      try {
        latest = await widget.removeTag(id);
      } on ApiException catch (e) {
        failures.add(_reason(e, 'Could not remove "${_nameFor(id)}"'));
      }
    }
    for (final id in toAdd) {
      try {
        latest = await widget.addTag(id);
      } on ApiException catch (e) {
        failures.add(_reason(e, 'Could not add "${_nameFor(id)}"'));
      }
    }

    if (!mounted) return;
    if (failures.isEmpty) {
      Navigator.pop(context, latest);
      return;
    }
    // Something was rejected: resync to what actually stuck so the ticks match
    // the server, and keep the dialog open with the reason.
    setState(() {
      _saving = false;
      _applied = latest;
      _saved = latest.map((t) => t.id).toSet();
      _picked = {..._saved};
      _error = failures.join('\n');
    });
  }

  /// A message worth showing. The API answers a rejected tag with a blank
  /// message and the detail in `fields` (`{'tag': 'Unknown tag, …'}`), which
  /// surfaced as an empty toast — i.e. as nothing happening at all.
  static String _reason(ApiException e, String fallback) {
    final message = e.message.trim();
    if (message.isNotEmpty) return message;
    final fields = e.fields.values
        .map((v) => v.trim())
        .where((v) => v.isNotEmpty);
    if (fields.isNotEmpty) return fields.join('\n');
    return fallback;
  }

  @override
  Widget build(BuildContext context) {
    return AppDialog(
      title: 'Tags',
      actionLabel: 'Save',
      actionBusy: _saving,
      actionEnabled: !_loading && _dirty,
      onAction: _save,
      child: _loading
          ? const Padding(
              padding: EdgeInsets.all(16),
              child: Center(child: CircularProgressIndicator()),
            )
          : Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (_searchable) ...[
                  SheetSearchField(
                    controller: _searchCtrl,
                    onChanged: (_) => setState(() {}),
                    onClear: () => setState(() {}),
                  ),
                  const SizedBox(height: 12),
                ],
                _body(context),
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  AppText.paraText(
                    context,
                    _error!,
                    color: Theme.of(context).colorScheme.error,
                  ),
                ],
              ],
            ),
    );
  }

  Widget _body(BuildContext context) {
    if (_options.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: AppText.subText(
          context,
          'No tags are available for your department. Ask an administrator or '
          'your department manager to add one.',
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      );
    }
    final items = _filtered;
    if (items.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 20),
        child: AppText.subText(context, 'No results found'),
      );
    }
    return ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.4,
      ),
      child: ListView(
        shrinkWrap: true,
        children: [for (final item in items) _row(context, item)],
      ),
    );
  }

  Widget _row(BuildContext context, MetaItem item) {
    final scheme = Theme.of(context).colorScheme;
    final selected = _picked.contains(item.id);
    final dot = _hexColor(item.color);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: _saving ? null : () => _toggle(item.id),
        borderRadius: BorderRadius.circular(6),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
          child: Row(
            children: [
              SelectionCheck(selected: selected, size: 20),
              const SizedBox(width: 12),
              if (dot != null) ...[
                Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(color: dot, shape: BoxShape.circle),
                ),
                const SizedBox(width: 8),
              ],
              Expanded(
                child: AppText.subText(
                  context,
                  item.name,
                  fw: selected ? 1 : 3,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  color: selected ? scheme.primary : scheme.onSurface,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// `#rgb` / `#rrggbb` as the server sends it; null when it isn't a colour.
  static Color? _hexColor(String? raw) {
    if (raw == null) return null;
    var hex = raw.trim().replaceFirst('#', '');
    if (hex.length == 3) {
      hex = hex.split('').map((c) => '$c$c').join();
    }
    if (hex.length != 6) return null;
    final value = int.tryParse(hex, radix: 16);
    return value == null ? null : Color(0xFF000000 | value);
  }
}
