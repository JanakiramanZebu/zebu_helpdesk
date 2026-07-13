import 'package:flutter/material.dart';

import '../../../core/format.dart';
import '../../../core/theme/app_text.dart';

/// One chip in a [CountChipRow]: a label, its count badge and a tap target.
class CountChip {
  const CountChip({
    required this.label,
    required this.value,
    required this.color,
    required this.onTap,
  });
  final String label;
  final int value;
  final Color color;
  final VoidCallback onTap;
}

/// A horizontally-scrollable row of filter chips, each showing a label and a
/// count. Used to expose the secondary ticket/task views (Mine, Answered,
/// Closed, Collaborator…) compactly instead of a second wall of stat boxes —
/// this is the "filters" surface, and each chip jumps to the pre-filtered list.
class CountChipRow extends StatelessWidget {
  const CountChipRow({super.key, required this.chips});

  final List<CountChip> chips;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 36,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 4),
        physics: const BouncingScrollPhysics(),
        itemCount: chips.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, i) => _Chip(chip: chips[i]),
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.chip});
  final CountChip chip;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Material(
      color: scheme.surface,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: chip.onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: scheme.outlineVariant),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 7,
                height: 7,
                decoration: BoxDecoration(
                  color: chip.color,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 8),
              AppText.subText(context, chip.label, fw: 1),
              const SizedBox(width: 7),
              AppText.subText(
                context,
                Fmt.count(chip.value),
                color: scheme.onSurfaceVariant,
                fw: 1,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
