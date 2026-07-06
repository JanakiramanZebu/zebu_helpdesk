import 'package:flutter/material.dart';

import '../../features/dashboard/web/_tokens.dart';

/// Width below which the header switches from a side-by-side layout
/// (title | trailing) to a stacked layout (title on top, trailing below).
/// Chosen so the trailing cluster — typically a filter button + search
/// field — stays legible when the list column shrinks under an open
/// detail panel instead of forcing the title to wrap mid-word.
const double _kHeaderStackBreakpoint = 640;

/// Standard page header used across every list screen.
///
/// Layout is responsive:
///   - When the header row is wide enough (≥ [_kHeaderStackBreakpoint]),
///     title sits on the left and [trailing] on the right, per the
///     reference design.
///   - When the row is narrower (typically after a detail panel opens
///     and pushes the list column below the breakpoint), [trailing]
///     drops to a new line under the title so the title never wraps
///     mid-word.
///
/// An optional [subtitle] renders as muted text under the title for pages
/// that carry a secondary line ("3 open · 1 overdue", etc.); when the
/// header stacks, the trailing sits below the subtitle.
///
/// The header brings its own vertical rhythm and does NOT include the
/// bottom hairline that separates it from the list body — callers wrap
/// the content underneath in its own container if they want a separator.
class PageHeader extends StatelessWidget {
  const PageHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.trailing,
    this.padding = const EdgeInsets.fromLTRB(
      WebTokens.s6,
      WebTokens.s5,
      WebTokens.s6,
      WebTokens.s4,
    ),
  });

  final String title;
  final String? subtitle;
  final Widget? trailing;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final t = WebTokens.of(context);
    // Title + optional subtitle column — same in both layouts, extracted
    // so the wide / stacked branches can compose it consistently.
    final titleColumn = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(title, style: t.hero),
        if (subtitle != null) ...[
          const SizedBox(height: 4),
          Text(subtitle!, style: t.bodySm),
        ],
      ],
    );

    return Padding(
      padding: padding,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final hasTrailing = trailing != null;
          final wide = constraints.maxWidth >= _kHeaderStackBreakpoint;
          if (!hasTrailing || wide) {
            return Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(child: titleColumn),
                if (hasTrailing) ...[
                  const SizedBox(width: WebTokens.s4),
                  trailing!,
                ],
              ],
            );
          }
          // Stacked: title on top, trailing wraps below. Align trailing
          // to the row's start so it lines up with the title's left edge
          // — reads as a continuation of the header, not a floating chip.
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              titleColumn,
              const SizedBox(height: WebTokens.s3),
              trailing!,
            ],
          );
        },
      ),
    );
  }
}
