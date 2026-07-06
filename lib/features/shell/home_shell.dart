import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/responsive/breakpoints.dart';
import '../../core/responsive/responsive_body.dart';
import '../../core/theme/app_theme.dart';
import 'widgets/floating_nav_bar.dart';

/// Top-level nav shell. Hosts the four primary branches (Dashboard, Tickets,
/// Tasks, More) and adapts its chrome to the available width:
///   * < 905 px → bottom-floating brand pill (phone, unchanged)
///   * 905–1239 → icon-only side rail
///   * ≥ 1240   → extended rail (icon + label)
class HomeShell extends StatelessWidget {
  const HomeShell({super.key, required this.shell});
  final StatefulNavigationShell shell;

  void _go(int index) =>
      shell.goBranch(index, initialLocation: index == shell.currentIndex);

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final bp = Breakpoint.of(constraints.maxWidth);
        if (!bp.isWide) return _PhoneShell(shell: shell, onTap: _go);
        return _WideShell(
          shell: shell,
          onTap: _go,
          extended: bp == Breakpoint.large,
        );
      },
    );
  }
}

/// The four primary nav destinations. Single source of truth for both the
/// phone bottom bar and the widescreen rail.
const _destinations = <_NavDest>[
  _NavDest(
    label: 'Dashboard',
    icon: Icons.dashboard_outlined,
    selectedIcon: Icons.dashboard,
  ),
  _NavDest(
    label: 'Tickets',
    icon: Icons.confirmation_number_outlined,
    selectedIcon: Icons.confirmation_number,
  ),
  _NavDest(
    label: 'Tasks',
    icon: Icons.task_alt_outlined,
    selectedIcon: Icons.task_alt,
  ),
  _NavDest(label: 'More', icon: Icons.menu, selectedIcon: Icons.menu),
];

class _NavDest {
  const _NavDest({
    required this.label,
    required this.icon,
    required this.selectedIcon,
  });
  final String label;
  final IconData icon;
  final IconData selectedIcon;
}

// --- Phone layout -----------------------------------------------------------

class _PhoneShell extends StatelessWidget {
  const _PhoneShell({required this.shell, required this.onTap});
  final StatefulNavigationShell shell;
  final ValueChanged<int> onTap;

  @override
  Widget build(BuildContext context) {
    // ResponsiveBody is a pass-through at phone widths; we wrap here for
    // parity with _WideShell so every branch screen sees the same max-width
    // constraint.
    return Scaffold(
      extendBody: true,
      body: ResponsiveBody(child: shell),
      bottomNavigationBar: FloatingNavBar(
        currentIndex: shell.currentIndex,
        onTap: onTap,
      ),
    );
  }
}

// --- Widescreen layout ------------------------------------------------------

class _WideShell extends StatelessWidget {
  const _WideShell({
    required this.shell,
    required this.onTap,
    required this.extended,
  });
  final StatefulNavigationShell shell;
  final ValueChanged<int> onTap;
  final bool extended;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      body: Row(
        children: [
          NavigationRail(
            extended: extended,
            minWidth: 72,
            minExtendedWidth: 220,
            selectedIndex: shell.currentIndex,
            onDestinationSelected: onTap,
            labelType: extended
                ? NavigationRailLabelType.none
                : NavigationRailLabelType.all,
            backgroundColor: scheme.surface,
            indicatorColor: AppTheme.brand.withValues(alpha: 0.14),
            selectedIconTheme: const IconThemeData(color: AppTheme.brand),
            unselectedIconTheme: IconThemeData(color: scheme.onSurfaceVariant),
            selectedLabelTextStyle: const TextStyle(
              color: AppTheme.brand,
              fontWeight: FontWeight.w600,
            ),
            unselectedLabelTextStyle: TextStyle(color: scheme.onSurfaceVariant),
            leading: extended
                ? Padding(
                    padding: const EdgeInsets.fromLTRB(20, 18, 20, 8),
                    child: Row(
                      children: [
                        Container(
                          width: 32,
                          height: 32,
                          decoration: BoxDecoration(
                            color: AppTheme.brand,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Icon(
                            Icons.support_agent,
                            color: Colors.white,
                            size: 18,
                          ),
                        ),
                        const SizedBox(width: 10),
                        const Text(
                          'Helpdesk',
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 15,
                          ),
                        ),
                      ],
                    ),
                  )
                : const Padding(
                    padding: EdgeInsets.symmetric(vertical: 16),
                    child: Icon(
                      Icons.support_agent,
                      color: AppTheme.brand,
                      size: 22,
                    ),
                  ),
            destinations: [
              for (final d in _destinations)
                NavigationRailDestination(
                  icon: Icon(d.icon),
                  selectedIcon: Icon(d.selectedIcon),
                  label: Text(d.label),
                ),
            ],
          ),
          VerticalDivider(width: 1, color: scheme.outlineVariant),
          Expanded(child: ResponsiveBody(child: shell)),
        ],
      ),
    );
  }
}
