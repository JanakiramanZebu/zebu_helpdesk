import 'package:flutter/material.dart';

import '../core/format.dart';

/// Circular initials avatar with a deterministic color per name.
class UserAvatar extends StatelessWidget {
  const UserAvatar({super.key, required this.name, this.radius = 20});
  final String name;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final color = _colorFor(name);
    return CircleAvatar(
      radius: radius,
      backgroundColor: color.withValues(alpha: 0.18),
      child: Text(
        Fmt.initials(name),
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.w700,
          fontSize: radius * 0.8,
        ),
      ),
    );
  }

  static Color _colorFor(String name) {
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
