import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

/// Renders a bundled SVG glyph tinted to a single color (defaults to the
/// theme's muted on-surface tone), so Mynt's SVG icons sit alongside Material
/// ones consistently.
class SvgIcon extends StatelessWidget {
  const SvgIcon(this.asset, {super.key, this.size = 22, this.color});

  final String asset;
  final double size;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final tint = color ?? Theme.of(context).colorScheme.onSurfaceVariant;
    return SvgPicture.asset(
      asset,
      width: size,
      height: size,
      colorFilter: ColorFilter.mode(tint, BlendMode.srcIn),
    );
  }
}
