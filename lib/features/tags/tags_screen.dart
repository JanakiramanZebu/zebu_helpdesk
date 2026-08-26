import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api_exception.dart';
import '../../core/theme/app_text.dart';
import '../../models/common.dart';
import '../../providers.dart';
import '../../widgets/app_dialog.dart';
import '../../widgets/app_sheet.dart';
import '../../widgets/app_snack.dart';
import '../../widgets/paged_list_view.dart';

/// The colour a tag gets when nothing else is chosen — osTicket's own default
/// (`include/staff/tags.inc.php` seeds its picker with it, and
/// `Tag::resolveOrCreate` stamps it on a tag minted from a ticket).
const _kDefaultTagColor = '#3b7dd8';

/// Quick picks. The web's field is a free `<input type="color">`, so these are
/// shortcuts, not the allowed set — the hex box below them takes any
/// `#rrggbb`, which is exactly what `Tag::update()` validates. The first is
/// osTicket's default and the last is `Tag::getColor()`'s fallback for a tag
/// stored without one.
const _kTagColors = <String>[
  _kDefaultTagColor,
  '#d9534f',
  '#f0ad4e',
  '#5cb85c',
  '#5bc0de',
  '#337ab7',
  '#9b59b6',
  '#666666',
];

/// What `Tag::update()` accepts: `#` plus six hex digits.
final _kHexColor = RegExp(r'^#[0-9a-fA-F]{6}$');

/// Status views over the one catalogue fetch, mirroring the web list's
/// enabled/disabled split.
enum _TagView {
  active('Active'),
  disabled('Disabled'),
  all('All');

  const _TagView(this.label);
  final String label;

  bool accepts(Tag t) => switch (this) {
    _TagView.active => t.isActive,
    _TagView.disabled => !t.isActive,
    _TagView.all => true,
  };
}

/// Manage the shared tag vocabulary — the mobile port of
/// `scp/managetags.php`: create, rename, recolor, enable / disable, merge and
/// delete. Reachable by an admin or the manager of any department
/// (`Tag::canManage()`, published here as `Me.canManageTags`).
///
/// **Merge is the reason this screen matters.** The web's own Merge action
/// destroys the tag associations it claims to move (the ORM never writes the
/// new `tag_id`, so the links are deleted with the source tag). `POST
/// /tags/merge` moves them explicitly, so this is the only safe way to merge
/// tags on this install.
class TagsScreen extends ConsumerStatefulWidget {
  const TagsScreen({super.key});

  @override
  ConsumerState<TagsScreen> createState() => _TagsScreenState();
}

class _TagsScreenState extends ConsumerState<TagsScreen> {
  int _reload = 0;
  _TagView _view = _TagView.active;

  /// Tags picked for a merge. The first pick survives; the rest are consumed.
  final List<Tag> _selected = [];

  bool get _merging => _selected.isNotEmpty;

  void _refresh() => setState(() {
    _reload++;
    _selected.clear();
  });

  void _toast(String msg) => AppSnack.info(context, msg);
  void _error(String msg) => AppSnack.error(context, msg);

  @override
  Widget build(BuildContext context) {
    final repo = ref.watch(tagsRepositoryProvider);
    final me = ref.watch(meProvider);
    final canCreate = me.maybeWhen(
      data: (m) => m.canCreateTags,
      orElse: () => false,
    );
    final canManage = me.maybeWhen(
      data: (m) => m.canManageTags,
      orElse: () => false,
    );

    return Scaffold(
      appBar: AppBar(
        title: const Text('Tags'),
        actions: [
          if (_merging)
            TextButton(
              onPressed: () => setState(_selected.clear),
              child: const Text('Cancel'),
            ),
        ],
      ),
      floatingActionButton: canCreate && !_merging
          ? FloatingActionButton(
              onPressed: _openCreate,
              child: const Icon(Icons.add),
            )
          : null,
      body: PagedListView<Tag>(
        refreshKey: _reload,
        emptyMessage: _view == _TagView.disabled
            ? 'No disabled tags'
            : 'No tags yet',
        emptyIcon: Icons.local_offer_outlined,
        header: _header(),
        fabClearance: true,
        fetch: (page) => repo.list(page: page),
        itemFilter: _view.accepts,
        itemBuilder: (context, t) => _TagRow(
          tag: t,
          canManage: canManage,
          mergeIndex: _mergeIndexOf(t),
          merging: _merging,
          onTapMerge: canManage ? () => _toggleMergePick(t) : null,
          onEdit: () => _openEdit(t),
          onToggleActive: () => _setActive(t, !t.isActive),
          onDelete: () => _confirmDelete(t),
        ),
      ),
    );
  }

  /// Where [t] sits in the merge selection: 0 = the survivor, 1+ = consumed,
  /// null = not picked.
  int? _mergeIndexOf(Tag t) {
    final i = _selected.indexWhere((s) => s.id == t.id);
    return i < 0 ? null : i;
  }

  Widget _header() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
        child: Row(
          children: [
            for (final v in _TagView.values)
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: ChoiceChip(
                  label: Text(v.label),
                  selected: _view == v,
                  onSelected: (_) => setState(() => _view = v),
                ),
              ),
          ],
        ),
      ),
      if (_merging) _mergeBar(),
    ],
  );

  /// The merge tray: names the survivor explicitly, because getting the
  /// direction backwards is not recoverable.
  Widget _mergeBar() {
    final scheme = Theme.of(context).colorScheme;
    final survivor = _selected.first;
    final consumed = _selected.skip(1).toList();
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 4, 12, 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: scheme.primary.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AppText.subText(context, 'Merge into "${survivor.name}"', fw: 1),
          const SizedBox(height: 4),
          AppText.paraText(
            context,
            consumed.isEmpty
                ? 'Now pick the tags to merge into it. They will be deleted.'
                : '${consumed.map((t) => t.name).join(', ')} '
                      '${consumed.length == 1 ? 'is' : 'are'} deleted, and '
                      '${consumed.length == 1 ? 'its' : 'their'} tickets and '
                      'tasks move to "${survivor.name}".',
            color: scheme.onSurfaceVariant,
          ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton(
              onPressed: consumed.isEmpty ? null : _confirmMerge,
              child: Text(
                consumed.isEmpty
                    ? 'Merge'
                    : 'Merge ${consumed.length} tag'
                          '${consumed.length == 1 ? '' : 's'}',
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _toggleMergePick(Tag t) {
    setState(() {
      final i = _selected.indexWhere((s) => s.id == t.id);
      if (i >= 0) {
        _selected.removeAt(i);
      } else {
        _selected.add(t);
      }
    });
  }

  Future<void> _confirmMerge() async {
    final survivor = _selected.first;
    final consumed = _selected.skip(1).toList();
    final objects = consumed.fold<int>(0, (n, t) => n + t.objectCount);
    final ok = await showAppConfirmDialog(
      context,
      title: 'Merge tags?',
      message:
          '${consumed.map((t) => '"${t.name}"').join(', ')} will be deleted '
          'and $objects tagged item${objects == 1 ? '' : 's'} will move to '
          '"${survivor.name}". This cannot be undone.',
      confirmLabel: 'Merge',
      destructive: true,
    );
    if (ok != true) return;
    try {
      final result = await ref
          .read(tagsRepositoryProvider)
          .merge(
            intoId: survivor.id,
            sourceIds: [for (final t in consumed) t.id],
          );
      if (!mounted) return;
      final skipped = result.skipped.isEmpty
          ? ''
          : ' (${result.skipped.length} skipped)';
      _toast(
        'Merged into "${result.into.name}" — '
        '${result.into.objectCount} tagged item'
        '${result.into.objectCount == 1 ? '' : 's'}$skipped',
      );
      _refresh();
    } on ApiException catch (e) {
      _error(e.message);
    }
  }

  Future<void> _openCreate() async {
    final created = await showAppSheet<Tag>(
      context: context,
      builder: (_) => const _TagEditor(),
    );
    if (created == null || !mounted) return;
    _toast('Tag "${created.name}" created');
    _refresh();
  }

  Future<void> _openEdit(Tag t) async {
    final saved = await showAppSheet<Tag>(
      context: context,
      builder: (_) => _TagEditor(existing: t),
    );
    if (saved == null || !mounted) return;
    _toast('Saved');
    _refresh();
  }

  Future<void> _setActive(Tag t, bool active) async {
    try {
      await ref.read(tagsRepositoryProvider).update(t.id, {
        'is_active': active,
      });
      if (!mounted) return;
      _toast(active ? 'Enabled' : 'Disabled');
      _refresh();
    } on ApiException catch (e) {
      _error(e.message);
    }
  }

  Future<void> _confirmDelete(Tag t) async {
    // A tag in use is refused server-side rather than silently detached, so
    // say what it is on and offer merge instead of a doomed delete.
    if (t.objectCount > 0) {
      final merge = await showAppConfirmDialog(
        context,
        title: 'Tag is in use',
        message:
            '"${t.name}" is on ${t.objectCount} ticket/task'
            '${t.objectCount == 1 ? '' : 's'}, so it cannot be deleted. '
            'Merge it into another tag instead?',
        confirmLabel: 'Merge',
      );
      if (merge == true && mounted) {
        setState(() {
          _selected
            ..clear()
            ..add(t);
        });
        _toast('Now pick the tag to keep, then merge');
      }
      return;
    }
    final ok = await showAppConfirmDialog(
      context,
      title: 'Delete tag?',
      message: 'Delete "${t.name}"? This cannot be undone.',
      confirmLabel: 'Delete',
      destructive: true,
    );
    if (ok != true) return;
    try {
      await ref.read(tagsRepositoryProvider).delete(t.id);
      if (!mounted) return;
      _toast('Deleted');
      _refresh();
    } on ApiException catch (e) {
      _error(e.message);
    }
  }
}

class _TagRow extends StatelessWidget {
  const _TagRow({
    required this.tag,
    required this.canManage,
    required this.merging,
    required this.mergeIndex,
    required this.onTapMerge,
    required this.onEdit,
    required this.onToggleActive,
    required this.onDelete,
  });

  final Tag tag;
  final bool canManage;
  final bool merging;
  final int? mergeIndex;
  final VoidCallback? onTapMerge;
  final VoidCallback onEdit;
  final VoidCallback onToggleActive;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final picked = mergeIndex != null;
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      color: picked ? scheme.primary.withValues(alpha: 0.06) : null,
      child: ListTile(
        onTap: merging ? onTapMerge : (canManage ? onEdit : null),
        onLongPress: canManage && !merging ? onTapMerge : null,
        leading: Container(
          width: 14,
          height: 14,
          decoration: BoxDecoration(
            color: _parseColor(tag.color, scheme.primary),
            shape: BoxShape.circle,
          ),
        ),
        title: Row(
          children: [
            Flexible(
              child: AppText.subText(
                context,
                tag.name,
                fw: 1,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (!tag.isActive) ...[
              const SizedBox(width: 8),
              _Pill(label: 'Disabled', color: scheme.error),
            ],
            if (tag.isGlobal) ...[
              const SizedBox(width: 6),
              _Pill(label: 'Global', color: scheme.onSurfaceVariant),
            ],
          ],
        ),
        subtitle: AppText.paraText(
          context,
          '${tag.objectCount} tagged item${tag.objectCount == 1 ? '' : 's'}'
          '${tag.updatedLabel == null ? '' : ' · updated ${tag.updatedLabel}'}',
          color: scheme.onSurfaceVariant,
        ),
        trailing: merging
            ? (picked
                  ? _MergeBadge(index: mergeIndex!)
                  : const Icon(Icons.radio_button_unchecked))
            : (canManage
                  ? PopupMenuButton<String>(
                      onSelected: (v) {
                        if (v == 'edit') onEdit();
                        if (v == 'toggle') onToggleActive();
                        if (v == 'merge') onTapMerge?.call();
                        if (v == 'delete') onDelete();
                      },
                      itemBuilder: (_) => [
                        const PopupMenuItem(
                          value: 'edit',
                          child: Text('Edit'),
                        ),
                        PopupMenuItem(
                          value: 'toggle',
                          child: Text(tag.isActive ? 'Disable' : 'Enable'),
                        ),
                        const PopupMenuItem(
                          value: 'merge',
                          child: Text('Merge…'),
                        ),
                        const PopupMenuItem(
                          value: 'delete',
                          child: Text('Delete'),
                        ),
                      ],
                    )
                  : null),
      ),
    );
  }
}

/// "Keep" for the survivor, then 1..n for the tags being consumed — the
/// direction has to be readable at a glance.
class _MergeBadge extends StatelessWidget {
  const _MergeBadge({required this.index});
  final int index;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return _Pill(
      label: index == 0 ? 'Keep' : 'Merge',
      color: index == 0 ? scheme.primary : scheme.error,
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({required this.label, required this.color});
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(6),
    ),
    child: AppText.paraText(context, label, color: color),
  );
}

Color _parseColor(String hex, Color fallback) {
  final v = hex.replaceAll('#', '').trim();
  if (v.length != 6) return fallback;
  final n = int.tryParse(v, radix: 16);
  return n == null ? fallback : Color(0xFF000000 | n);
}

/// Create / edit sheet — name, colour, and (on edit) the Active switch, which
/// is the same partial `POST /tags/{id}` the row menu uses.
class _TagEditor extends ConsumerStatefulWidget {
  const _TagEditor({this.existing});
  final Tag? existing;

  @override
  ConsumerState<_TagEditor> createState() => _TagEditorState();
}

class _TagEditorState extends ConsumerState<_TagEditor> {
  late final TextEditingController _name = TextEditingController(
    text: widget.existing?.name ?? '',
  );

  /// The hex box is the source of truth for the colour; the swatches just
  /// write into it. A tag recoloured on the web to something outside the quick
  /// picks therefore opens showing its real colour rather than nothing
  /// selected.
  late final TextEditingController _colorCtrl = TextEditingController(
    text: _normalizeHex(widget.existing?.color) ?? _kDefaultTagColor,
  );
  late bool _active = widget.existing?.isActive ?? true;

  String get _color => _colorCtrl.text.trim();

  bool _saving = false;
  Map<String, String> _fieldErrors = const {};
  String? _error;

  bool get _isEdit => widget.existing != null;

  @override
  void dispose() {
    _name.dispose();
    _colorCtrl.dispose();
    super.dispose();
  }

  /// `#rrggbb` for anything the server or the agent can plausibly hand over
  /// (with or without the `#`, any case); null when it isn't a colour at all.
  static String? _normalizeHex(String? raw) {
    final v = (raw ?? '').trim();
    if (v.isEmpty) return null;
    final withHash = v.startsWith('#') ? v : '#$v';
    return _kHexColor.hasMatch(withHash) ? withHash.toLowerCase() : null;
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    final color = _normalizeHex(_color);
    // `Tag::update()`'s own three rules, worded the way it words them, so a
    // typo costs no round trip. Uniqueness is the one it can only answer
    // server-side.
    final nameError = name.isEmpty
        ? 'Tag name is required'
        : name.runes.length > 64
        ? 'Tag name is too long (64 characters max)'
        : null;
    if (nameError != null || color == null) {
      setState(() {
        _error = null;
        _fieldErrors = {
          if (nameError != null) 'name': nameError,
          if (color == null)
            'color': 'Enter a valid hex color, e.g. $_kDefaultTagColor',
        };
      });
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
      _fieldErrors = const {};
    });
    final repo = ref.read(tagsRepositoryProvider);
    try {
      var saved = _isEdit
          // Partial update: only what this sheet owns.
          ? await repo.update(widget.existing!.id, {
              'name': name,
              'color': color,
              'is_active': _active,
            })
          : await repo.create(name: name, color: color, isActive: _active);
      // The web's Add form can create a tag already disabled (its Active box
      // starts checked but can be unchecked). An install whose POST /tags
      // ignores `is_active` would silently create it active instead, so make
      // the state stick with the update call that definitely honours it.
      if (!_isEdit && !_active && saved.isActive) {
        saved = await repo.update(saved.id, {'is_active': false});
      }
      if (mounted) Navigator.pop(context, saved);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.fields.isEmpty ? e.message : null;
        _fieldErrors = e.fields;
      });
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return AppSheet(
      title: _isEdit ? 'Edit tag' : 'New tag',
      child: AbsorbPointer(
        absorbing: _saving,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (_error != null) ...[
              AppText.subText(context, _error!, color: scheme.error),
              const SizedBox(height: 12),
            ],
            TextField(
              controller: _name,
              autofocus: !_isEdit,
              textCapitalization: TextCapitalization.words,
              decoration: InputDecoration(
                labelText: 'Tag name',
                errorText: _fieldErrors['name'],
              ),
            ),
            const SizedBox(height: 16),
            AppText.subText(context, 'Colour', fw: 1),
            const SizedBox(height: 8),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                for (final c in _kTagColors)
                  GestureDetector(
                    onTap: () => setState(() {
                      _colorCtrl.text = c;
                      _fieldErrors = {..._fieldErrors}..remove('color');
                    }),
                    child: Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        color: _parseColor(c, scheme.primary),
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: _color.toLowerCase() == c.toLowerCase()
                              ? scheme.onSurface
                              : Colors.transparent,
                          width: 2.5,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            // The web's control is a free colour picker, so any hex the server
            // accepts has to be typeable here too — otherwise a tag can only
            // ever wear one of eight colours in the app.
            TextField(
              controller: _colorCtrl,
              onChanged: (_) => setState(() {}),
              maxLength: 7,
              autocorrect: false,
              decoration: InputDecoration(
                labelText: 'Chip colour',
                counterText: '',
                helperText: 'Any hex colour, e.g. $_kDefaultTagColor',
                errorText: _fieldErrors['color'],
                prefixIcon: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                  child: Container(
                    width: 22,
                    height: 22,
                    decoration: BoxDecoration(
                      color: _parseColor(
                        _normalizeHex(_color) ?? '',
                        scheme.surfaceContainerHighest,
                      ),
                      shape: BoxShape.circle,
                      border: Border.all(color: scheme.outlineVariant),
                    ),
                  ),
                ),
                prefixIconConstraints: const BoxConstraints(
                  minWidth: 46,
                  minHeight: 42,
                ),
              ),
            ),
            const SizedBox(height: 4),
            // On the web this switch is on the Add form too — an agent can
            // define a tag now and only open it to tagging later.
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: _active,
              onChanged: (v) => setState(() => _active = v),
              title: const Text('Active'),
              subtitle: const Text(
                'A disabled tag stays on what already carries it, but is '
                'not offered for new tagging.',
              ),
            ),
            const SizedBox(height: 20),
            FilledButton(
              onPressed: _saving ? null : _save,
              child: Text(_saving ? 'Saving…' : 'Save'),
            ),
          ],
        ),
      ),
    );
  }
}
