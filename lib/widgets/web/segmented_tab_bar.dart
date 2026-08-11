import 'package:flutter/material.dart';

import '../../res/zebu_theme.dart';
import '../../res/zebu_spacing.dart';
import '../../res/zebu_text_styles.dart';

/// A single tab entry consumed by [SegmentedTabBar].
///
/// The [count], when non-null, renders as a small raised **superscript**
/// after the label (`Open⁴`) rather than a separate chip — it reads as an
/// annotation on the view rather than a second element competing with it.
///
/// [icon] is the leading glyph. [dot] is the older 6×6 status dot, kept for
/// callers that haven't been given an icon set; when both are absent the tab
/// is label-only.
class SegmentedTabItem<T> {
  const SegmentedTabItem({
    required this.value,
    required this.label,
    this.count,
    this.icon,
    this.dot,
  });
  final T value;
  final String label;
  final int? count;

  /// Leading glyph. Takes precedence over [dot].
  final IconData? icon;

  /// Legacy status dot, used only when [icon] is null.
  final Color? dot;
}

/// Pill-chip tab row matching the mobile app's `FilterChipTabs`: each tab is
/// a rounded chip with a colored status dot, label, and inline count.
/// Selected = brand-tinted fill (`accent @ 0.08`) + brand border; unselected
/// = flat surface chip with a hairline border.
///
/// [showBaseline] is retained for API compatibility but no longer paints —
/// the chips carry their own frames, so no baseline is needed.
///
/// When the tab row overflows its slot, chevron buttons appear at the
/// leading/trailing edges — click either to page the strip ~half a
/// viewport in that direction. Buttons hide themselves at the ends so
/// the affordance only shows when there's actually more to scroll to.
class SegmentedTabBar<T> extends StatefulWidget {
  const SegmentedTabBar({
    super.key,
    required this.items,
    required this.selected,
    required this.onSelect,
    this.showBaseline = true,
    this.padding = const EdgeInsets.symmetric(horizontal: ZebuSpacing.s6),
  });

  final List<SegmentedTabItem<T>> items;
  final T selected;
  final ValueChanged<T> onSelect;
  final bool showBaseline;
  final EdgeInsetsGeometry padding;

  @override
  State<SegmentedTabBar<T>> createState() => _SegmentedTabBarState<T>();
}

class _SegmentedTabBarState<T> extends State<SegmentedTabBar<T>> {
  final ScrollController _scroll = ScrollController();
  bool _canLeft = false;
  bool _canRight = false;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_recompute);
    // Initial state must wait for layout — the scroll controller has no
    // position/extent until the SingleChildScrollView has been laid out
    // once, so schedule the first check for after this frame.
    WidgetsBinding.instance.addPostFrameCallback((_) => _recompute());
  }

  @override
  void dispose() {
    _scroll.removeListener(_recompute);
    _scroll.dispose();
    super.dispose();
  }

  void _recompute() {
    if (!mounted || !_scroll.hasClients) return;
    final p = _scroll.position;
    final left = p.pixels > 0.5;
    final right = p.pixels < p.maxScrollExtent - 0.5;
    if (left != _canLeft || right != _canRight) {
      setState(() {
        _canLeft = left;
        _canRight = right;
      });
    }
  }

  void _scrollBy(double delta) {
    if (!_scroll.hasClients) return;
    final target = (_scroll.offset + delta).clamp(
      0.0,
      _scroll.position.maxScrollExtent,
    );
    _scroll.animateTo(
      target,
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOut,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: widget.padding,
      child: LayoutBuilder(
        builder: (context, c) {
          // Page by ~half the visible width — enough to reveal the next
          // couple of tabs without overshooting past what the user just saw.
          final step = c.hasBoundedWidth ? c.maxWidth * 0.5 : 160.0;
          return Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              _ScrollChevron(
                icon: Icons.chevron_left_rounded,
                visible: _canLeft,
                onTap: () => _scrollBy(-step),
              ),
              Expanded(
                // Metrics notifications fire when the scrollable's content
                // or viewport size changes (item count, resize) — schedule a
                // recompute so the chevrons appear/disappear as needed.
                child: NotificationListener<ScrollMetricsNotification>(
                  onNotification: (_) {
                    WidgetsBinding.instance.addPostFrameCallback(
                      (_) => _recompute(),
                    );
                    return false;
                  },
                  // Suppress the platform scrollbar — the chevrons carry
                  // the affordance, and Flutter web's default gutter would
                  // add a horizontal grey stripe under the tabs.
                  child: ScrollConfiguration(
                    behavior: ScrollConfiguration.of(
                      context,
                    ).copyWith(scrollbars: false),
                    child: SingleChildScrollView(
                      controller: _scroll,
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          for (final item in widget.items)
                            _Tab<T>(
                              item: item,
                              active: item.value == widget.selected,
                              onTap: () => widget.onSelect(item.value),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              _ScrollChevron(
                icon: Icons.chevron_right_rounded,
                visible: _canRight,
                onTap: () => _scrollBy(step),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// Small edge chevron button. Kept in the layout via [Visibility] so tabs
/// don't shift horizontally when it appears — the space is always reserved
/// on both sides, and the button is only interactive/visible at the ends
/// where there's actually more content to scroll to.
class _ScrollChevron extends StatefulWidget {
  const _ScrollChevron({
    required this.icon,
    required this.visible,
    required this.onTap,
  });

  final IconData icon;
  final bool visible;
  final VoidCallback onTap;

  @override
  State<_ScrollChevron> createState() => _ScrollChevronState();
}

class _ScrollChevronState extends State<_ScrollChevron> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final t = ZebuTheme.of(context);
    final child = AnimatedOpacity(
      opacity: widget.visible ? 1 : 0,
      duration: const Duration(milliseconds: 140),
      curve: Curves.easeOut,
      child: MouseRegion(
        cursor: widget.visible
            ? SystemMouseCursors.click
            : SystemMouseCursors.basic,
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.visible ? widget.onTap : null,
          child: Container(
            width: 24,
            alignment: Alignment.center,
            color: Colors.transparent,
            child: Icon(
              widget.icon,
              size: 18,
              color: _hover && widget.visible ? t.accent : t.textSecondary,
            ),
          ),
        ),
      ),
    );
    // IgnorePointer when hidden so the reserved space doesn't intercept
    // clicks meant for tabs on the very edge.
    return IgnorePointer(ignoring: !widget.visible, child: child);
  }
}

class _Tab<T> extends StatefulWidget {
  const _Tab({required this.item, required this.active, required this.onTap});
  final SegmentedTabItem<T> item;
  final bool active;
  final VoidCallback onTap;

  @override
  State<_Tab<T>> createState() => _TabState<T>();
}

class _TabState<T> extends State<_Tab<T>> {
  bool _hover = false;

  /// Selected fill — the slate family's stronger step, matching the field
  /// glyph tiles in the ticket panel. Neutral rather than brand-blue: the
  /// label already carries the state, and a blue chip beside blue status
  /// values read as two different meanings for one colour.
  Color _activeFill(ZebuTheme t) => t.surfaceMutedStrong;

  /// Hover preview — one step lighter than [_activeFill], so hovering never
  /// looks like selecting.
  Color _hoverFill(ZebuTheme t) => t.surfaceMuted;

  @override
  Widget build(BuildContext context) {
    final t = ZebuTheme.of(context);
    final item = widget.item;

    // No borders and no brand tint: the selected tab is distinguished by a
    // soft filled pill and a stronger label, so a row of six views reads as
    // one quiet strip instead of six competing boxes.
    // Slate tones, matching the ticket panel's field rows: muted glyph-grey
    // when idle, the darker value tone when selected.
    final fg = widget.active ? t.textSlate : t.iconMuted;
    // Shared by the label and its badge count so the two never disagree.
    final weight = widget.active ? ZebuFonts.semiBold : ZebuFonts.medium;
    final bg = widget.active
        ? _activeFill(t)
        // Idle is the hover tone at zero alpha, never `Colors.transparent` —
        // that is transparent *black*, and lerping from it drags the fill
        // through a grey flash on the way in.
        : (_hover ? _hoverFill(t) : _hoverFill(t).withValues(alpha: 0));

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: Padding(
          padding: const EdgeInsets.only(right: ZebuSpacing.s1, bottom: 6),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 140),
            curve: Curves.easeOut,
            height: 34,
            padding: const EdgeInsets.symmetric(horizontal: ZebuSpacing.s3),
            decoration: BoxDecoration(
              color: bg,
              borderRadius: BorderRadius.circular(ZebuRadius.rXs),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (item.icon != null) ...[
                  Icon(item.icon, size: 18, color: fg),
                  const SizedBox(width: 6),
                ] else if (item.dot != null) ...[
                  Container(
                    width: 6,
                    height: 6,
                    decoration: BoxDecoration(
                      color: item.dot,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 6),
                ],
                // Label and count are one text run so the count rides the
                // label's baseline as a true superscript, rather than being
                // a separately-centred sibling in the Row.
                // Size is constant across both states — only the weight
                // shifts, so switching tabs never nudges the strip's layout.
                // Label 14, badge 13; semiBold when active, medium when not.
                Text(
                  item.label,
                  style: ZebuTextStyles.body(
                    context,
                    color: fg,
                    fontWeight: weight,
                  ),
                ),
                if (item.count != null) ...[
                  const SizedBox(width: 4),
                  // Raised as a sibling rather than a WidgetSpan inside the
                  // label: `Transform.translate` doesn't affect layout, so the
                  // count floats clear of the baseline without changing the
                  // row's height or the label's line box. Matches the ordersbook
                  // tabs in Mynt Plus Web.
                  Transform.translate(
                    offset: const Offset(0, -6),
                    child: Text(
                      '${item.count}',
                      style: ZebuTextStyles.body(
                        context,
                        color: fg,
                        fontWeight: weight,
                      ).copyWith(fontSize: 13).withTabularNums(),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
