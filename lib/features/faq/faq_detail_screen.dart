import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api_exception.dart';
import '../../core/format.dart';
import '../../core/theme/app_text.dart';
import '../../models/faq.dart';
import '../../providers.dart';
import '../../widgets/app_dialog.dart';
import '../../widgets/app_snack.dart';
import '../../widgets/attachment_tile.dart';
import '../../widgets/states.dart';
import 'faq_editor_sheet.dart';

class FaqDetailScreen extends ConsumerStatefulWidget {
  const FaqDetailScreen({super.key, required this.faqId});
  final int faqId;

  @override
  ConsumerState<FaqDetailScreen> createState() => _FaqDetailScreenState();
}

class _FaqDetailScreenState extends ConsumerState<FaqDetailScreen> {
  Faq? _faq;
  Object? _error;
  bool _loading = true;

  /// The publish toggle in flight, so the action can't be fired twice.
  bool _busy = false;

  /// Tell the Knowledgebase list behind this screen that a row (or an article
  /// count) it is showing has moved on. It stays mounted under the pushed
  /// detail, so it reloads while this screen is still on top.
  void _markChanged() => ref.read(faqChangedProvider.notifier).bump();

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final faq = await ref.read(faqRepositoryProvider).get(widget.faqId);
      if (!mounted) return;
      setState(() {
        _faq = faq;
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

  /// The web's article actions (`scp/faq.php`), all behind `faq.manage` the
  /// way that page's POST branch is.
  Future<void> _edit() async {
    final faq = _faq;
    if (faq == null) return;
    // The editor sends the whole form, so it needs the full article — which is
    // exactly what this screen already holds. Categories come from the list
    // endpoint.
    var categories = <FaqCategory>[];
    try {
      categories = await ref.read(faqRepositoryProvider).categories();
    } on ApiException {
      // Non-fatal — the article's own category stands in below.
    }
    // The sheet opens its Category dropdown on the article's own category, and
    // `DropdownButtonFormField` asserts unless that value is among the items.
    // So whenever the list didn't bring it back — the call above failed, or the
    // article sits in a category the listing doesn't return — put it in, rather
    // than handing the sheet a value it cannot render.
    final own = faq.category;
    if (own != null && !categories.any((c) => c.id == own.id)) {
      categories = [...categories, FaqCategory(id: own.id, name: own.name)];
    }
    if (!mounted) return;
    final saved = await showFaqEditorSheet(
      context,
      categories: categories,
      existing: faq,
    );
    if (saved == null || !mounted) return;
    _markChanged();
    AppSnack.success(context, 'Article saved');
    await _load();
  }

  /// Publishing is not a separate endpoint — it is a one-key partial edit.
  ///
  /// Driven off [Faq.listing], not `published`: that boolean is the server's
  /// `isPublished()`, which also folds in whether the *category* is public, so
  /// a Public article under a Private category reads false and this would
  /// "publish" something already published.
  Future<void> _togglePublished() async {
    final faq = _faq;
    if (faq == null || _busy) return;
    final next = faq.listing == FaqListing.internal;
    setState(() => _busy = true);
    try {
      final saved = await ref
          .read(faqRepositoryProvider)
          .updateArticle(faq.id, {'published': next});
      if (!mounted) return;
      _markChanged();
      setState(() {
        _faq = saved;
        _busy = false;
      });
      AppSnack.success(
        context,
        next ? 'Article published' : 'Article is now internal',
      );
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      AppSnack.error(context, e.message);
    }
  }

  /// Deletes the article, its help-topic links and its attachments.
  Future<void> _delete() async {
    final faq = _faq;
    if (faq == null) return;
    final ok = await showAppConfirmDialog(
      context,
      title: 'Delete article?',
      message:
          'Delete "${faq.question}"? Its attachments and help-topic links go '
          'with it, and this cannot be undone.',
      confirmLabel: 'Delete',
      destructive: true,
    );
    if (ok != true || !mounted) return;
    try {
      await ref.read(faqRepositoryProvider).deleteArticle(faq.id);
      if (!mounted) return;
      _markChanged();
      AppSnack.success(context, 'Article deleted');
      Navigator.of(context).pop();
    } on ApiException catch (e) {
      if (mounted) AppSnack.error(context, e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final faq = _faq;
    final canManage = ref
        .watch(meProvider)
        .maybeWhen(data: (m) => m.canManageFaq, orElse: () => false);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Article'),
        actions: [
          if (canManage && faq != null)
            PopupMenuButton<String>(
              tooltip: 'Article actions',
              onSelected: (v) {
                switch (v) {
                  case 'edit':
                    _edit();
                  case 'publish':
                    _togglePublished();
                  case 'delete':
                    _delete();
                }
              },
              itemBuilder: (_) => [
                const PopupMenuItem(value: 'edit', child: Text('Edit')),
                PopupMenuItem(
                  value: 'publish',
                  child: Text(
                    faq.listing == FaqListing.internal
                        ? 'Publish'
                        // Demoting a Featured article is one-way: the API has
                        // no way to put it back.
                        : faq.listing == FaqListing.featured
                        ? 'Make internal (drops Featured)'
                        : 'Make internal',
                  ),
                ),
                const PopupMenuItem(value: 'delete', child: Text('Delete')),
              ],
            ),
        ],
      ),
      body: SafeArea(
        child: _loading
            ? const LoadingView()
            : _error != null
            ? ErrorView(error: _error!, onRetry: _load)
            : _buildBody(context, faq!),
      ),
    );
  }

  Widget _buildBody(BuildContext context, Faq faq) {
    final theme = Theme.of(context);
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        AppText.custmText(context, faq.question, fs: 22, fw: 2),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _chip(
              context,
              faq.listing.label,
              faq.listing == FaqListing.internal
                  ? theme.colorScheme.outline
                  : theme.colorScheme.primary,
            ),
            if (faq.category != null)
              _chip(context, faq.category!.name, theme.colorScheme.secondary),
          ],
        ),
        const SizedBox(height: 16),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: AppText.subText(context, Fmt.stripHtml(faq.answer)),
          ),
        ),
        if (faq.attachments.isNotEmpty) ...[
          const SizedBox(height: 16),
          AppText.subText(context, 'Attachments', fw: 1),
          const SizedBox(height: 4),
          Card(
            child: Column(
              children: [
                for (final a in faq.attachments) AttachmentTile(attachment: a),
              ],
            ),
          ),
        ],
        if (faq.notes != null && faq.notes!.trim().isNotEmpty) ...[
          const SizedBox(height: 16),
          AppText.subText(context, 'Notes', fw: 1),
          const SizedBox(height: 6),
          AppText.subText(context, faq.notes!),
        ],
        const SizedBox(height: 20),
        AppText.paraText(
          context,
          'Created ${Fmt.date(faq.created)}  ·  Updated ${Fmt.date(faq.updated)}',
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ],
    );
  }

  Widget _chip(BuildContext context, String label, Color color) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(6),
    ),
    child: AppText.paraText(context, label, color: color, fw: 0),
  );
}
