import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/api/api_exception.dart';
import '../../core/router/routes.dart';
import '../../core/theme/app_text.dart';
import '../../core/theme/app_theme.dart';
import '../../models/faq.dart';
import '../../providers.dart';
import '../../widgets/app_dialog.dart';
import '../../widgets/app_search_field.dart';
import '../../widgets/app_sheet.dart';
import '../../widgets/app_snack.dart';
import '../../widgets/paged_list_view.dart';
import '../../widgets/states.dart';

/// Knowledgebase: browse categories (no query) or search FAQs (query set).
class FaqScreen extends ConsumerStatefulWidget {
  const FaqScreen({super.key});

  @override
  ConsumerState<FaqScreen> createState() => _FaqScreenState();
}

class _FaqScreenState extends ConsumerState<FaqScreen> {
  final _searchCtrl = TextEditingController();
  String _q = '';

  List<FaqCategory>? _categories;
  Object? _catError;
  bool _loadingCats = false;

  @override
  void initState() {
    super.initState();
    _loadCategories();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadCategories() async {
    setState(() {
      _loadingCats = true;
      _catError = null;
    });
    try {
      final cats = await ref.read(faqRepositoryProvider).categories();
      if (!mounted) return;
      setState(() {
        _categories = cats;
        _loadingCats = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _catError = e;
        _loadingCats = false;
      });
    }
  }

  /// The web's "Add New Category" button, on the Categories page only and
  /// gated on `faq.manage` (see [Me.canManageFaq]). While `/me` is loading the
  /// action stays hidden rather than flashing in.
  Future<void> _addCategory() async {
    final created = await showAppSheet<FaqCategory>(
      context: context,
      builder: (_) => _CategorySheet(all: _categories ?? const []),
    );
    if (created == null || !mounted) return;
    AppSnack.success(context, 'Category "${created.name}" created');
    await _loadCategories();
  }

  Future<void> _editCategory(FaqCategory cat) async {
    final saved = await showAppSheet<FaqCategory>(
      context: context,
      builder: (_) => _CategorySheet(
        existing: cat,
        all: _categories ?? const [],
      ),
    );
    if (saved == null || !mounted) return;
    AppSnack.success(context, 'Category saved');
    await _loadCategories();
  }

  /// The web's Make Public / Make Private mass action, one category at a time.
  /// Visibility *is* the `type` field — there is no separate endpoint.
  Future<void> _setCategoryType(FaqCategory cat, String type) async {
    try {
      await ref
          .read(faqRepositoryProvider)
          .updateCategory(cat.id, {'type': type});
      if (!mounted) return;
      AppSnack.success(context, 'Category is now $type');
      await _loadCategories();
    } on ApiException catch (e) {
      if (mounted) AppSnack.error(context, e.message);
    }
  }

  /// Delete takes the category's articles with it, exactly as the web's mass
  /// action does — so the confirmation states the count up front, from the
  /// list row's own `faq_count`.
  Future<void> _deleteCategory(FaqCategory cat) async {
    final n = cat.faqCount;
    final ok = await showAppConfirmDialog(
      context,
      title: 'Delete category?',
      message: n == 0
          ? 'Delete "${cat.displayName}"? This cannot be undone.'
          : 'Delete "${cat.displayName}" and the $n article'
                '${n == 1 ? '' : 's'} in it? The article'
                '${n == 1 ? '' : 's'} will be deleted too, and this cannot '
                'be undone.',
      confirmLabel: 'Delete',
      destructive: true,
    );
    if (ok != true) return;
    try {
      final deleted = await ref
          .read(faqRepositoryProvider)
          .deleteCategory(cat.id);
      if (!mounted) return;
      AppSnack.success(
        context,
        deleted == 0
            ? 'Category deleted'
            : 'Category deleted with $deleted article'
                  '${deleted == 1 ? '' : 's'}',
      );
      await _loadCategories();
    } on ApiException catch (e) {
      // A failed article delete leaves the category intact server-side, so
      // nothing was destroyed — say so rather than implying a half-delete.
      if (mounted) AppSnack.error(context, e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final canManage = ref
        .watch(meProvider)
        .maybeWhen(data: (m) => m.canManageFaq, orElse: () => false);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Knowledgebase'),
        actions: [
          if (canManage && _q.isEmpty)
            IconButton(
              icon: const Icon(Icons.create_new_folder_outlined),
              tooltip: 'Add new category',
              onPressed: _addCategory,
            ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(56),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
            child: AppSearchField(
              controller: _searchCtrl,
              hintText: 'Search articles',
              onSubmitted: (v) => setState(() => _q = v.trim()),
              onClear: () => setState(() => _q = ''),
            ),
          ),
        ),
      ),
      body: SafeArea(child: _q.isEmpty ? _buildCategories() : _buildSearch()),
    );
  }

  Widget _buildSearch() {
    final repo = ref.watch(faqRepositoryProvider);
    return PagedListView<Faq>(
      refreshKey: _q,
      emptyMessage: 'No articles found',
      emptyHint: 'Try a different search term.',
      emptyIcon: Icons.menu_book_outlined,
      fetch: (page) => repo.search(q: _q, page: page),
      itemBuilder: (context, faq) => _FaqRow(faq: faq),
    );
  }

  /// Whether the category management actions are offered — the same
  /// `faq.manage` gate the web puts on its Categories page.
  bool get _canManage => ref
      .read(meProvider)
      .maybeWhen(data: (m) => m.canManageFaq, orElse: () => false);

  Widget _buildCategories() {
    if (_loadingCats && _categories == null) return const LoadingView();
    if (_catError != null && _categories == null) {
      return ErrorView(error: _catError!, onRetry: _loadCategories);
    }
    final cats = _categories ?? const [];
    if (cats.isEmpty) {
      return const EmptyView(
        icon: Icons.folder_open_outlined,
        message: 'No categories',
      );
    }
    return RefreshIndicator(
      onRefresh: _loadCategories,
      child: ListView.builder(
        padding: const EdgeInsets.symmetric(vertical: 6),
        itemCount: cats.length,
        itemBuilder: (context, i) => _CategoryTile(
          category: cats[i],
          canManage: _canManage,
          onEdit: () => _editCategory(cats[i]),
          onSetType: (t) => _setCategoryType(cats[i], t),
          onDelete: () => _deleteCategory(cats[i]),
        ),
      ),
    );
  }
}

/// Expandable category that lazily loads its FAQs when first opened.
class _CategoryTile extends ConsumerStatefulWidget {
  const _CategoryTile({
    required this.category,
    required this.canManage,
    required this.onEdit,
    required this.onSetType,
    required this.onDelete,
  });

  final FaqCategory category;
  final bool canManage;
  final VoidCallback onEdit;
  final ValueChanged<String> onSetType;
  final VoidCallback onDelete;

  @override
  ConsumerState<_CategoryTile> createState() => _CategoryTileState();
}

class _CategoryTileState extends ConsumerState<_CategoryTile> {
  List<Faq>? _faqs;
  bool _loading = false;
  Object? _error;

  @override
  void initState() {
    super.initState();
    if (widget.category.faqs.isNotEmpty) {
      _faqs = widget.category.faqs;
    }
  }

  Future<void> _ensureLoaded() async {
    if (_faqs != null || _loading) return;
    setState(() => _loading = true);
    try {
      final full = await ref
          .read(faqRepositoryProvider)
          .category(widget.category.id);
      if (!mounted) return;
      setState(() {
        _faqs = full.faqs;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final cat = widget.category;
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: ExpansionTile(
        shape: const Border(),
        leading: const Icon(Icons.folder_outlined),
        // "Funds / Pay in" when the category has a parent — the web's
        // Categories list renders the same full path (`getFullName()`).
        title: Row(
          children: [
            Expanded(
              child: AppText.subText(context, cat.displayName, fw: 1),
            ),
            if (widget.canManage)
              PopupMenuButton<String>(
                tooltip: 'Category actions',
                onSelected: (v) {
                  switch (v) {
                    case 'edit':
                      widget.onEdit();
                    case 'delete':
                      widget.onDelete();
                    default:
                      widget.onSetType(v);
                  }
                },
                itemBuilder: (_) => [
                  const PopupMenuItem(value: 'edit', child: Text('Edit')),
                  PopupMenuItem(
                    value: cat.public ? 'private' : 'public',
                    child: Text(
                      cat.public ? 'Make private' : 'Make public',
                    ),
                  ),
                  const PopupMenuItem(value: 'delete', child: Text('Delete')),
                ],
              ),
          ],
        ),
        // The web's Categories table carries NAME / TYPE / FAQS; the type is
        // what says whether an article in here is visible to end users at all,
        // so it rides along with the count.
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _CategoryTypeChip(type: cat.type, public: cat.public),
              const SizedBox(width: 8),
              AppText.paraText(
                context,
                cat.faqCount == 1 ? '1 article' : '${cat.faqCount} articles',
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ],
          ),
        ),
        onExpansionChanged: (open) {
          if (open) _ensureLoaded();
        },
        children: [
          if (_loading)
            const Padding(
              padding: EdgeInsets.all(16),
              child: Center(
                child: SizedBox(
                  height: 22,
                  width: 22,
                  child: CircularProgressIndicator(strokeWidth: 2.2),
                ),
              ),
            )
          else if (_error != null)
            Padding(
              padding: const EdgeInsets.all(12),
              child: ErrorView(
                error: _error!,
                onRetry: () {
                  setState(() => _error = null);
                  _ensureLoaded();
                },
              ),
            )
          else if ((_faqs ?? const []).isEmpty)
            Padding(
              padding: const EdgeInsets.all(16),
              child: AppText.subText(context, 'No articles in this category.'),
            )
          else
            for (final faq in _faqs!) _FaqRow(faq: faq, dense: true),
        ],
      ),
    );
  }
}

class _FaqRow extends StatelessWidget {
  const _FaqRow({required this.faq, this.dense = false});
  final Faq faq;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tile = ListTile(
      dense: dense,
      title: AppText.subText(
        context,
        faq.question,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        fw: 0,
      ),
      subtitle: Padding(
        padding: const EdgeInsets.only(top: 6),
        child: Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            _chip(
              context,
              faq.published ? 'Public' : 'Internal',
              faq.published
                  ? theme.colorScheme.primary
                  : theme.colorScheme.outline,
            ),
            if (faq.category != null)
              _chip(context, faq.category!.name, theme.colorScheme.secondary),
          ],
        ),
      ),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => context.push(Routes.faqArticle(faq.id)),
    );
    if (dense) return tile;
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: tile,
    );
  }

  Widget _chip(BuildContext context, String label, Color color) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(6),
    ),
    child: AppText.paraText(context, label, color: color, fw: 0),
  );
}

/// The Type column from the web's Categories table: Private / Public /
/// Featured. Falls back to the `public` flag on an install whose
/// `/faq/categories` doesn't send the richer `type` string.
class _CategoryTypeChip extends StatelessWidget {
  const _CategoryTypeChip({required this.type, required this.public});
  final String? type;
  final bool public;

  @override
  Widget build(BuildContext context) {
    final label = (type == null || type!.isEmpty)
        ? (public ? 'Public' : 'Private')
        : type!;
    final color = switch (label.toLowerCase()) {
      'public' => AppTheme.open,
      'featured' => AppTheme.warning,
      _ => Theme.of(context).colorScheme.outline,
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
      ),
      child: AppText.paraText(context, label, color: color, fw: 0),
    );
  }
}

// --- Add new category -------------------------------------------------------

/// The web's "Add New Category" form (`scp/categories.php`): type, parent,
/// name, description and internal notes — in the web's own order. Pops the
/// created [FaqCategory] on success.
class _CategorySheet extends ConsumerStatefulWidget {
  const _CategorySheet({this.existing, this.all = const []});

  /// The category being edited, or null to create one.
  final FaqCategory? existing;

  /// Every category the list already loaded — the Parent dropdown's options.
  /// Passed in rather than re-fetched: the screen behind the sheet has them.
  final List<FaqCategory> all;

  @override
  ConsumerState<_CategorySheet> createState() => _CategorySheetState();
}

class _CategorySheetState extends ConsumerState<_CategorySheet> {
  late final _name = TextEditingController(
    text: widget.existing?.name ?? '',
  );
  final _description = TextEditingController();
  final _notes = TextEditingController();

  /// osTicket's three category visibilities, in the web dropdown's order.
  static const _types = ['private', 'public', 'featured'];
  late String _type = widget.existing?.type?.toLowerCase() ?? 'private';

  /// What the web's Parent dropdown offers below "— Top-Level Category —",
  /// sorted by the same full path the Categories list shows.
  late final List<FaqCategory> _parents = _selectableParents();
  late int _parentId = _initialParentId();

  /// Every category that may be this one's parent. On an edit that excludes
  /// the category itself *and* its descendants — re-parenting a category under
  /// its own child would orphan the branch, which `Category` refuses.
  List<FaqCategory> _selectableParents() {
    final self = widget.existing;
    final banned = <int>{if (self != null) self.id};
    // Ids only ever point upward, but the list arrives unordered, so keep
    // sweeping until no further descendant turns up.
    for (var grew = self != null; grew;) {
      grew = false;
      for (final c in widget.all) {
        if (!banned.contains(c.id) && banned.contains(c.parentId ?? 0)) {
          banned.add(c.id);
          grew = true;
        }
      }
    }
    final out = [
      for (final c in widget.all)
        if (!banned.contains(c.id)) c,
    ];
    out.sort(
      (a, b) => a.displayName.toLowerCase().compareTo(b.displayName.toLowerCase()),
    );
    return out;
  }

  /// The stored parent, or top level. An install that doesn't publish `pid`
  /// sends null and lands on top level rather than tripping the dropdown's
  /// "value must be in items" assert.
  int _initialParentId() {
    final pid = widget.existing?.parentId ?? 0;
    return _parents.any((c) => c.id == pid) ? pid : 0;
  }

  bool get _isEdit => widget.existing != null;

  bool _saving = false;
  Map<String, String> _fieldErrors = const {};
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _description.dispose();
    _notes.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    final description = _description.text.trim();
    // `Category::update()` requires a name of 3+ characters and a description;
    // catching them here saves a round trip and words each failure the way the
    // server does. On an edit the description is only validated when the
    // agent typed one — an omitted field keeps its stored value.
    final nameError = name.isEmpty
        ? 'Category name is required'
        : name.length < 3
        ? 'Name is too short. 3 chars minimum'
        : null;
    final descriptionMissing = !_isEdit && description.isEmpty;
    if (nameError != null || descriptionMissing) {
      setState(() {
        _error = null;
        _fieldErrors = {
          if (nameError != null) 'name': nameError,
          if (descriptionMissing) 'description': 'A description is required',
        };
      });
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
      _fieldErrors = const {};
    });
    final repo = ref.read(faqRepositoryProvider);
    final notes = _notes.text.trim();
    try {
      final saved = _isEdit
          // Partial update: the category payload never serves the description
          // or the notes back, so sending an untouched (empty) field would
          // blank a value the agent can't even see. Send only what was typed.
          ? await repo.updateCategory(widget.existing!.id, {
              'name': name,
              'type': _type,
              'pid': _parentId,
              if (description.isNotEmpty) 'description': description,
              if (notes.isNotEmpty) 'notes': notes,
            })
          : await repo.createCategory(
              name: name,
              type: _type,
              description: description,
              parentId: _parentId,
              notes: notes,
            );
      if (mounted) Navigator.pop(context, saved);
    } on ApiException catch (e) {
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
      title: _isEdit ? 'Edit category' : 'Add new category',
      subtitle: _isEdit
          ? 'Description and notes are not served back by the API — leave '
                'them blank to keep what is stored.'
          : null,
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
            // The web's field order: Category Type, Parent, Name, then
            // Description, with Internal Notes on its own tab last.
            DropdownButtonFormField<String>(
              initialValue: _type,
              decoration: InputDecoration(
                labelText: 'Category type',
                errorText: _fieldErrors['type'] ?? _fieldErrors['ispublic'],
              ),
              items: [
                for (final t in _types)
                  DropdownMenuItem(
                    value: t,
                    child: Text('${t[0].toUpperCase()}${t.substring(1)}'),
                  ),
              ],
              onChanged: (v) => setState(() => _type = v ?? _type),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<int>(
              initialValue: _parentId,
              isExpanded: true,
              decoration: InputDecoration(
                labelText: 'Parent',
                errorText: _fieldErrors['pid'],
              ),
              items: [
                const DropdownMenuItem(
                  value: 0,
                  child: Text('— Top-Level Category —'),
                ),
                for (final c in _parents)
                  DropdownMenuItem(
                    value: c.id,
                    child: Text(c.displayName, overflow: TextOverflow.ellipsis),
                  ),
              ],
              onChanged: (v) => setState(() => _parentId = v ?? _parentId),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _name,
              textCapitalization: TextCapitalization.sentences,
              decoration: InputDecoration(
                labelText: 'Category name',
                helperText: 'Short descriptive name.',
                errorText: _fieldErrors['name'],
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _description,
              minLines: 3,
              maxLines: 6,
              textCapitalization: TextCapitalization.sentences,
              decoration: InputDecoration(
                labelText: _isEdit ? 'Description (optional)' : 'Description',
                alignLabelWithHint: true,
                errorText: _fieldErrors['description'],
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _notes,
              minLines: 2,
              maxLines: 4,
              textCapitalization: TextCapitalization.sentences,
              decoration: InputDecoration(
                labelText: 'Internal notes (optional)',
                alignLabelWithHint: true,
                errorText: _fieldErrors['notes'],
              ),
            ),
            const SizedBox(height: 16),
            // Expanded on both: the theme gives these buttons an infinite
            // minimum width, so they need a width-bounded parent.
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: _saving ? null : () => Navigator.pop(context),
                    child: const Text('Cancel'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(
                    onPressed: _saving ? null : _save,
                    child: _saving
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2.4,
                              color: Colors.white,
                            ),
                          )
                        : Text(_isEdit ? 'Save' : 'Create'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
