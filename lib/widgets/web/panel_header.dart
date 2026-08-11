import 'package:flutter/material.dart';

import '../../res/zebu_spacing.dart';
import '../../res/zebu_text_styles.dart';
import '../../res/zebu_theme.dart';

/// Record identity for a detail panel — a quiet meta line over the title.
///
/// The id and the meta line used to share the title's row, which cost the
/// title ~140 px of the only line it gets. Stacked, the title runs the full
/// width of the header and truncates far later; the meta line costs no height
/// the header wasn't already reserving.
///
/// Shared by the ticket and task panels: both show `#id · someone` over a
/// long subject that has nowhere else on screen to be read in full.
class ZebuPanelTitle extends StatelessWidget {
  const ZebuPanelTitle({
    super.key,
    required this.id,
    required this.title,
    this.meta,
  });

  /// Record number, rendered with a leading `#`.
  final String id;

  /// The long line — a ticket subject or a task title.
  final String title;

  /// Optional second crumb after the id: a requester, an assignee, a channel.
  final String? meta;

  @override
  Widget build(BuildContext context) {
    final t = ZebuTheme.of(context);
    final crumb = (meta ?? '').trim();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Text(
              '#$id',
              // Tabular figures rather than a second typeface: the reason a
              // number wants monospace is even columns, and that is exactly
              // what tabular figures give inside the app's own face.
              style: ZebuTextStyles.eyebrow(
                context,
                color: t.textSlateMuted,
              ).withTabularNums(),
            ),
            if (crumb.isNotEmpty) ...[
              const SizedBox(width: ZebuSpacing.s2),
              Container(
                width: 3,
                height: 3,
                decoration: BoxDecoration(
                  color: t.borderDefault,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: ZebuSpacing.s2),
              Flexible(
                child: Text(
                  crumb,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: ZebuTextStyles.eyebrow(
                    context,
                    color: t.textSlateMuted,
                  ),
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: 1),
        // Full title on hover — a truncated title is the one thing in this
        // header an agent actually needs to read in full, and there is
        // nowhere else on the screen it appears.
        Tooltip(
          message: title,
          waitDuration: const Duration(milliseconds: 400),
          child: Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            softWrap: false,
            style: ZebuTextStyles.sectionTitle(
              context,
              color: t.textPrimary,
              fontWeight: ZebuFonts.semiBold,
            ).copyWith(height: 1.25),
          ),
        ),
      ],
    );
  }
}

/// Small square chevron button — collapses a detail pane, or brings it back.
class ZebuRailToggle extends StatefulWidget {
  const ZebuRailToggle({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  @override
  State<ZebuRailToggle> createState() => _ZebuRailToggleState();
}

class _ZebuRailToggleState extends State<ZebuRailToggle> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final t = ZebuTheme.of(context);
    return Tooltip(
      message: widget.tooltip,
      waitDuration: const Duration(milliseconds: 400),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            width: 26,
            height: 26,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              // Idle is the hover tone at zero alpha, never
              // `Colors.transparent` — that is transparent *black*, and
              // lerping from it drags the fill through a grey flash.
              color: _hover
                  ? t.surfaceMuted
                  : t.surfaceMuted.withValues(alpha: 0),
              border: Border.all(color: t.borderSubtle, width: 1),
              borderRadius: BorderRadius.circular(ZebuRadius.rXs),
            ),
            child: Icon(
              widget.icon,
              size: 15,
              color: _hover ? t.textSlate : t.iconMuted,
            ),
          ),
        ),
      ),
    );
  }
}
