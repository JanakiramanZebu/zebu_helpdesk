import 'package:flutter/material.dart';

import '../../features/dashboard/web/_tokens.dart';

/// Tri-state selection checkbox shared by the list tables (inbox / tickets /
/// tasks) for row selection and header select-all. `value` semantics:
///   • true  → filled with the accent, white check glyph
///   • false → empty box with a hairline border
///   • null  → filled with the accent, minus glyph (indeterminate / "some")
class SelectCheckbox extends StatelessWidget {
  const SelectCheckbox({
    super.key,
    required this.value,
    required this.onChanged,
    this.tooltip,
  });

  final bool? value;
  final ValueChanged<bool?> onChanged;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final t = WebTokens.of(context);
    final checked = value == true;
    final indeterminate = value == null;
    final filled = checked || indeterminate;
    final box = AnimatedContainer(
      duration: const Duration(milliseconds: 100),
      width: 16,
      height: 16,
      decoration: BoxDecoration(
        color: filled ? t.accent : Colors.transparent,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(
          color: filled ? t.accent : t.borderStrong,
          width: 1.4,
        ),
      ),
      alignment: Alignment.center,
      child: filled
          ? Icon(
              indeterminate ? Icons.remove : Icons.check,
              size: 12,
              color: Colors.white,
            )
          : null,
    );
    final target = MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => onChanged(!checked),
        child: box,
      ),
    );
    if (tooltip == null) return target;
    return Tooltip(message: tooltip!, child: target);
  }
}
