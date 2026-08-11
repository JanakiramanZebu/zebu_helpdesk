import 'package:flutter/material.dart';

import '../../res/zebu_theme.dart';
import '../../res/zebu_spacing.dart';
import '../svg_icon.dart';
import '../../res/zebu_text_styles.dart';

/// ClickUp-style menu section: a small-caps eyebrow header followed by a
/// stack of [MenuRow]s. The trailing divider is drawn by the section so a
/// popover assembling multiple sections doesn't need to interleave manual
/// [Divider] widgets.
///
/// Pass `title: null` for a "pinned" section (e.g. a header) that shouldn't
/// carry an eyebrow.
class MenuSection extends StatelessWidget {
  const MenuSection({
    super.key,
    this.title,
    required this.children,
    this.showDivider = true,
  });

  final String? title;
  final List<Widget> children;
  final bool showDivider;

  @override
  Widget build(BuildContext context) {
    final t = ZebuTheme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (title != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(
              ZebuSpacing.s3 + 4,
              ZebuSpacing.s3,
              ZebuSpacing.s3 + 4,
              ZebuSpacing.s1,
            ),
            child: Text(
              title!.toUpperCase(),
              style: ZebuTextStyles.eyebrow(context),
            ),
          ),
        ...children,
        if (showDivider)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Container(height: 1, color: t.borderSubtle),
          ),
      ],
    );
  }
}

/// A single tap-target row inside a [MenuSection]. Renders as an inset pill
/// so hover fills stop before the popover edge (a common ClickUp detail).
///
/// Pass either a Material [icon] or a mobile [svg] asset (`Assets.*`) for
/// the leading glyph — [svg] takes precedence. [trailing] can be used for
/// pins / badges / chevrons.
class MenuRow extends StatefulWidget {
  const MenuRow({
    super.key,
    this.icon,
    this.svg,
    required this.label,
    required this.onTap,
    this.trailing,
    this.destructive = false,
  }) : assert(icon != null || svg != null, 'Provide icon or svg');

  final IconData? icon;
  final String? svg;
  final String label;
  final VoidCallback? onTap;
  final Widget? trailing;
  final bool destructive;

  @override
  State<MenuRow> createState() => _MenuRowState();
}

class _MenuRowState extends State<MenuRow> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final t = ZebuTheme.of(context);
    final disabled = widget.onTap == null;
    final tone = widget.destructive ? t.danger : t.textPrimary;
    return MouseRegion(
      cursor: disabled ? SystemMouseCursors.basic : SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 100),
          height: 36,
          margin: const EdgeInsets.symmetric(horizontal: 6),
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            color: _hover && !disabled
                ? (widget.destructive ? t.dangerLight : t.bgHover)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(ZebuRadius.rSm),
          ),
          child: Row(
            children: [
              if (widget.svg != null)
                SvgIcon(widget.svg!, size: 16, color: tone)
              else
                Icon(widget.icon, size: 16, color: tone),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  widget.label,
                  style: ZebuTextStyles.body(
                    context,
                  ).copyWith(color: tone, fontWeight: FontWeight.w500),
                ),
              ),
              if (widget.trailing != null) widget.trailing!,
            ],
          ),
        ),
      ),
    );
  }
}
