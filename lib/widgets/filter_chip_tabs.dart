import 'package:flutter/material.dart';

import '../core/format.dart';
import '../core/theme/app_text.dart';

/// A horizontally-scrollable row of selectable filter chips, matching the
/// dashboard's count-chip language: each chip carries a small colored status
/// dot, a label, and an optional count. The selected chip fills with a
/// brand-tinted surface and brand border/text; the rest stay flat with a
/// hairline border.
///
/// Drop-in replacement for the underline [SegmentedTabs] on list screens, but
/// visually consistent with the dashboard's [FocusStrip] / count chips.
class FilterChipTabs extends StatefulWidget {
  const FilterChipTabs({
    super.key,
    required this.items,
    required this.selectedKey,
    required this.onSelected,
    this.counts,
    this.colorFor,
  });

  /// (key, label) pairs in display order.
  final List<({String key, String label})> items;
  final String selectedKey;
  final ValueChanged<String> onSelected;

  /// Optional per-key counts shown after the label.
  final Map<String, int>? counts;

  /// Optional dot color per key (view semantics). Falls back to the primary
  /// tone when null.
  final Color Function(String key)? colorFor;

  @override
  State<FilterChipTabs> createState() => _FilterChipTabsState();
}

class _FilterChipTabsState extends State<FilterChipTabs> {
  final _scroll = ScrollController();
  final _keys = <String, GlobalKey>{};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _ensureVisible());
  }

  @override
  void didUpdateWidget(covariant FilterChipTabs old) {
    super.didUpdateWidget(old);
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
      alignment: 0.5,
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 36,
      child: ListView.separated(
        controller: _scroll,
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
        itemCount: widget.items.length,
        separatorBuilder: (_, _) => const SizedBox(width: 6),
        itemBuilder: (context, i) {
          final item = widget.items[i];
          return _Chip(
            key: _keys.putIfAbsent(item.key, GlobalKey.new),
            label: item.label,
            count: widget.counts?[item.key],
            dotColor: widget.colorFor?.call(item.key),
            selected: item.key == widget.selectedKey,
            onTap: () => widget.onSelected(item.key),
          );
        },
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({
    super.key,
    required this.label,
    required this.count,
    required this.dotColor,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final int? count;
  final Color? dotColor;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final dot = dotColor ?? scheme.primary;
    final borderColor = selected
        ? scheme.primary.withValues(alpha: 0.5)
        : scheme.outlineVariant;
    final fill = selected ? scheme.primary.withValues(alpha: 0.08) : scheme.surface;

    return Material(
      color: fill,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: borderColor),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 6,
                height: 6,
                decoration: BoxDecoration(color: dot, shape: BoxShape.circle),
              ),
              const SizedBox(width: 6),
              AppText.custmText(
                context,
                label,
                fs: 13,
                fw: selected ? 2 : 1,
                color: selected ? scheme.primary : scheme.onSurface,
              ),
              if (count != null) ...[
                const SizedBox(width: 5),
                AppText.custmText(
                  context,
                  Fmt.count(count!),
                  fs: 13,
                  fw: 1,
                  color: selected
                      ? scheme.primary
                      : scheme.onSurfaceVariant,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
