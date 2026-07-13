import 'package:flutter/material.dart';

/// Minimal status / priority / tag indicator: **colored dot + label** with
/// no background, no border. The signal is the color; the chrome comes off.
/// Reads as premium precisely because it's restrained — Linear / Vercel
/// "issue status" style rather than a chunky chip.
///
/// Two sizes:
///   * default — 12 px label, 6 px dot (fits table cells);
///   * dense   — 11 px label, 5 px dot (fits tight inline chips).
///
/// Pass an [icon] to swap the dot for a filled glyph — used by priority
/// rows (flag) and category tags where a shape reads faster than a dot.
class StatusPill extends StatelessWidget {
  const StatusPill({
    super.key,
    required this.label,
    required this.color,
    this.icon,
    this.dense = false,
    this.fontWeight = FontWeight.w500,
  });

  final String label;
  final Color color;
  final IconData? icon;
  final bool dense;

  /// Label weight. Defaults to `w500` (matches the light restraint the pill
  /// was designed for); pass `w600` when the pill also carries an
  /// identity/type meaning that should read as bolder in a scannable column.
  final FontWeight fontWeight;

  @override
  Widget build(BuildContext context) {
    final size = dense ? 11.0 : 14.0;
    final indicatorSize = dense ? 5.0 : 6.0;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (icon != null)
          Icon(icon, size: indicatorSize + 5, color: color)
        else
          Container(
            width: indicatorSize + 4,
            height: indicatorSize,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
            ),
          ),
        SizedBox(width: dense ? 6 : 7),
        Flexible(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: size,
              fontWeight: fontWeight,
              color: color,
              height: 1.25,
              letterSpacing: 0.05,
            ),
          ),
        ),
      ],
    );
  }
}
