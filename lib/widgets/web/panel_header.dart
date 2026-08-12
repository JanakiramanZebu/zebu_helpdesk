import 'package:flutter/material.dart';

import '../app_dropdown.dart';
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

/// Square ghost icon button for a detail panel's header cluster.
///
/// No border and no fill at rest — the header is already a bounded strip, so
/// outlining each of three buttons boxed the boxes. Hover raises [bgHover].
class ZebuPanelIconBtn extends StatefulWidget {
  const ZebuPanelIconBtn({
    super.key,
    required this.icon,
    required this.onTap,
    this.tooltip,
  });
  final IconData icon;
  final VoidCallback onTap;
  final String? tooltip;

  @override
  State<ZebuPanelIconBtn> createState() => _ZebuPanelIconBtnState();
}

class _ZebuPanelIconBtnState extends State<ZebuPanelIconBtn> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final t = ZebuTheme.of(context);
    final child = MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 100),
          width: 32,
          height: 32,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: _hover ? t.bgHover : t.bgElevated,
            borderRadius: BorderRadius.circular(ZebuRadius.rSm),
          ),
          child: Icon(widget.icon, size: 18, color: t.textPrimary),
        ),
      ),
    );
    return widget.tooltip == null
        ? child
        : Tooltip(message: widget.tooltip!, child: child);
  }
}

/// The `Actions ⌄` ghost pill in a detail panel's header.
///
/// The caller supplies the menu entries — those are model-specific (a ticket
/// can be claimed, a task can be closed) — but the trigger's chrome and the
/// menu it opens are shared, because they had already drifted: one panel drew
/// a 5 px radius with a 14 px medium label, the other 6 px with 12 px
/// semibold, on two buttons sitting in the same position on two screens.
class ZebuPanelActionsBtn extends StatefulWidget {
  const ZebuPanelActionsBtn({
    super.key,
    required this.entries,
    required this.onSelected,
    this.label = 'Actions',
  });

  final List<AppDropdownEntry<String>> entries;
  final Future<void> Function(String value) onSelected;
  final String label;

  @override
  State<ZebuPanelActionsBtn> createState() => _ZebuPanelActionsBtnState();
}

class _ZebuPanelActionsBtnState extends State<ZebuPanelActionsBtn> {
  bool _hover = false;

  Future<void> _open() async {
    final chosen = await showAppDropdown<String>(
      context,
      entries: widget.entries,
    );
    if (chosen != null) await widget.onSelected(chosen);
  }

  @override
  Widget build(BuildContext context) {
    final t = ZebuTheme.of(context);
    return Tooltip(
      message: widget.label,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: _open,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 100),
            height: 32,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              color: _hover ? t.bgHover : t.bgElevated,
              border: Border.all(color: t.borderSubtle, width: 1),
              borderRadius: BorderRadius.circular(5),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  widget.label,
                  style: ZebuTextStyles.body(
                    context,
                    color: t.textPrimary,
                    fontWeight: ZebuFonts.medium,
                  ),
                ),
                const SizedBox(width: 4),
                Icon(Icons.expand_more, size: 16, color: t.textPrimary),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Placeholder for [ZebuPanelTitle] while the record loads.
///
/// Two muted bars in the shape the real header will take, rather than the
/// word "Loading…". Hosts that can pass a list-row summary never see this;
/// the ones that only know an internal id — the notifications inbox, the
/// dashboard — do, and for them the id is not the number an agent would
/// recognise, so there is nothing truthful to show yet. A skeleton says
/// "this is arriving" without claiming anything and without the header
/// changing height when it does.
class ZebuPanelTitleSkeleton extends StatelessWidget {
  const ZebuPanelTitleSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    final t = ZebuTheme.of(context);
    Widget bar(double width, double height) => Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: t.bgTertiary,
        borderRadius: BorderRadius.circular(3),
      ),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [bar(96, 10), const SizedBox(height: 6), bar(280, 14)],
    );
  }
}
