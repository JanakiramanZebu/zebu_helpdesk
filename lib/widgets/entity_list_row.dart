import 'package:flutter/material.dart';

import '../core/theme/app_text.dart';
import '../core/theme/app_theme.dart';
import 'selection_check.dart';
import 'status_chip.dart';
import 'user_avatar.dart';

/// A neutral metadata chip descriptor (icon + label + danger flag). Lets model
/// adapters describe secondary chips without depending on widget internals.
class EntityMetaChip {
  const EntityMetaChip({
    required this.icon,
    required this.label,
    this.danger = false,
  });

  final IconData icon;
  final String label;
  final bool danger;
}

/// The model-agnostic data a list row needs to render. Both [Ticket] and [Task]
/// map to this so tickets and tasks share one row widget and stay visually
/// consistent by construction.
class EntityRowData {
  const EntityRowData({
    required this.number,
    required this.title,
    required this.statusName,
    required this.personName,
    required this.createdAgo,
    this.createdTooltip,
    this.priorityLabel,
    this.metaChips = const [],
    this.subtitleParts = const [],
    this.accentColor,
    this.danger = false,
    this.dangerLabel,
    this.dangerIcon = Icons.warning_amber_rounded,
    this.progress,
  });

  /// Display number, e.g. "008971" (rendered as "#008971").
  final String number;
  final String title;
  final String statusName;

  /// Requester (ticket) or assignee (task) shown in the footer / compact lead.
  final String personName;

  /// Relative created time, e.g. "3 days ago".
  final String createdAgo;
  final String? createdTooltip;

  /// Priority display name, or null if none.
  final String? priorityLabel;

  /// Secondary metadata chips (department, due date, …) for the card view.
  final List<EntityMetaChip> metaChips;

  /// Extra pieces joined into the compact-view subtitle (after the number),
  /// e.g. department name or progress percent.
  final List<String> subtitleParts;

  /// Left accent-bar color (priority-derived). Defaults to the theme outline.
  final Color? accentColor;

  /// A danger state (ticket overdue / task blocked): red border + icon + time.
  final bool danger;
  final String? dangerLabel;
  final IconData dangerIcon;

  /// 0..100 progress (tasks). Null hides the progress bar.
  final int? progress;
}

/// Shared list row for tickets and tasks. Renders a clean, dense card (default)
/// or a Gmail-style single-line [compact] row. Selection chrome (checkbox +
/// highlight) is built in. Design changes here apply to both features at once.
class EntityListRow extends StatelessWidget {
  const EntityListRow({
    super.key,
    required this.data,
    required this.onTap,
    this.selectionMode = false,
    this.selected = false,
    this.onToggle,
    this.compact = false,
  });

  final EntityRowData data;
  final VoidCallback onTap;
  final bool selectionMode;
  final bool selected;
  final VoidCallback? onToggle;
  final bool compact;

  static const _dangerColor = AppTheme.overdue;

  /// The left accent color encodes *attention level*, not raw priority, so the
  /// default "Normal" case stays neutral and genuinely urgent rows pop:
  /// overdue / High / Emergency → red, Medium → amber, everything else neutral.
  Color _accent(ColorScheme scheme) {
    if (data.danger) return _dangerColor;
    final p = (data.priorityLabel ?? '').toLowerCase();
    if (p.contains('emergency') || p.contains('high')) return AppTheme.overdue;
    if (p.contains('medium')) return AppTheme.warning;
    return scheme.outlineVariant; // normal / low / none → neutral
  }

  /// Whether to render a priority chip at all. "Normal" is the implicit default
  /// and adds noise, so it's suppressed — only meaningful priorities show.
  bool get _showPriority {
    final p = (data.priorityLabel ?? '').toLowerCase();
    return p.isNotEmpty && !p.contains('normal');
  }

  String get _semanticsLabel {
    final buf = StringBuffer('${data.number}, ${data.title}. Status ${data.statusName}.');
    if (data.priorityLabel != null) buf.write(' Priority ${data.priorityLabel}.');
    if (data.danger) buf.write(' ${data.dangerLabel ?? 'Attention'}.');
    return buf.toString();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      button: true,
      label: _semanticsLabel,
      child: compact ? _buildCompact(context, scheme) : _buildCard(context, scheme),
    );
  }

  // ── Card view ──────────────────────────────────────────────────────────────

  Widget _buildCard(BuildContext context, ColorScheme scheme) {
    final accent = _accent(scheme);

    // Border priority: selection > danger accent > default hairline (theme).
    final RoundedRectangleBorder? shape = selected
        ? RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(color: scheme.primary.withValues(alpha: 0.6)),
          )
        : data.danger
        ? RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(color: _dangerColor.withValues(alpha: 0.5)),
          )
        : null;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      color: selected ? scheme.primary.withValues(alpha: 0.06) : null,
      shape: shape,
      child: InkWell(
        onTap: selectionMode ? onToggle : onTap,
        onLongPress: onToggle,
        borderRadius: BorderRadius.circular(12),
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (!selectionMode) Container(width: 4, color: accent),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(14, 11, 12, 11),
                  child: Row(
                    children: [
                      if (selectionMode) ...[
                        SelectionCheck(selected: selected),
                        const SizedBox(width: 12),
                      ],
                      Expanded(child: _cardBody(context, scheme)),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _cardBody(BuildContext context, ColorScheme scheme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Header: id · person · time … status (right).
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            AppText.paraText(
              context,
              '#${data.number}',
              color: scheme.primary,
              fw: 2,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Tooltip(
                message: data.createdTooltip ?? '',
                child: AppText.paraText(
                  context,
                  data.createdAgo,
                  color: data.danger
                      ? _dangerColor
                      : scheme.onSurfaceVariant,
                  fw: data.danger ? 1 : 0,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
            const SizedBox(width: 8),
            if (data.danger)
              Padding(
                padding: const EdgeInsets.only(right: 6),
                child: Tooltip(
                  message: data.dangerLabel ?? '',
                  child: Icon(data.dangerIcon, size: 16, color: _dangerColor),
                ),
              ),
            StatusChip.status(data.statusName, dense: true),
          ],
        ),
        const SizedBox(height: 8),
        // Title — the primary anchor.
        AppText.subText(
          context,
          data.title,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          fw: 2,
          lineHeight: 1.25,
        ),
        // Secondary chip row: priority + metadata.
        if (_showPriority || data.metaChips.isNotEmpty) ...[
          const SizedBox(height: 9),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              if (_showPriority)
                StatusChip.priority(data.priorityLabel!, dense: true),
              for (final m in data.metaChips)
                MetaChip(icon: m.icon, label: m.label, danger: m.danger),
            ],
          ),
        ],
        if (data.progress != null && data.progress! > 0) ...[
          const SizedBox(height: 10),
          _ProgressBar(progress: data.progress!),
        ],
        const SizedBox(height: 10),
        // Footer: person avatar + name.
        Row(
          children: [
            UserAvatar(name: data.personName, radius: 11),
            const SizedBox(width: 8),
            Expanded(
              child: AppText.paraText(
                context,
                data.personName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                fw: 1,
                color: scheme.onSurface,
              ),
            ),
          ],
        ),
      ],
    );
  }

  // ── Compact view ─────────────────────────────────────────────────────────

  Widget _buildCompact(BuildContext context, ColorScheme scheme) {
    final statusColor = data.danger
        ? _dangerColor
        : StatusChip.status(data.statusName).color ?? AppTheme.open;
    final accent = _accent(scheme);

    return Material(
      color: selected
          ? scheme.primary.withValues(alpha: 0.06)
          : Colors.transparent,
      child: InkWell(
        onTap: selectionMode ? onToggle : onTap,
        onLongPress: onToggle,
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Priority accent rail — the card view's cue, kept edge-to-edge
              // here to match the inbox row's left rail.
              if (!selectionMode) Container(width: 4, color: accent),
              Expanded(
                child: Padding(
                  padding: EdgeInsets.fromLTRB(
                    selectionMode ? 16 : 12,
                    12,
                    16,
                    12,
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (selectionMode) ...[
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: SelectionCheck(selected: selected),
                        ),
                        const SizedBox(width: 14),
                      ] else ...[
                        _AvatarWithStatus(
                          name: data.personName,
                          statusColor: statusColor,
                          danger: data.danger,
                          dangerIcon: data.dangerIcon,
                        ),
                        const SizedBox(width: 14),
                      ],
                      Expanded(child: _compactBody(context, scheme)),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Inbox-style stacked body: a header line (id + time), the title as the
  /// scannable anchor, then a muted person/meta line with the status (and
  /// meaningful priority) chip on the right — mirroring the notification row.
  Widget _compactBody(BuildContext context, ColorScheme scheme) {
    // Number moves up to the header, so the footer is just person + any extra
    // parts (department / progress).
    final footer = [data.personName, ...data.subtitleParts].join('  ·  ');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        // Header: id (left) + created time (right).
        Row(
          children: [
            Expanded(
              child: AppText.paraText(
                context,
                '#${data.number}',
                color: scheme.primary,
                fw: 2,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 8),
            Tooltip(
              message: data.createdTooltip ?? '',
              child: AppText.captionText(
                context,
                data.createdAgo,
                color: data.danger ? _dangerColor : scheme.onSurfaceVariant,
                fw: data.danger ? 2 : 0,
              ),
            ),
          ],
        ),
        const SizedBox(height: 3),
        // Title — the primary anchor (up to 2 lines, like the inbox message).
        AppText.subText(
          context,
          data.title,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          fw: 2,
          lineHeight: 1.3,
        ),
        // Secondary metadata (department, due date, …). Compact drops the card's
        // full chip cluster, but these carry real signal (an overdue due date
        // especially), so surface them as a dense inline line rather than hide
        // them the way the priority/status chips are handled below.
        if (data.metaChips.isNotEmpty) ...[
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              for (final m in data.metaChips)
                MetaChip(icon: m.icon, label: m.label, danger: m.danger),
            ],
          ),
        ],
        const SizedBox(height: 6),
        // Footer: person + meta (left), priority + status chips (right).
        Row(
          children: [
            Expanded(
              child: AppText.paraText(
                context,
                footer,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                color: scheme.onSurfaceVariant,
              ),
            ),
            if (_showPriority) ...[
              const SizedBox(width: 8),
              StatusChip.priority(data.priorityLabel!, dense: true),
            ],
            const SizedBox(width: 8),
            StatusChip.status(data.statusName, dense: true),
          ],
        ),
      ],
    );
  }
}

/// Compact-view avatar with a corner status dot and an optional danger badge.
class _AvatarWithStatus extends StatelessWidget {
  const _AvatarWithStatus({
    required this.name,
    required this.statusColor,
    required this.danger,
    required this.dangerIcon,
  });

  final String name;
  final Color statusColor;
  final bool danger;
  final IconData dangerIcon;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Stack(
      children: [
        UserAvatar(name: name, radius: 19),
        Positioned(
          right: 0,
          bottom: 0,
          child: Container(
            width: 11,
            height: 11,
            decoration: BoxDecoration(
              color: statusColor,
              shape: BoxShape.circle,
              border: Border.all(color: scheme.surface, width: 2),
            ),
          ),
        ),
        if (danger)
          Positioned(
            left: 0,
            top: 0,
            child: Icon(dangerIcon, size: 12, color: AppTheme.overdue),
          ),
      ],
    );
  }
}

/// A labeled progress bar for the card view (tasks).
class _ProgressBar extends StatelessWidget {
  const _ProgressBar({required this.progress});
  final int progress;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      children: [
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: (progress / 100).clamp(0, 1),
              minHeight: 6,
              backgroundColor: scheme.outlineVariant.withValues(alpha: 0.4),
            ),
          ),
        ),
        const SizedBox(width: 8),
        AppText.captionText(
          context,
          '$progress%',
          color: scheme.onSurfaceVariant,
          fw: 1,
        ),
      ],
    );
  }
}
