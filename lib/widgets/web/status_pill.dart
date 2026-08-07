import 'package:flutter/material.dart';

import '../../res/zebu_spacing.dart';

/// Status / priority / tag chip, matching the mobile app's `StatusChip`
/// language: a **filled tinted pill** — the chip color at 12 % alpha as the
/// background, radius 8, with the label (and optional leading icon) in the
/// full-strength color. Reads as a solid, scannable badge in tables and
/// detail panels, identical to the mobile ticket/task rows.
///
/// Two sizes:
///   * default — 12 px label, H10/V5 padding (fits table cells);
///   * dense   — 11 px label, H8/V3 padding (fits tight inline chips).
///
/// Pass an [icon] for chips where a glyph reads faster than color alone
/// (priority flags, category tags).
class StatusPill extends StatelessWidget {
  const StatusPill({
    super.key,
    required this.label,
    required this.color,
    this.icon,
    this.dense = false,
    this.fontWeight = FontWeight.w600,
  });

  final String label;
  final Color color;
  final IconData? icon;
  final bool dense;

  /// Label weight. Defaults to `w600` (mobile `StatusChip` weight); pass
  /// `w500` for softer secondary tags.
  final FontWeight fontWeight;

  @override
  Widget build(BuildContext context) {
    final fontSize = dense ? 11.0 : 12.0;
    final iconSize = dense ? 12.0 : 14.0;
    return Container(
      padding: dense
          ? const EdgeInsets.symmetric(horizontal: 8, vertical: 3)
          : const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(ZebuRadius.rSm),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: iconSize, color: color),
            const SizedBox(width: 4),
          ],
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: fontSize,
                fontWeight: fontWeight,
                color: color,
                height: 1.25,
                letterSpacing: 0.05,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
