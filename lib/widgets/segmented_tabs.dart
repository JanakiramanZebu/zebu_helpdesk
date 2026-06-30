import 'package:flutter/material.dart';

/// Mynt Plus *portfolio*-style filter tabs: a horizontally scrollable row of
/// labels with an animated underline under the selected item (brand-colored,
/// bold) sitting on a full-width hairline baseline. The selected tab is always
/// scrolled into view — including when [selectedKey] is changed externally
/// (e.g. tapping a dashboard stat tile), so the row never stays static.
///
/// Each tab can carry a small count [badge] (e.g. the number of tickets in that
/// view) via the [counts] map keyed by item key.
class SegmentedTabs extends StatefulWidget {
  const SegmentedTabs({
    super.key,
    required this.items,
    required this.selectedKey,
    required this.onSelected,
    this.counts,
  });

  /// (key, label) pairs in display order.
  final List<({String key, String label})> items;
  final String selectedKey;
  final ValueChanged<String> onSelected;

  /// Optional per-tab counts shown as a small badge after the label.
  final Map<String, int>? counts;

  @override
  State<SegmentedTabs> createState() => _SegmentedTabsState();
}

class _SegmentedTabsState extends State<SegmentedTabs> {
  final _scroll = ScrollController();
  final _keys = <String, GlobalKey>{};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _ensureVisible());
  }

  @override
  void didUpdateWidget(covariant SegmentedTabs old) {
    super.didUpdateWidget(old);
    // Scroll the newly-selected tab into view whether the change came from a
    // tap here or from another screen flipping [selectedKey].
    if (old.selectedKey != widget.selectedKey) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _ensureVisible());
    }
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _ensureVisible() {
    final ctx = _keys[widget.selectedKey]?.currentContext;
    if (ctx == null || !_scroll.hasClients) return;
    Scrollable.ensureVisible(
      ctx,
      alignment: 0.5, // center the selected tab horizontally
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return SizedBox(
      height: 40,
      child: DecoratedBox(
        // Full-width hairline baseline the selected underline sits on.
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(color: scheme.outlineVariant, width: 1),
          ),
        ),
        child: ListView.builder(
          controller: _scroll,
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          itemCount: widget.items.length,
          itemBuilder: (context, i) {
            final item = widget.items[i];
            final selected = item.key == widget.selectedKey;
            final count = widget.counts?[item.key];
            final key = _keys.putIfAbsent(item.key, GlobalKey.new);
            final color = selected ? scheme.primary : scheme.onSurfaceVariant;
            return GestureDetector(
              key: key,
              behavior: HitTestBehavior.opaque,
              onTap: () => widget.onSelected(item.key),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                padding: const EdgeInsets.symmetric(horizontal: 16),
                decoration: BoxDecoration(
                  border: Border(
                    bottom: BorderSide(
                      color: selected ? scheme.primary : Colors.transparent,
                      width: 2.5,
                    ),
                  ),
                ),
                child: Center(
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      AnimatedDefaultTextStyle(
                        duration: const Duration(milliseconds: 180),
                        style: TextStyle(
                          fontSize: 14.5,
                          fontWeight: selected
                              ? FontWeight.w700
                              : FontWeight.w500,
                          color: color,
                        ),
                        child: Text(item.label),
                      ),
                      // if (count != null) ...[
                      //   const SizedBox(width: 6),
                      //   _Badge(count: count, selected: selected),
                      // ],
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge({required this.count, required this.selected});

  final int count;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final bg = selected
        ? scheme.primary.withValues(alpha: 0.14)
        : scheme.onSurfaceVariant.withValues(alpha: 0.14);
    final fg = selected ? scheme.primary : scheme.onSurfaceVariant;
    return Container(
      constraints: const BoxConstraints(minWidth: 20),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(9),
      ),
      child: Text(
        count > 999 ? '999+' : '$count',
        textAlign: TextAlign.center,
        style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: fg),
      ),
    );
  }
}
