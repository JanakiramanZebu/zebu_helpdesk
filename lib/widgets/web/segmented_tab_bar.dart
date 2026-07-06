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
class SegmentedTabBar<T> extends StatelessWidget {
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
  Widget build(BuildContext context) {
    final t = WebTokens.of(context);
    return Container(
      decoration: showBaseline
          ? BoxDecoration(
              border: Border(
                bottom: BorderSide(color: t.borderSubtle, width: 1),
              ),
            )
          : null,
      padding: padding,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            for (final item in items)
              _Tab<T>(
                item: item,
                active: item.value == selected,
                onTap: () => onSelect(item.value),
              ),
          ],
        ),
      ),
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
        ? WebTokens.accent
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
                  color:
                      widget.active ? WebTokens.accent : Colors.transparent,
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
        color: active ? WebTokens.accent : Colors.transparent,
        borderRadius: BorderRadius.circular(WebTokens.rFull),
        border: Border.all(
          color: active ? WebTokens.accent : t.borderSubtle,
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
