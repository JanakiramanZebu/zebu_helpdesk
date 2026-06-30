import 'package:flutter/material.dart';

/// A compact rounded-square selection checkbox used by the flat list rows and
/// the select-all header — filled with the brand color and a check when on.
class SelectionCheck extends StatelessWidget {
  const SelectionCheck({super.key, required this.selected, this.size = 22});

  final bool selected;
  final double size;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 140),
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: selected ? scheme.primary : Colors.transparent,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: selected ? scheme.primary : scheme.outline,
          width: 1.6,
        ),
      ),
      child: selected
          ? Icon(Icons.check, size: size * 0.66, color: scheme.onPrimary)
          : null,
    );
  }
}
