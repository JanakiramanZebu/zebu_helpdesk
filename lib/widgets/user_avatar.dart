import 'package:flutter/material.dart';

import '../core/format.dart';
import '../core/theme/app_text.dart';

/// Circular initials avatar with a deterministic color per name.
class UserAvatar extends StatelessWidget {
  const UserAvatar({super.key, required this.name, this.radius = 20});
  final String name;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final color = colorFor(name);
    return CircleAvatar(
      radius: radius,
      backgroundColor: color.withValues(alpha: 0.18),
      child: AppText.custmText(
        context,
        Fmt.initials(name),
        fs: radius * 0.8,
        fw: 2,
        color: color,
      ),
    );
  }

  /// Deterministic accent color for a display [name] (shared so chat bubbles
  /// can tint the sender's name to match their avatar).
  static Color colorFor(String name) {
    const palette = [
      Color(0xFF3D5AFE),
      Color(0xFF00897B),
      Color(0xFFD81B60),
      Color(0xFF8E24AA),
      Color(0xFFF4511E),
      Color(0xFF43A047),
      Color(0xFF6D4C41),
      Color(0xFF1E88E5),
    ];
    var hash = 0;
    for (final c in name.codeUnits) {
      hash = (hash * 31 + c) & 0x7fffffff;
    }
    return palette[hash % palette.length];
  }
}
