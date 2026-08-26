import 'package:flutter/material.dart';

import '../core/theme/app_text.dart';
import 'svg_icon.dart';

/// Shared styling for the â‹®-action menus on the ticket / task detail screens.
///
/// [appMenuTheme] wraps a [PopupMenuButton] so the popup renders as a rounded,
/// softly-elevated card, and [appMenuItem] builds a row that pairs a tinted
/// SVG icon-chip with a label â€” destructive rows tint to the error color.
class AppActionMenu {
  AppActionMenu._();

  /// Shape/color/padding to spread onto a [PopupMenuButton] so every detail
  /// menu looks the same.
  static ShapeBorder get shape =>
      RoundedRectangleBorder(borderRadius: BorderRadius.circular(18));

  static const EdgeInsets menuPadding = EdgeInsets.symmetric(vertical: 8);

  static const double elevation = 3;
}

/// A single â‹®-menu row: an SVG glyph inside a tinted rounded chip, followed by
/// the label. Pass [destructive] for actions like Delete so both the chip and
/// text pick up the error color.
PopupMenuItem<String> appMenuItem({
  required String value,
  required String asset,
  required String label,
  bool destructive = false,
}) {
  return PopupMenuItem<String>(
    value: value,
    height: 46,
    padding: const EdgeInsets.symmetric(horizontal: 12),
    child: _AppMenuRow(asset: asset, label: label, destructive: destructive),
  );
}

class _AppMenuRow extends StatelessWidget {
  const _AppMenuRow({
    required this.asset,
    required this.label,
    required this.destructive,
  });

  final String asset;
  final String label;
  final bool destructive;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final accent = destructive ? scheme.error : scheme.primary;
    final textColor = destructive ? scheme.error : scheme.onSurface;
    return Row(
      children: [
        Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            color: accent.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Center(child: SvgIcon(asset, size: 19, color: accent)),
        ),
        const SizedBox(width: 12),
        AppText.subText(context, label, color: textColor, fw: 1),
      ],
    );
  }
}

/// Flattens menu [groups] into a single entry list, inserting a
/// [PopupMenuDivider] only *between* non-empty groups — so gating items out by
/// permission never leaves a dangling or doubled divider (TK-019).
///
/// Lives here rather than on a screen so both detail menus share one rule and
/// it can be tested without pumping a whole screen.
List<PopupMenuEntry<String>> joinMenuGroups(
  List<List<PopupMenuEntry<String>>> groups,
) {
  final out = <PopupMenuEntry<String>>[];
  for (final g in groups) {
    if (g.isEmpty) continue;
    if (out.isNotEmpty) out.add(const PopupMenuDivider());
    out.addAll(g);
  }
  return out;
}
