import 'package:fleather/fleather.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:parchment/codecs.dart';

import '../core/api/api_exception.dart';
import '../core/format.dart';
import '../core/theme/app_text.dart';
import '../models/canned.dart';
import '../models/faq.dart';
import '../providers.dart';
import 'app_sheet.dart';
import 'pickers.dart';
import 'states.dart';

/// Compact quick-action buttons ("Saved replies" / "Insert FAQ") that live in
/// the composer's top control strip, next to the expand button. Icon-only to
/// stay compact; long-press shows the tooltip. Tapping opens the picker sheet
/// and the host wires the result back into the editor.
class ComposerActionChips extends StatelessWidget {
  const ComposerActionChips({
    super.key,
    required this.onCanned,
    required this.onFaq,
  });

  final VoidCallback onCanned;
  final VoidCallback onFaq;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          tooltip: 'Saved replies',
          visualDensity: VisualDensity.compact,
          icon: Icon(
            Icons.quickreply_outlined,
            size: 20,
            color: scheme.onSurfaceVariant,
          ),
          onPressed: onCanned,
        ),
        IconButton(
          tooltip: 'Insert FAQ',
          visualDensity: VisualDensity.compact,
          icon: Icon(
            Icons.menu_book_outlined,
            size: 20,
            color: scheme.onSurfaceVariant,
          ),
          onPressed: onFaq,
        ),
      ],
    );
  }
}

/// Inserts [html] as rich content at the composer's current cursor. Falls back
/// to plain text if the HTML can't be decoded into the editor's document model
/// (helpdesk canned/FAQ bodies occasionally carry tags Fleather can't map).
void insertRichHtml(FleatherController controller, String html) {
  final doc = controller.document;
  // The document always ends in a trailing "\n", so the last valid insertion
  // offset is length - 1. Clamp the (possibly stale) cursor into range.
  final index = controller.selection.baseOffset.clamp(0, doc.length - 1);
  try {
    final delta = parchmentHtml.decode(html).toDelta();
    final change = Delta()..retain(index);
    var inserted = 0;
    for (final op in delta.toList()) {
      change.push(op);
      inserted += op.length;
    }
    controller.compose(
      change,
      selection: TextSelection.collapsed(offset: index + inserted),
      source: ChangeSource.local,
    );
  } catch (_) {
    final text = Fmt.stripHtml(html).trim();
    if (text.isEmpty) return;
    controller.replaceText(
      index,
      0,
      text,
      selection: TextSelection.collapsed(offset: index + text.length),
    );
  }
}

// --- Attachment source sheet (Camera / Photo / File) ------------------------

/// Presents the attachment-source chooser as a bottom sheet (replacing the old
/// popup menu) and returns the picked [AttachSource], or null if dismissed.
Future<AttachSource?> pickAttachSource(BuildContext context) {
  return showAppSheet<AttachSource>(
    context: context,
    builder: (_) => const _AttachSourceSheet(),
  );
}

class _AttachSourceSheet extends StatelessWidget {
  const _AttachSourceSheet();

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 8),
          _row(
            context,
            icon: Icons.photo_camera_outlined,
            label: 'Camera',
            source: AttachSource.camera,
          ),
          _row(
            context,
            icon: Icons.image_outlined,
            label: 'Photo',
            source: AttachSource.photos,
          ),
          _row(
            context,
            icon: Icons.attach_file,
            label: 'File',
            source: AttachSource.files,
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  Widget _row(
    BuildContext context, {
    required IconData icon,
    required String label,
    required AttachSource source,
  }) {
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      onTap: () => Navigator.pop(context, source),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
        child: Row(
          children: [
            Icon(icon, size: 24, color: scheme.onSurfaceVariant),
            const SizedBox(width: 20),
            AppText.subText(context, label, fw: 1),
          ],
        ),
      ),
    );
  }
}

// --- Canned responses picker ------------------------------------------------

/// Bottom-sheet list of enabled canned responses. Returns the chosen response,
/// or null if dismissed. The caller expands/inserts its body.
Future<CannedResponse?> pickCannedResponse(
  BuildContext context,
  WidgetRef ref,
) {
  return showAppSheet<CannedResponse>(
    context: context,
    builder: (_) => const _CannedPickerSheet(),
  );
}

class _CannedPickerSheet extends ConsumerStatefulWidget {
  const _CannedPickerSheet();

  @override
  ConsumerState<_CannedPickerSheet> createState() => _CannedPickerSheetState();
}

class _CannedPickerSheetState extends ConsumerState<_CannedPickerSheet> {
  List<CannedResponse> _items = [];
  bool _loading = true;
  Object? _error;

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
      final page = await ref
          .read(cannedRepositoryProvider)
          .list(page: 1, limit: 100);
      if (!mounted) return;
      setState(() {
        _items = page.items.where((c) => c.isEnabled).toList();
        _loading = false;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AppSheet(
      title: 'Canned responses',
      scrollable: false,
      padding: EdgeInsets.zero,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.6,
        ),
        child: _loading
            ? const Padding(
                padding: EdgeInsets.all(32),
                child: Center(child: CircularProgressIndicator()),
              )
            : _error != null
            ? Padding(
                padding: const EdgeInsets.all(16),
                child: ErrorView(
                  error: _error!,
                  compact: true,
                  onRetry: _load,
                ),
              )
            : _items.isEmpty
            ? Padding(
                padding: const EdgeInsets.all(24),
                child: Center(
                  child: AppText.subText(context, 'No canned responses'),
                ),
              )
            : ListView.builder(
                padding: const EdgeInsets.only(bottom: 8),
                itemCount: _items.length,
                itemBuilder: (context, i) {
                  final c = _items[i];
                  return _PickerRow(
                    icon: Icons.quickreply_outlined,
                    title: c.title,
                    subtitle: Fmt.stripHtml(c.body),
                    onTap: () => Navigator.pop(context, c),
                  );
                },
              ),
      ),
    );
  }
}

// --- FAQ (knowledgebase) picker ---------------------------------------------

/// Searchable bottom-sheet over the knowledgebase. Returns the chosen article
/// (list variant â€” the caller fetches the full answer if needed), or null.
Future<Faq?> pickFaqArticle(BuildContext context, WidgetRef ref) {
  return showAppSheet<Faq>(
    context: context,
    builder: (_) => const _FaqPickerSheet(),
  );
}

class _FaqPickerSheet extends ConsumerStatefulWidget {
  const _FaqPickerSheet();

  @override
  ConsumerState<_FaqPickerSheet> createState() => _FaqPickerSheetState();
}

class _FaqPickerSheetState extends ConsumerState<_FaqPickerSheet> {
  final _search = TextEditingController();
  List<Faq> _items = [];
  bool _loading = true;
  Object? _error;
  String _lastQuery = '';

  @override
  void initState() {
    super.initState();
    _load('');
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _load(String q) async {
    _lastQuery = q;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final page = await ref
          .read(faqRepositoryProvider)
          .search(q: q.isEmpty ? null : q, page: 1, limit: 50);
      if (!mounted) return;
      setState(() {
        _items = page.items;
        _loading = false;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AppSheet(
      title: 'Insert FAQ',
      scrollable: false,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SheetSearchField(
            controller: _search,
            hintText: 'Search the knowledgebase...',
            onSubmitted: _load,
            onClear: () => _load(''),
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: MediaQuery.of(context).size.height * 0.45,
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                ? ErrorView(
                    error: _error!,
                    compact: true,
                    onRetry: () => _load(_lastQuery),
                  )
                : _items.isEmpty
                ? Center(child: AppText.subText(context, 'No articles found'))
                : ListView.builder(
                    itemCount: _items.length,
                    itemBuilder: (context, i) {
                      final f = _items[i];
                      return _PickerRow(
                        icon: Icons.help_outline,
                        title: f.question,
                        subtitle: f.category?.name ?? 'General',
                        onTap: () => Navigator.pop(context, f),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

/// Shared list row for the canned/FAQ pickers: a tinted rounded leading icon,
/// a bold title and a single muted subtitle line.
class _PickerRow extends StatelessWidget {
  const _PickerRow({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: scheme.primary.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(9),
              ),
              child: Icon(icon, size: 18, color: scheme.primary),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  AppText.subText(
                    context,
                    title,
                    fw: 2,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  AppText.paraText(
                    context,
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    color: scheme.onSurfaceVariant,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
