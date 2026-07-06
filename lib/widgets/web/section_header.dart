import 'package:flutter/material.dart';

import '../../features/dashboard/web/_tokens.dart';

/// Small-caps section header used both inside cards and above lists.
/// Typography is [WebTokens.sectionCaps] — a lightly tracked semibold at
/// 11 px in [WebTokens.textSecondary], so the label reads as an "eyebrow"
/// without stealing focus from the content underneath.
///
/// [icon] renders on the leading side in the same secondary tone. [trailing]
/// is a free slot for links / chips / buttons ("See All", filter toggles).
class SectionHeader extends StatelessWidget {
  const SectionHeader({
    super.key,
    required this.title,
    this.icon,
    this.trailing,
    this.uppercase = true,
  });

  final String title;
  final IconData? icon;
  final Widget? trailing;
  final bool uppercase;

  @override
  Widget build(BuildContext context) {
    final t = WebTokens.of(context);
    return Row(
      children: [
        if (icon != null) ...[
          Icon(icon, size: 14, color: t.textSecondary),
          const SizedBox(width: 6),
        ],
        Text(uppercase ? title.toUpperCase() : title, style: t.sectionCaps),
        const Spacer(),
        if (trailing != null) trailing!,
      ],
    );
  }
}
