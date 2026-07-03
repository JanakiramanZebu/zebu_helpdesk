import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/format.dart';
import '../../core/theme/app_text.dart';
import '../../models/faq.dart';
import '../../providers.dart';
import '../../widgets/attachment_tile.dart';
import '../../widgets/states.dart';

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

  @override
  Widget build(BuildContext context) {
    final faq = _faq;
    return Scaffold(
      appBar: AppBar(title: const Text('Article')),
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
              faq.published ? (faq.type ?? 'Public') : (faq.type ?? 'Internal'),
              faq.published
                  ? theme.colorScheme.primary
                  : theme.colorScheme.outline,
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
