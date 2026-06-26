import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/router/routes.dart';
import '../../models/faq.dart';
import '../../providers.dart';
import '../../widgets/app_search_field.dart';
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Knowledgebase'),
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
      body: _q.isEmpty ? _buildCategories() : _buildSearch(),
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
        itemBuilder: (context, i) => _CategoryTile(category: cats[i]),
      ),
    );
  }
}

/// Expandable category that lazily loads its FAQs when first opened.
class _CategoryTile extends ConsumerStatefulWidget {
  const _CategoryTile({required this.category});
  final FaqCategory category;

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
      final full = await ref.read(faqRepositoryProvider).category(widget.category.id);
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
        title: Text(cat.name, style: const TextStyle(fontWeight: FontWeight.w600)),
        trailing: Text(
          '${cat.faqCount}',
          style: Theme.of(context).textTheme.bodyMedium,
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
              child: ErrorView(error: _error!, onRetry: () {
                setState(() => _error = null);
                _ensureLoaded();
              }),
            )
          else if ((_faqs ?? const []).isEmpty)
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text('No articles in this category.'),
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
      title: Text(
        faq.question,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontWeight: FontWeight.w500),
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
              faq.published ? theme.colorScheme.primary : theme.colorScheme.outline,
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
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: color,
            fontWeight: FontWeight.w500,
          ),
        ),
      );
}
