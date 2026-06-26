import 'package:flutter/material.dart';

/// Mynt Plus-style segmented filter tabs: a scrollable row of pills where the
/// selected item gets a soft grey pill (`#F1F3F8`) and brand-colored bold
/// label, the rest are plain grey text. Replaces the Material `ChoiceChip` row.
class SegmentedTabs extends StatelessWidget {
  const SegmentedTabs({
    super.key,
    required this.items,
    required this.selectedKey,
    required this.onSelected,
  });

  /// (key, label) pairs in display order.
  final List<({String key, String label})> items;
  final String selectedKey;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final pill = isDark ? const Color(0xFF24242B) : const Color(0xFFF1F3F8);

    return SizedBox(
      height: 38,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        itemCount: items.length,
        separatorBuilder: (_, _) => const SizedBox(width: 6),
        itemBuilder: (context, i) {
          final item = items[i];
          final selected = item.key == selectedKey;
          return GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => onSelected(item.key),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              alignment: Alignment.center,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              decoration: BoxDecoration(
                color: selected ? pill : Colors.transparent,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                item.label,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                  color: selected
                      ? (isDark ? scheme.primary : scheme.primary)
                      : scheme.onSurfaceVariant,
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
