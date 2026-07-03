import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../../core/assets.dart';
import '../../../core/theme/app_text.dart';
import '../../../core/theme/app_theme.dart';

/// A floating, light bottom navigation bar. Sits above the content (the host
/// [Scaffold] uses `extendBody: true`) as a rounded surface card with a soft
/// shadow. Unselected destinations show a muted custom SVG glyph + label; the
/// selected one is lifted into a brand-blue "pill" with the icon and label in
/// white.
///
/// All five items switch shell branches (Dashboard / Tickets / Tasks / Inbox /
/// More). The **Inbox** item additionally carries an unread
/// [notificationCount] badge.
class FloatingNavBar extends StatelessWidget {
  const FloatingNavBar({
    super.key,
    required this.currentIndex,
    required this.onTap,
    this.notificationCount = 0,
  });

  final int currentIndex;
  final ValueChanged<int> onTap;

  /// Unread notification count shown as a badge on the Inbox item.
  final int notificationCount;

  static const _items = <({String icon, String label})>[
    (icon: Assets.navDashboard, label: 'Home'),
    (icon: Assets.navTickets, label: 'Ticket'),
    (icon: Assets.navTasks, label: 'Tasks'),
    (icon: Assets.navInbox, label: 'Inbox'),
    (icon: Assets.navMore, label: 'Menu'),
  ];

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bottomInset = MediaQuery.of(context).padding.bottom;
    final barColor = isDark ? const Color(0xFF1C1C1E) : Colors.white;

    return Padding(
      padding: EdgeInsets.fromLTRB(
        14,
        0,
        14,
        (bottomInset > 0 ? bottomInset : 0) + 10,
      ),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: barColor,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(
            color: scheme.outlineVariant.withValues(alpha: isDark ? 0.6 : 0.9),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: isDark ? 0.4 : 0.10),
              blurRadius: 20,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(24),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
            child: Row(
              children: [
                for (var i = 0; i < _items.length; i++)
                  _NavItem(
                    icon: _items[i].icon,
                    label: _items[i].label,
                    selected: currentIndex == i,
                    badgeCount: i == 3 ? notificationCount : 0,
                    onTap: () => onTap(i),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
    this.badgeCount = 0,
  });

  final String icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  /// When > 0, a small red count badge is drawn over the icon.
  final int badgeCount;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final muted = scheme.onSurfaceVariant;
    final iconColor = selected ? Colors.white : muted;

    // The selected item expands to fit its inline label; others stay compact.
    return Expanded(
      flex: selected ? 3 : 2,
      child: Semantics(
        selected: selected,
        button: true,
        label: label,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          splashColor: AppTheme.brand.withValues(alpha: 0.10),
          highlightColor: Colors.transparent,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOut,
            height: 44,
            padding: EdgeInsets.symmetric(horizontal: selected ? 12 : 4),
            decoration: BoxDecoration(
              color: selected ? AppTheme.brand : Colors.transparent,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _Glyph(
                  icon: icon,
                  color: iconColor,
                  badgeCount: badgeCount,
                  onBrand: selected,
                ),
                // Reveal the label only when selected, animating its width.
                ClipRect(
                  child: AnimatedAlign(
                    duration: const Duration(milliseconds: 220),
                    curve: Curves.easeOut,
                    alignment: Alignment.centerLeft,
                    widthFactor: selected ? 1 : 0,
                    child: Padding(
                      padding: const EdgeInsets.only(left: 8),
                      child: AppText.custmText(
                        context,
                        label,
                        fs: 13,
                        color: Colors.white,
                        fw: 1,
                        maxLines: 1,
                        overflow: TextOverflow.clip,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The SVG glyph with an optional count badge.
class _Glyph extends StatelessWidget {
  const _Glyph({
    required this.icon,
    required this.color,
    required this.badgeCount,
    required this.onBrand,
  });

  final String icon;
  final Color color;
  final int badgeCount;

  /// True when drawn on the brand-blue pill (affects the badge's border).
  final bool onBrand;

  @override
  Widget build(BuildContext context) {
    final glyph = SvgPicture.asset(
      icon,
      width: 23,
      height: 23,
      colorFilter: ColorFilter.mode(color, BlendMode.srcIn),
    );
    if (badgeCount <= 0) return glyph;

    return Stack(
      clipBehavior: Clip.none,
      children: [
        glyph,
        Positioned(
          top: -5,
          right: -8,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
            constraints: const BoxConstraints(minWidth: 16),
            decoration: BoxDecoration(
              color: AppTheme.overdue,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: onBrand ? AppTheme.brand : Colors.white,
                width: 1.5,
              ),
            ),
            child: AppText.custmText(
              context,
              badgeCount > 99 ? '99+' : '$badgeCount',
              fs: 9,
              color: Colors.white,
              fw: 2,
              height: 1.3,
              align: TextAlign.center,
            ),
          ),
        ),
      ],
    );
  }
}
