import 'package:flutter/material.dart';

import '../../features/dashboard/web/_tokens.dart';

/// A single tab entry consumed by [SegmentedTabBar]. The [count], when
/// non-null, renders as a small tinted pill beside the label — brand-tinted
/// on the active tab, neutral on inactive tabs.
class SegmentedTabItem<T> {
  const SegmentedTabItem({
    required this.value,
    required this.label,
    this.count,
  });
  final T value;
  final String label;
  final int? count;
}

/// Text-tab row with a 2 px brand accent underline on the selected tab.
/// ClickUp-inspired: airy, minimal, no card frame, count pill inline.
///
/// The bar itself only draws a subtle bottom hairline underneath all tabs
/// (the "baseline") so unselected tabs don't look like they're floating.
/// Callers can suppress that baseline by passing [showBaseline] = false.
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
    this.padding = const EdgeInsets.symmetric(horizontal: WebTokens.s6),
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
    final target = (_scroll.offset + delta)
        .clamp(0.0, _scroll.position.maxScrollExtent);
    _scroll.animateTo(
      target,
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOut,
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = WebTokens.of(context);
    return Container(
      decoration: widget.showBaseline
          ? BoxDecoration(
              border: Border(
                bottom: BorderSide(color: t.borderSubtle, width: 1),
              ),
            )
          : null,
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
                    WidgetsBinding.instance
                        .addPostFrameCallback((_) => _recompute());
                    return false;
                  },
                  // Suppress the platform scrollbar — the chevrons carry
                  // the affordance, and Flutter web's default gutter would
                  // add a horizontal grey stripe under the tabs.
                  child: ScrollConfiguration(
                    behavior: ScrollConfiguration.of(context)
                        .copyWith(scrollbars: false),
                    child: SingleChildScrollView(
                      controller: _scroll,
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.end,
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
    final t = WebTokens.of(context);
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
              color: _hover && widget.visible
                  ? t.accent
                  : t.textSecondary,
            ),
          ),
        ),
      ),
    );
    // IgnorePointer when hidden so the reserved space doesn't intercept
    // clicks meant for tabs on the very edge.
    return IgnorePointer(
      ignoring: !widget.visible,
      child: child,
    );
  }
}

class _Tab<T> extends StatefulWidget {
  const _Tab({
    required this.item,
    required this.active,
    required this.onTap,
  });
  final SegmentedTabItem<T> item;
  final bool active;
  final VoidCallback onTap;

  @override
  State<_Tab<T>> createState() => _TabState<T>();
}

class _TabState<T> extends State<_Tab<T>> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final t = WebTokens.of(context);
    final fg = widget.active
        ? t.accent
        : (_hover ? t.textPrimary : t.textSecondary);
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: Padding(
          padding: const EdgeInsets.only(right: WebTokens.s6),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 12),
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(
                  color: widget.active ? t.accent : Colors.transparent,
                  width: 2,
                ),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  widget.item.label,
                  style: TextStyle(
                    fontSize: 13.5,
                    fontWeight:
                        widget.active ? FontWeight.w600 : FontWeight.w500,
                    color: fg,
                    letterSpacing: 0.1,
                  ),
                ),
                if (widget.item.count != null) ...[
                  const SizedBox(width: 6),
                  _CountPill(
                    count: widget.item.count!,
                    active: widget.active,
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

/// Premium count pill.
///
/// * Active tab — **filled brand-blue chip** with white bold text and a
///   soft accent glow, so the current view is unmistakable at a glance.
/// * Inactive — hairline outlined chip on the page background, secondary
///   text. Reads as a quiet counter rather than a competing badge.
///
/// Both variants are fully-rounded and animate their bg / border / shadow
/// on a shared 140 ms `easeOut` curve, so switching tabs feels smooth
/// rather than a hard "state flip".
class _CountPill extends StatelessWidget {
  const _CountPill({required this.count, required this.active});
  final int count;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final t = WebTokens.of(context);
    return AnimatedContainer(
      duration: const Duration(milliseconds: 140),
      curve: Curves.easeOut,
      constraints: const BoxConstraints(minWidth: 22, minHeight: 18),
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 1),
      decoration: BoxDecoration(
        color: active ? t.accent : Colors.transparent,
        borderRadius: BorderRadius.circular(WebTokens.rFull),
        border: Border.all(
          color: active ? t.accent : t.borderSubtle,
          width: 1,
        ),
        boxShadow: active ? WebTokens.accentGlow : null,
      ),
      alignment: Alignment.center,
      child: Text(
        '$count',
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: active ? Colors.white : t.textSecondary,
          height: 1.2,
          letterSpacing: 0.2,
        ).copyWith(fontFeatures: const [FontFeature.tabularFigures()]),
      ),
    );
  }
}
