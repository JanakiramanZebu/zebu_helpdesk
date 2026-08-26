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

/// Mints a tag from a typed name and applies it, returning the object's new
/// tag list. `POST /{obj}/{id}/tags {"name": ...}` resolves the name to an
/// existing tag or creates it (`Tag::resolveOrCreate`), so this is one call,
/// not create-then-apply.
typedef TagCreator = Future<List<Tag>> Function(String name);

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
/// An admin or department manager can also **create** a tag here by typing a
/// name that isn't in the list yet — the web's own affordance (select2 with
/// `tags: true` in `templates/tags-manage.tmpl.php`: "To create a new tag,
/// type it and press Enter"). Pass [createTag] only when `Tag::canCreate()`
/// holds for the agent; a regular agent applies existing tags only. Like a
/// tick, a typed name is only committed by **Save** — dismissing the dialog
/// mints nothing.
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
  TagCreator? createTag,
}) {
  return showDialog<List<Tag>>(
    context: context,
    builder: (_) => _TagsDialog(
      loadApplied: loadApplied,
      loadShared: loadShared,
      addTag: addTag,
      removeTag: removeTag,
      createTag: createTag,
    ),
  );
}

class _TagsDialog extends StatefulWidget {
  const _TagsDialog({
    required this.loadApplied,
    required this.loadShared,
    required this.addTag,
    required this.removeTag,
    this.createTag,
  });

  final AppliedTagsLoader loadApplied;
  final SharedTagsLoader loadShared;
  final TagMutation addTag;
  final TagMutation removeTag;

  /// Null when the agent may not mint tags, which is also what hides the
  /// "Create ..." row.
  final TagCreator? createTag;

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

  /// Names typed into the search box that don't exist yet, queued for Save.
  /// They have no id until the server mints them, so they can't live in
  /// [_picked].
  final List<String> _newNames = [];

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

  bool get _dirty => !_setEquals(_picked, _saved) || _newNames.isNotEmpty;

  static bool _setEquals(Set<int> a, Set<int> b) =>
      a.length == b.length && a.containsAll(b);

  /// Typing is how a tag is created, so the box is always there for an agent
  /// who may create one — not only once the list is long enough to search.
  bool get _searchable => _options.length > 8 || widget.createTag != null;

  String get _query => _searchCtrl.text.trim();

  List<MetaItem> get _filtered {
    final query = _query.toLowerCase();
    if (query.isEmpty) return _options;
    return _options
        .where((item) => item.name.toLowerCase().contains(query))
        .toList();
  }

  List<String> get _filteredNewNames {
    final query = _query.toLowerCase();
    if (query.isEmpty) return _newNames;
    return _newNames.where((n) => n.toLowerCase().contains(query)).toList();
  }

  /// Whether what's typed would mint a new tag: creation is allowed, something
  /// was typed, and neither the vocabulary nor this dialog's queue already has
  /// it. The comparison is case-insensitive because the server dedupes on a
  /// normalised slug — typing an existing tag's name in another case resolves
  /// to that tag rather than creating a second one, so offer the tick instead.
  bool get _canMint {
    if (widget.createTag == null || _query.isEmpty) return false;
    final q = _query.toLowerCase();
    return !_options.any((o) => o.name.trim().toLowerCase() == q) &&
        !_newNames.any((n) => n.toLowerCase() == q);
  }

  /// Queue the typed name and clear the box, the way pressing Enter in the
  /// web's select2 turns the text into a chip. Nothing is sent until Save.
  void _mint() {
    if (!_canMint || _saving) return;
    setState(() {
      _newNames.add(_query);
      _searchCtrl.clear();
      _error = null;
    });
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
    // Typed names last: each one creates the tag and applies it in the same
    // call. A name the server won't mint (a disabled tag already holds it, or
    // the permission is refused) stays in the queue, so the agent sees which
    // one was rejected instead of losing what they typed.
    final failedNames = <String>[];
    for (final name in List<String>.of(_newNames)) {
      try {
        latest = await widget.createTag!(name);
      } on ApiException catch (e) {
        failedNames.add(name);
        failures.add(_reason(e, 'Could not create "$name"'));
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
      _newNames
        ..clear()
        ..addAll(failedNames);
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
                    hintText: widget.createTag == null
                        ? 'Search'
                        : 'Search, or type a new tag',
                    onChanged: (_) => setState(() {}),
                    onSubmitted: (_) => _mint(),
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
    if (_options.isEmpty && _newNames.isEmpty) {
      // The web splits this message the same way: an agent who cannot create
      // is told to ask someone who can; one who can is told to type.
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: AppText.subText(
          context,
          widget.createTag == null
              ? 'No tags are available for your department. Ask an '
                    'administrator or your department manager to add one.'
              : 'No tags have been defined yet. Type a name above to create '
                    'the first one.',
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      );
    }
    final items = _filtered;
    final pending = _filteredNewNames;
    if (items.isEmpty && pending.isEmpty && !_canMint) {
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
        children: [
          if (_canMint) _createRow(context),
          for (final name in pending) _pendingRow(context, name),
          for (final item in items) _row(context, item),
        ],
      ),
    );
  }

  /// `Create "<what you typed>"` — the top row while the box holds a name the
  /// vocabulary doesn't have.
  Widget _createRow(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: _saving ? null : _mint,
        borderRadius: BorderRadius.circular(6),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
          child: Row(
            children: [
              Icon(Icons.add_circle_outline, size: 20, color: scheme.primary),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    AppText.subText(
                      context,
                      'Create "$_query"',
                      fw: 1,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      color: scheme.primary,
                    ),
                    AppText.paraText(
                      context,
                      'New tag, shared with every agent',
                      color: scheme.onSurfaceVariant,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// A queued name: ticked like any applied tag, badged **New**, and tapped
  /// again to drop it before Save.
  Widget _pendingRow(BuildContext context, String name) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: _saving
            ? null
            : () => setState(() {
                _newNames.remove(name);
                _error = null;
              }),
        borderRadius: BorderRadius.circular(6),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
          child: Row(
            children: [
              const SelectionCheck(selected: true, size: 20),
              const SizedBox(width: 12),
              Expanded(
                child: AppText.subText(
                  context,
                  name,
                  fw: 1,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  color: scheme.primary,
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: scheme.primary.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: AppText.paraText(context, 'New', color: scheme.primary),
              ),
            ],
          ),
        ),
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
