import 'package:flutter/material.dart';

import '../../../core/format.dart';
import '../../../core/theme/app_text.dart';
import '../../../core/theme/app_theme.dart';
import '../../../models/reports.dart';
import '../../../widgets/skeleton.dart';
import '../../../widgets/states.dart';

/// The chrome of the Reports page: a stack of labelled cards over the download
/// button, kept out of the screen so the screen reads as the page's structure
/// rather than its pixels.

/// A labelled card wrapping a group of rows.
class ReportSectionCard extends StatelessWidget {
  const ReportSectionCard({
    super.key,
    required this.title,
    required this.children,
    this.trailing,
  });

  final String title;
  final List<Widget> children;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 12, 8, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 0, 8, 6),
              child: Row(
                children: [
                  Expanded(
                    child: AppText.captionText(
                      context,
                      title.toUpperCase(),
                      color: scheme.onSurfaceVariant,
                      fw: 2,
                    ),
                  ),
                  if (trailing != null) trailing!,
                ],
              ),
            ),
            ...children,
          ],
        ),
      ),
    );
  }
}

/// One tappable filter row with an optional clear affordance.
class ReportFilterRow extends StatelessWidget {
  const ReportFilterRow({
    super.key,
    required this.icon,
    required this.label,
    required this.value,
    required this.onTap,
    this.onClear,
  });

  final IconData icon;
  final String label;
  final String value;
  final VoidCallback onTap;
  final VoidCallback? onClear;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
        child: Row(
          children: [
            Icon(icon, size: 18, color: scheme.onSurfaceVariant),
            const SizedBox(width: 12),
            Expanded(child: AppText.custmText(context, label, fs: 14, fw: 0)),
            Flexible(
              child: AppText.paraText(
                context,
                value,
                color: scheme.onSurfaceVariant,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (onClear != null)
              IconButton(
                visualDensity: VisualDensity.compact,
                tooltip: 'Clear',
                icon: const Icon(Icons.close, size: 16),
                onPressed: onClear,
              )
            else
              Icon(Icons.chevron_right, color: scheme.onSurfaceVariant),
          ],
        ),
      ),
    );
  }
}

/// A single-select row rendered as chips — the shape osTicket uses for its
/// short, fixed option lists, of which task status is the one that survives
/// (`All` / `Open` / `Closed`, the only three values the endpoint reads).
class ReportChipsRow<T> extends StatelessWidget {
  const ReportChipsRow({
    super.key,
    required this.icon,
    required this.label,
    required this.options,
    required this.value,
    required this.onChanged,
  });

  final IconData icon;
  final String label;

  /// Option value paired with its display label, in the order to show them.
  final List<(T, String)> options;
  final T value;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 18, color: scheme.onSurfaceVariant),
              const SizedBox(width: 12),
              AppText.custmText(context, label, fs: 14, fw: 0),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final (key, text) in options)
                ChoiceChip(
                  label: Text(text),
                  selected: key == value,
                  onSelected: (_) => onChanged(key),
                  visualDensity: VisualDensity.compact,
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// "You currently have access to N tickets." — the web's blue info bar.
///
/// The count is the type's **unfiltered** visibility total, exactly as on the
/// web: `GET /reports/exports` reports what the agent can see, not a preview of
/// what the current filters would export.
class ReportAccessBanner extends StatelessWidget {
  const ReportAccessBanner({
    super.key,
    required this.loading,
    required this.count,
    required this.label,
  });

  final bool loading;
  final int? count;
  final String label;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.brand.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppTheme.brand.withValues(alpha: 0.25)),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.insert_chart_outlined,
            size: 20,
            color: AppTheme.brand,
          ),
          const SizedBox(width: 12),
          Expanded(child: _body(context, scheme)),
        ],
      ),
    );
  }

  Widget _body(BuildContext context, ColorScheme scheme) {
    // Shaped like the loaded state so the banner keeps its height.
    if (loading) {
      return const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          SkeletonBox(width: 190, height: 14),
          SizedBox(height: 6),
          SkeletonBox(width: 130, height: 10),
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        AppText.subText(
          context,
          'You currently have access to ${Fmt.count(count ?? 0)} $label.',
          fw: 1,
        ),
        const SizedBox(height: 2),
        AppText.captionText(
          context,
          'Filters below will narrow the export.',
          color: scheme.onSurfaceVariant,
        ),
      ],
    );
  }
}

/// A soft notice strip — used for what the server tells the screen it cannot
/// do, rather than for anything the user can act on.
class ReportNotice extends StatelessWidget {
  const ReportNotice(this.message, {super.key, this.tone = AppTheme.warning});

  final String message;
  final Color tone;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: tone.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.warning_amber_rounded, size: 18, color: tone),
          const SizedBox(width: 10),
          Expanded(child: AppText.paraText(context, message)),
        ],
      ),
    );
  }
}

/// The column grid, with the web's `(All / None)` shortcuts.
///
/// Columns arrive from the server in catalog order and are exported in the
/// order they are sent, so what is listed here is the order of the file.
class ReportColumnsCard extends StatelessWidget {
  const ReportColumnsCard({
    super.key,
    required this.columns,
    required this.selected,
    required this.onToggle,
    required this.onAll,
    required this.onNone,
    this.loading = false,
  });

  final List<ReportColumn> columns;
  final Set<String> selected;
  final void Function(String key, bool on) onToggle;
  final VoidCallback onAll;
  final VoidCallback onNone;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    if (loading) {
      return const ReportSectionCard(
        title: 'Columns',
        children: [
          Padding(
            padding: EdgeInsets.symmetric(horizontal: 8, vertical: 10),
            child: SkeletonBox(width: 200, height: 14),
          ),
          Padding(
            padding: EdgeInsets.symmetric(horizontal: 8, vertical: 10),
            child: SkeletonBox(width: 160, height: 14),
          ),
          Padding(
            padding: EdgeInsets.symmetric(horizontal: 8, vertical: 10),
            child: SkeletonBox(width: 180, height: 14),
          ),
          Padding(
            padding: EdgeInsets.symmetric(horizontal: 8, vertical: 10),
            child: SkeletonBox(width: 140, height: 14),
          ),
        ],
      );
    }
    return ReportSectionCard(
      title: 'Columns',
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          AppText.captionText(
            context,
            '${selected.length}/${columns.length}',
            color: scheme.onSurfaceVariant,
          ),
          const SizedBox(width: 4),
          TextButton(
            onPressed: onAll,
            style: TextButton.styleFrom(
              visualDensity: VisualDensity.compact,
              padding: const EdgeInsets.symmetric(horizontal: 8),
            ),
            child: const Text('All'),
          ),
          TextButton(
            onPressed: onNone,
            style: TextButton.styleFrom(
              visualDensity: VisualDensity.compact,
              padding: const EdgeInsets.symmetric(horizontal: 8),
            ),
            child: const Text('None'),
          ),
        ],
      ),
      children: [
        for (final c in columns)
          CheckboxListTile(
            dense: true,
            controlAffinity: ListTileControlAffinity.leading,
            contentPadding: const EdgeInsets.symmetric(horizontal: 8),
            value: selected.contains(c.key),
            title: AppText.custmText(context, c.label, fs: 14, fw: 0),
            // Custom form fields are what differs between installs, so they
            // are marked rather than left indistinguishable from the fixed set.
            subtitle: c.isCustomField
                ? AppText.captionText(
                    context,
                    'Custom field',
                    color: scheme.onSurfaceVariant,
                  )
                : null,
            onChanged: (on) => onToggle(c.key, on == true),
          ),
      ],
    );
  }
}

/// The download call-to-action, and the only one there is.
///
/// `scp/reports.php` submits to a single green **Download CSV**, and the
/// dashboard's statistics picker ends in the same button. Both files are the
/// server's own, fetched from a signed `GET /reports/download` link, so there
/// is no second format to offer and no second rendering to keep honest.
class ReportDownloadButton extends StatelessWidget {
  const ReportDownloadButton({
    super.key,
    required this.busy,
    required this.enabled,
    required this.onPressed,
    this.disabledHint = 'Nothing to export yet.',
  });

  final bool busy;
  final bool enabled;
  final VoidCallback onPressed;

  /// Why the button is dead. Shown only while [enabled] is false — an enabled
  /// button explains itself.
  final String disabledHint;

  @override
  Widget build(BuildContext context) {
    if (busy) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 12),
        child: LoadingView(),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (!enabled) ...[
          AppText.paraText(
            context,
            disabledHint,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
          const SizedBox(height: 10),
        ],
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: enabled ? onPressed : null,
            icon: const Icon(Icons.download_rounded, size: 18),
            label: const Text('Download CSV'),
          ),
        ),
      ],
    );
  }
}
