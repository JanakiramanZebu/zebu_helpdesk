import 'package:flutter/material.dart';

import '../../res/zebu_theme.dart';
import '../../res/zebu_spacing.dart';
import '../../res/zebu_text_styles.dart';

/// Contextual bulk-action bar shown above a list table while one or more rows
/// are selected. Renders "{n} selected", the caller-supplied [actions], and a
/// trailing Clear button. Sits in the same slot the [SegmentedTabBar] occupies
/// so the toolbar height doesn't jump when selection toggles on/off.
class WebBulkBar extends StatelessWidget {
  const WebBulkBar({
    super.key,
    required this.count,
    required this.onClear,
    required this.actions,
  });

  final int count;
  final VoidCallback onClear;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final t = ZebuTheme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: ZebuSpacing.s4,
        vertical: ZebuSpacing.s2,
      ),
      decoration: BoxDecoration(
        color: t.accentSoft,
        border: Border(bottom: BorderSide(color: t.borderSubtle, width: 1)),
      ),
      child: Row(
        children: [
          Text(
            '$count selected',
            style: ZebuTextStyles.small(context).copyWith(
              color: t.accent,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(width: ZebuSpacing.s3),
          Expanded(
            child: Wrap(
              spacing: ZebuSpacing.s2,
              runSpacing: ZebuSpacing.s2,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: actions,
            ),
          ),
          const SizedBox(width: ZebuSpacing.s2),
          WebBulkButton(
            icon: Icons.close_rounded,
            label: 'Clear',
            onTap: (_) => onClear(),
          ),
        ],
      ),
    );
  }
}

/// Ghost button used inside a [WebBulkBar]. [onTap] receives the button's own
/// [BuildContext] so callers can anchor an `showAppDropdown` menu directly
/// under the button (e.g. Assign / Status / Priority pickers).
class WebBulkButton extends StatefulWidget {
  const WebBulkButton({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
    this.tone,
    this.hasMenu = false,
  });

  final IconData icon;
  final String label;
  final void Function(BuildContext buttonContext) onTap;

  /// Foreground/accent tone; defaults to the primary text color. Pass
  /// `t.danger` for destructive actions.
  final Color? tone;

  /// When true, a trailing chevron hints the button opens a menu.
  final bool hasMenu;

  @override
  State<WebBulkButton> createState() => _WebBulkButtonState();
}

class _WebBulkButtonState extends State<WebBulkButton> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final t = ZebuTheme.of(context);
    final fg = widget.tone ?? t.textPrimary;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: Builder(
        builder: (buttonContext) => GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => widget.onTap(buttonContext),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 100),
            height: 30,
            padding: const EdgeInsets.symmetric(horizontal: ZebuSpacing.s3),
            decoration: BoxDecoration(
              color: _hover ? t.bgHover : t.bgElevated,
              border: Border.all(color: t.borderSubtle, width: 1),
              borderRadius: BorderRadius.circular(ZebuRadius.rSm),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(widget.icon, size: 15, color: fg),
                const SizedBox(width: 6),
                Text(
                  widget.label,
                  style: ZebuTextStyles.small(context).copyWith(
                    color: fg,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (widget.hasMenu) ...[
                  const SizedBox(width: 2),
                  Icon(Icons.expand_more, size: 15, color: fg),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
