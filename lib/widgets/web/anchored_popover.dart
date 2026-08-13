import 'package:flutter/material.dart';

import '../../res/zebu_text_styles.dart';
import '../../res/zebu_theme.dart';

/// Geometry and the popover route shared by the anchored surfaces in
/// `lib/widgets/web/` — the property menu and the date picker.
///
/// Both hang a panel off a value that sits at the **right** edge of its row, so
/// both right-align to the trigger, and both have to flip upward when the row
/// is near the bottom of a scrolling dialog. That arithmetic was written for
/// `showZebuPropertyMenu`; the date picker would have had to copy it verbatim,
/// which is what this file exists to prevent.

/// The root overlay's render box for [anchorContext], or null when there is
/// none to measure against.
RenderBox? zebuOverlayBox(BuildContext anchorContext) {
  final render = Overlay.of(
    anchorContext,
    rootOverlay: true,
  ).context.findRenderObject();
  return render is RenderBox ? render : null;
}

/// [anchorContext]'s bounds in the root overlay's coordinate space, or null if
/// its box is missing or unattached — a context that has already been disposed,
/// or one that never got laid out.
Rect? zebuAnchorRect(BuildContext anchorContext, RenderBox overlay) {
  final box = anchorContext.findRenderObject();
  if (box is! RenderBox || !box.attached) return null;
  return Rect.fromPoints(
    box.localToGlobal(Offset.zero, ancestor: overlay),
    box.localToGlobal(box.size.bottomRight(Offset.zero), ancestor: overlay),
  );
}

// --- Popover tones ---------------------------------------------------------
// From the approved mock, with dark counterparts so a popover survives a theme
// flip. One definition for every anchored surface: the menu and the picker sit
// on the same card, a hairline apart, and must not drift.

/// The card itself.
Color zebuPopoverPanel(ZebuTheme t) => t.bgElevated;

/// Its hairline border.
Color zebuPopoverEdge(ZebuTheme t) =>
    t.isLight ? const Color(0xFFE1E4E8) : t.borderSubtle;

/// Fill behind the selected row or day.
Color zebuPopoverSelectedBg(ZebuTheme t) =>
    t.isLight ? const Color(0xFFE8F4FD) : const Color(0x2E2F81F7);

/// Fill under the pointer, and the resting fill of an inset control.
Color zebuPopoverHoverBg(ZebuTheme t) =>
    t.isLight ? const Color(0xFFF6F8FA) : const Color(0xFF21262D);

/// Primary label ink.
Color zebuPopoverInk(ZebuTheme t) =>
    t.isLight ? const Color(0xFF121212) : t.textPrimary;

/// Secondary ink — muted entries, weekday headings, disabled days.
Color zebuPopoverInkMuted(ZebuTheme t) =>
    t.isLight ? const Color(0xFF6B6B6B) : const Color(0xFF8B949E);

/// Destructive label on a popover — Clear on the date picker.
///
/// Pinned from the mock rather than taken from `t.danger`, which is a brighter
/// `#FF1717` tuned for badges and error borders and reads hot as a text link.
/// Dark is the existing dark-mode danger step, since the mock only specifies
/// the light pair.
Color zebuPopoverDanger(ZebuTheme t) =>
    t.isLight ? const Color(0xFFC40024) : const Color(0xFFF85149);

/// Its hover pill.
Color zebuPopoverDangerBg(ZebuTheme t) =>
    t.isLight ? const Color(0xFFFDECEC) : const Color(0xFF2D1117);

/// The shadow every popover casts.
const List<BoxShadow> kZebuPopoverShadow = [
  BoxShadow(color: Color(0x2910182B), blurRadius: 32, offset: Offset(0, 12)),
];

/// A popover hung off [anchor]: right-aligned to it, opening downward when
/// there is room below and upward when there is not.
class ZebuAnchoredRoute<T> extends PopupRoute<T> {
  ZebuAnchoredRoute({
    required this.anchor,
    required this.overlaySize,
    required this.width,
    required this.estimatedHeight,
    required this.builder,
    this.gap = 6,
  });

  final Rect anchor;
  final Size overlaySize;
  final double width;

  /// Only decides which way the panel opens — the panel sizes itself. An
  /// estimate is enough because being wrong costs a flip, not a clipped panel.
  final double estimatedHeight;

  final WidgetBuilder builder;
  final double gap;

  @override
  Color? get barrierColor => null;
  @override
  bool get barrierDismissible => true;
  @override
  String? get barrierLabel => 'Dismiss';
  @override
  Duration get transitionDuration => const Duration(milliseconds: 120);

  @override
  Widget buildPage(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
  ) {
    const margin = 8.0;
    final spaceBelow = overlaySize.height - anchor.bottom - gap - margin;
    final spaceAbove = anchor.top - gap - margin;

    // Prefer downward, and go up only when down does not fit and up has more
    // room. When neither fits — a short browser window, or a row low in a
    // scrolling dialog — take the roomier side and cap the panel to it rather
    // than letting it hang off the screen, which is what a plain
    // "does it fit below?" test does.
    final openDown = estimatedHeight <= spaceBelow || spaceBelow >= spaceAbove;
    final maxHeight = (openDown ? spaceBelow : spaceAbove).clamp(
      120.0,
      double.infinity,
    );

    var left = anchor.right - width;
    if (left + width > overlaySize.width - 8) {
      left = overlaySize.width - 8 - width;
    }
    if (left < 8) left = 8;

    final top = openDown ? anchor.bottom + gap : null;
    final bottom = openDown ? null : overlaySize.height - anchor.top + gap;

    return Stack(
      children: [
        Positioned(
          left: left,
          top: top,
          bottom: bottom,
          // Width must be pinned here. A `Positioned` without one offers its
          // child unbounded width, and a stretch-aligned Column inside then
          // asks for infinity and asserts. It is also what makes the
          // right-edge alignment above correct — `left` is derived from it.
          width: width,
          child: FadeTransition(
            opacity: animation,
            child: SlideTransition(
              position:
                  Tween<Offset>(
                    begin: Offset(0, openDown ? -0.03 : 0.03),
                    end: Offset.zero,
                  ).animate(
                    CurvedAnimation(parent: animation, curve: Curves.easeOut),
                  ),
              // The cap is what keeps an oversized panel on screen. Panels are
              // expected to scroll their own body when they hit it.
              child: ConstrainedBox(
                constraints: BoxConstraints(maxHeight: maxHeight),
                child: Builder(builder: builder),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Filter box at the top of a popover. Borderless - the panel is already a card,
/// and a second outline inside it read as a field floating on a field.
class ZebuPopoverSearch extends StatelessWidget {
  const ZebuPopoverSearch({
    required this.controller,
    required this.onChanged,
    this.hint = 'Search',
  });

  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  final String hint;

  @override
  Widget build(BuildContext context) {
    final t = ZebuTheme.of(context);
    return Container(
      height: 32,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: zebuPopoverHoverBg(t),
        borderRadius: BorderRadius.circular(7),
      ),
      child: Row(
        children: [
          Icon(Icons.search, size: 15, color: zebuPopoverInkMuted(t)),
          const SizedBox(width: 6),
          Expanded(
            child: TextField(
              controller: controller,
              onChanged: onChanged,
              autofocus: true,
              cursorColor: t.accent,
              style: ZebuTextStyles.small(
                context,
              ).copyWith(fontSize: 13, color: zebuPopoverInk(t)),
              decoration: InputDecoration(
                isDense: true,
                filled: false,
                contentPadding: EdgeInsets.zero,
                hintText: hint,
                hintStyle: ZebuTextStyles.small(
                  context,
                ).copyWith(fontSize: 13, color: zebuPopoverInkMuted(t)),
                // Every border slot, not just `border` - the global
                // `inputDecorationTheme` sets `enabledBorder` and
                // `focusedBorder`, and those beat `border` outright.
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                disabledBorder: InputBorder.none,
                errorBorder: InputBorder.none,
                focusedErrorBorder: InputBorder.none,
              ),
            ),
          ),
          // Listens to the controller rather than relying on the panel to
          // rebuild: a remote search debounces its `onChanged`, so keying the
          // button off the panel's state would leave it a beat behind what is
          // actually in the field.
          ValueListenableBuilder<TextEditingValue>(
            valueListenable: controller,
            builder: (context, value, _) => value.text.isEmpty
                ? const SizedBox.shrink()
                : _SearchClearBtn(
                    onTap: () {
                      controller.clear();
                      // Tell the panel too — clearing the text is a filter
                      // change like any other, and a remote search has to go
                      // back and fetch the unfiltered page.
                      onChanged('');
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

/// Empties the filter without closing the menu. Absent while the field is
/// empty — there is nothing to clear, and a permanent X beside a permanent
/// magnifier is two glyphs for one small box.
class _SearchClearBtn extends StatefulWidget {
  const _SearchClearBtn({required this.onTap});
  final VoidCallback onTap;

  @override
  State<_SearchClearBtn> createState() => _SearchClearBtnState();
}

class _SearchClearBtnState extends State<_SearchClearBtn> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final t = ZebuTheme.of(context);
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: Padding(
          padding: const EdgeInsets.only(left: 4),
          child: Icon(
            Icons.close_rounded,
            size: 14,
            color: _hover ? zebuPopoverInk(t) : zebuPopoverInkMuted(t),
          ),
        ),
      ),
    );
  }
}
