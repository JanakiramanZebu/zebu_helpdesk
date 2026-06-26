import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/format.dart';
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
      body: _loading
          ? const LoadingView()
          : _error != null
              ? ErrorView(error: _error!, onRetry: _load)
              : _buildBody(context, faq!),
    );
  }

  Widget _buildBody(BuildContext context, Faq faq) {
    final theme = Theme.of(context);
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(
          faq.question,
          style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _chip(
              context,
              faq.published ? (faq.type ?? 'Public') : (faq.type ?? 'Internal'),
              faq.published ? theme.colorScheme.primary : theme.colorScheme.outline,
            ),
            if (faq.category != null)
              _chip(context, faq.category!.name, theme.colorScheme.secondary),
          ],
        ),
        const SizedBox(height: 16),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              Fmt.stripHtml(faq.answer),
              style: theme.textTheme.bodyMedium,
            ),
          ),
        ),
        if (faq.attachments.isNotEmpty) ...[
          const SizedBox(height: 16),
          Text('Attachments', style: theme.textTheme.titleSmall),
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
          Text('Notes', style: theme.textTheme.titleSmall),
          const SizedBox(height: 6),
          Text(faq.notes!, style: theme.textTheme.bodyMedium),
        ],
        const SizedBox(height: 20),
        Text(
          'Created ${Fmt.date(faq.created)}  ·  Updated ${Fmt.date(faq.updated)}',
          style: theme.textTheme.bodySmall
              ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
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
