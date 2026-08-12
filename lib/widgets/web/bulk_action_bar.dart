import 'package:flutter/material.dart';

import '../../res/zebu_spacing.dart';
import '../../res/zebu_text_styles.dart';
import '../app_dropdown.dart';

/// One action offered while rows are selected.
class WebBulkAction {
  const WebBulkAction({
    required this.icon,
    required this.label,
    required this.onTap,
    this.hasMenu = false,
    this.primary = false,
    this.destructive = false,
  });

  final IconData icon;
  final String label;

  /// Receives the button's own context so the caller can anchor a dropdown
  /// directly beneath it.
  final void Function(BuildContext anchor) onTap;

  /// Shows a trailing caret — the action opens a picker rather than firing.
  final bool hasMenu;

  /// Rendered inline on the bar. Everything else folds into the overflow
  /// menu: five equal buttons made the one an agent presses nine times out of
  /// ten as hard to find as the one they press monthly.
  final bool primary;

  final bool destructive;
}

/// Floating action bar shown while rows are selected.
///
/// A dark pill over the table rather than a strip above it. The old strip had
/// two problems no amount of styling fixes: it inserted a row, so the whole
/// table jumped ~44 px the moment a box was ticked and back again when it was
/// cleared — with rows moving under the pointer mid-click — and it scrolled
/// away, so selecting fifty rows and scrolling to check the last one left the
/// actions off-screen.
///
/// Host it in a [Stack] over the table, not in the column with it.
class WebBulkBar extends StatelessWidget {
  const WebBulkBar({
    super.key,
    required this.count,
    required this.onClear,
    required this.actions,
    this.noun = 'selected',
  });

  final int count;
  final VoidCallback onClear;
  final List<WebBulkAction> actions;

  /// Trailing word after the count — "selected" reads fine for both screens.
  final String noun;

  @override
  Widget build(BuildContext context) {
    final inline = actions.where((a) => a.primary).toList();
    final overflow = actions.where((a) => !a.primary).toList();

    // Dark in both themes. An overlay that floats above the page shouldn't
    // share the page's surface colour, or it reads as part of the table.
    const fill = Color(0xFF1D2939);

    return Align(
      alignment: Alignment.bottomCenter,
      child: Padding(
        // Clear of the viewport edge — at 20 px the pill looked like it
        // was falling off the bottom of the window.
        padding: const EdgeInsets.only(bottom: ZebuSpacing.s8),
        child: Material(
          color: Colors.transparent,
          child: Container(
            padding: const EdgeInsets.symmetric(
              horizontal: ZebuSpacing.s2 + 2,
              vertical: ZebuSpacing.s2,
            ),
            decoration: BoxDecoration(
              color: fill,
              borderRadius: BorderRadius.circular(ZebuRadius.rLg),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x40101828),
                  blurRadius: 24,
                  offset: Offset(0, 8),
                ),
              ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: ZebuSpacing.s3,
                  ),
                  child: Text(
                    '$count $noun',
                    style: ZebuTextStyles.small(
                      context,
                      color: Colors.white,
                      fontWeight: ZebuFonts.semiBold,
                    ).withTabularNums(),
                  ),
                ),
                _Sep(),
                for (final a in inline) ...[
                  const SizedBox(width: 2),
                  _BarButton(action: a),
                ],
                if (overflow.isNotEmpty) ...[
                  const SizedBox(width: 2),
                  _OverflowButton(actions: overflow),
                ],
                _Sep(),
                const SizedBox(width: 2),
                _BarButton(
                  action: WebBulkAction(
                    icon: Icons.close_rounded,
                    label: 'Clear',
                    onTap: (_) => onClear(),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Hairline divider between the bar's zones.
class _Sep extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Container(
    width: 1,
    height: 18,
    margin: const EdgeInsets.symmetric(horizontal: ZebuSpacing.s2),
    color: Colors.white.withValues(alpha: 0.16),
  );
}

class _BarButton extends StatefulWidget {
  const _BarButton({required this.action});
  final WebBulkAction action;

  @override
  State<_BarButton> createState() => _BarButtonState();
}

class _BarButtonState extends State<_BarButton> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final a = widget.action;
    final fg = a.destructive ? const Color(0xFFFDA29B) : Colors.white;
    return Builder(
      builder: (btnCtx) => MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => a.onTap(btnCtx),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 100),
            height: 32,
            padding: const EdgeInsets.symmetric(horizontal: ZebuSpacing.s3),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              // Idle is the hover tone at zero alpha, never
              // `Colors.transparent` — that is transparent *black*, and on a
              // dark bar a fill lerping from it flashes darker on the way in.
              color: _hover
                  ? Colors.white.withValues(alpha: 0.12)
                  : Colors.white.withValues(alpha: 0),
              borderRadius: BorderRadius.circular(ZebuRadius.rXs),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(a.icon, size: 15, color: fg),
                const SizedBox(width: 6),
                Text(
                  a.label,
                  style: ZebuTextStyles.small(
                    context,
                    color: fg,
                    fontWeight: ZebuFonts.medium,
                  ),
                ),
                if (a.hasMenu) ...[
                  const SizedBox(width: 2),
                  Icon(Icons.expand_more, size: 14, color: fg),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The `⋯` button holding every non-primary action.
class _OverflowButton extends StatefulWidget {
  const _OverflowButton({required this.actions});
  final List<WebBulkAction> actions;

  @override
  State<_OverflowButton> createState() => _OverflowButtonState();
}

class _OverflowButtonState extends State<_OverflowButton> {
  bool _hover = false;

  Future<void> _open(BuildContext anchor) async {
    final chosen = await showAppDropdown<int>(
      anchor,
      entries: [
        for (var i = 0; i < widget.actions.length; i++)
          AppDropdownItem<int>(
            value: i,
            label: widget.actions[i].label,
            icon: widget.actions[i].icon,
          ),
      ],
    );
    if (chosen == null || !anchor.mounted) return;
    // Fire against the ⋯ button's context so an action that opens its own
    // picker anchors under the bar rather than at the top-left of the screen.
    widget.actions[chosen].onTap(anchor);
  }

  @override
  Widget build(BuildContext context) {
    return Builder(
      builder: (btnCtx) => MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => _open(btnCtx),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 100),
            width: 32,
            height: 32,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: _hover
                  ? Colors.white.withValues(alpha: 0.12)
                  : Colors.white.withValues(alpha: 0),
              borderRadius: BorderRadius.circular(ZebuRadius.rXs),
            ),
            child: const Icon(
              Icons.more_horiz_rounded,
              size: 18,
              color: Colors.white,
            ),
          ),
        ),
      ),
    );
  }
}
