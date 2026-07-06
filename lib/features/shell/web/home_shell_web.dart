import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/assets.dart';
import '../../../core/router/routes.dart';
import '../../../providers.dart';
import '../../../core/theme/theme_controller.dart';
import '../../../widgets/user_avatar.dart';
import '../../dashboard/web/_tokens.dart';
import '../../profile/web/profile_screen_web.dart';
import '../../tickets/web/create_ticket_screen_web.dart';
import '_shell_tokens.dart';
import 'profile_menu_popover.dart';

/// Web-only top-level shell. Replaces `HomeShell` on the web target.
///
/// Layout: full-width top bar (workspace pill on the left, action cluster on
/// the right) above a Row of a dark [_Sidebar] + content. The five primary
/// branches (Dashboard / Tickets / Tasks / Inbox / More) map 1:1 to the
/// existing [StatefulNavigationShell] indices declared in `app_router.dart`.
///
/// Visual language is inspired by the ClickUp workspace shell:
///   * dark, always-visible sidebar rail — collapsible at narrow widths;
///   * flat, hairline-bordered top bar with a workspace pill on the left and
///     an action cluster on the right;
///   * no invented global search — the app has no such endpoint, so we don't
///     draw a decorative field for it.
class HomeShellWeb extends StatelessWidget {
  const HomeShellWeb({super.key, required this.shell});
  final StatefulNavigationShell shell;

  void _go(int index) =>
      shell.goBranch(index, initialLocation: index == shell.currentIndex);

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final collapsed = width < ShellTokens.collapseBreakpoint;
    final sidebarWidth =
        collapsed ? ShellTokens.sidebarCollapsed : ShellTokens.sidebarExpanded;

    // Apply the Zebu Premium typeface (Inter) to the entire web tree — the
    // family called out globally in DESIGN_SYSTEM.md. Mobile never reaches
    // this widget, so this scoped override never affects Android/iOS, which
    // already use Inter via AppTheme.
    final base = Theme.of(context);
    final t = WebTokens.of(context);
    return Theme(
      data: base.copyWith(
        textTheme: GoogleFonts.interTextTheme(base.textTheme),
        scrollbarTheme: ScrollbarThemeData(
          thumbVisibility: const WidgetStatePropertyAll(true),
          thickness: const WidgetStatePropertyAll(8),
          radius: const Radius.circular(4),
          thumbColor: WidgetStatePropertyAll(
            base.colorScheme.outlineVariant.withValues(alpha: 0.9),
          ),
        ),
      ),
      // Force every Scrollable underneath the shell to wear a visible
      // scrollbar. Default MaterialScrollBehavior only draws the scrollbar on
      // desktop TargetPlatform (macOS/Linux/Windows) — on web builds running
      // under mobile-emulated platforms it would otherwise be invisible.
      child: ScrollConfiguration(
        behavior: const _WebScrollBehavior(),
        child: Scaffold(
          backgroundColor: t.bgPrimary,
          body: Column(
            children: [
              _TopBar(logoSlotWidth: sidebarWidth),
              Expanded(
                child: Row(
                  children: [
                    _Sidebar(
                      currentIndex: shell.currentIndex,
                      onTap: _go,
                      collapsed: collapsed,
                    ),
                    Expanded(child: shell),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// Branch indices must match the order declared in `app_router.dart`. On web
// the router adds a dedicated Inbox branch between Tasks and More, so the web
// destination list is 5 entries wide (mobile still uses 4). Each destination
// gets a distinctive icon so the sidebar reads at a glance when collapsed.
const _destinations = <_NavDest>[
  _NavDest(
    label: 'Dashboard',
    icon: Icons.space_dashboard_outlined,
    selectedIcon: Icons.space_dashboard,
  ),
  _NavDest(
    label: 'Tickets',
    icon: Icons.local_activity_outlined,
    selectedIcon: Icons.local_activity,
  ),
  _NavDest(
    label: 'Tasks',
    icon: Icons.checklist_rtl_outlined,
    selectedIcon: Icons.checklist_rtl,
  ),
  _NavDest(
    label: 'Inbox',
    icon: Icons.mark_email_unread_outlined,
    selectedIcon: Icons.mark_email_unread,
  ),
  _NavDest(
    label: 'More',
    icon: Icons.grid_view_outlined,
    selectedIcon: Icons.grid_view,
  ),
];

// Named indices so intent is obvious at the call sites below.
const _idxDashboard = 0;
const _idxTickets = 1;
const _idxTasks = 2;
const _idxInbox = 3;
const _idxMore = 4;

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

// --- Sidebar ----------------------------------------------------------------

class _Sidebar extends ConsumerWidget {
  const _Sidebar({
    required this.currentIndex,
    required this.onTap,
    required this.collapsed,
  });

  final int currentIndex;
  final ValueChanged<int> onTap;
  final bool collapsed;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ShellTokens.of(context);
    final width =
        collapsed ? ShellTokens.sidebarCollapsed : ShellTokens.sidebarExpanded;
    return Container(
      width: width,
      decoration: BoxDecoration(
        color: s.ctaFg,
        border: Border(
          right: BorderSide(color: s.sidebarBorder, width: 1),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 14),
          _NewTicketButton(collapsed: collapsed),
          const SizedBox(height: 14),
          _SideNavItem(
            icon: _destinations[_idxDashboard].icon,
            selectedIcon: _destinations[_idxDashboard].selectedIcon,
            label: _destinations[_idxDashboard].label,
            selected: currentIndex == _idxDashboard,
            collapsed: collapsed,
            onTap: () => onTap(_idxDashboard),
          ),
          _SideNavItem(
            icon: _destinations[_idxTickets].icon,
            selectedIcon: _destinations[_idxTickets].selectedIcon,
            label: _destinations[_idxTickets].label,
            selected: currentIndex == _idxTickets,
            collapsed: collapsed,
            onTap: () => onTap(_idxTickets),
          ),
          _SideNavItem(
            icon: _destinations[_idxTasks].icon,
            selectedIcon: _destinations[_idxTasks].selectedIcon,
            label: _destinations[_idxTasks].label,
            selected: currentIndex == _idxTasks,
            collapsed: collapsed,
            onTap: () => onTap(_idxTasks),
          ),
          // Inbox is a full shell branch — tapping it switches branches (like
          // Dashboard/Tickets) instead of pushing a route over the shell. The
          // badge shows the live unread count.
          _InboxNavItem(
            collapsed: collapsed,
            selected: currentIndex == _idxInbox,
            onTap: () => onTap(_idxInbox),
          ),
          _SideNavItem(
            icon: _destinations[_idxMore].icon,
            selectedIcon: _destinations[_idxMore].selectedIcon,
            label: _destinations[_idxMore].label,
            selected: currentIndex == _idxMore,
            collapsed: collapsed,
            onTap: () => onTap(_idxMore),
          ),
          const Spacer(),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Container(height: 1, color: s.sidebarDivider),
          ),
          _ProfileFooter(collapsed: collapsed),
        ],
      ),
    );
  }
}

/// Sidebar primary action — filled brand-blue pill sitting above the
/// Dashboard nav item. Filled (vs. outlined) so it reads clearly against the
/// dark rail; on the previous light rail an outlined pill worked, but on a
/// dark bg a filled brand pill has stronger visual weight without competing
/// with the selected nav row (which uses a neutral dark surface + accent
/// bar).
class _NewTicketButton extends StatefulWidget {
  const _NewTicketButton({required this.collapsed});
  final bool collapsed;

  @override
  State<_NewTicketButton> createState() => _NewTicketButtonState();
}

class _NewTicketButtonState extends State<_NewTicketButton> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final s = ShellTokens.of(context);
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: widget.collapsed ? 12 : 11),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: GestureDetector(
          onTap: () => showCreateTicketDialog(context),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            curve: Curves.easeOut,
            height: 40,
            decoration: BoxDecoration(
              color: _hover ? s.ctaHover : s.ctaBg,
              borderRadius: BorderRadius.circular(WebTokens.rSm),
              boxShadow: _hover
                  ? const [
                      BoxShadow(
                        color: Color(0x330037B7),
                        blurRadius: 14,
                        offset: Offset(0, 4),
                      ),
                    ]
                  : null,
            ),
            child: widget.collapsed
                ? Tooltip(
                    message: 'New ticket',
                    child: Icon(Icons.add, color: s.ctaFg, size: 20),
                  )
                : Row(
                    mainAxisAlignment: MainAxisAlignment.start,
                    children: [
                      const SizedBox(width: 10),
                      Icon(Icons.add, color: s.ctaFg, size: 18),
                      const SizedBox(width: 6),
                      Text(
                        'New Ticket',
                        style: TextStyle(
                          color: s.ctaFg,
                          fontSize: 13.5,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 0.1,
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

class _SideNavItem extends StatefulWidget {
  const _SideNavItem({
    required this.icon,
    required this.selectedIcon,
    required this.label,
    required this.selected,
    required this.collapsed,
    required this.onTap,
    this.trailing,
  });

  final IconData icon;
  final IconData selectedIcon;
  final String label;
  final bool selected;
  final bool collapsed;
  final VoidCallback onTap;
  final Widget? trailing;

  @override
  State<_SideNavItem> createState() => _SideNavItemState();
}

class _SideNavItemState extends State<_SideNavItem> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final s = ShellTokens.of(context);
    // ClickUp-inspired active state: a subtle neutral surface (not brand
    // blue) plus a thin brand accent bar down the left edge, and the icon /
    // label go pure white. Hover uses the same surface at a lower alpha so
    // the row previews before commit.
    //
    // Idle bg is set to `sidebarBg` explicitly (rather than transparent) so
    // the [AnimatedContainer] tweens color-to-color like the tickets table
    // row — smoother than transparent-to-color, which can flicker at low
    // alphas during the transition.
    final bg = widget.selected
        ? s.sidebarSelected
        : (_hover ? s.sidebarHover : s.sidebarBg);
    final iconColor =
        widget.selected ? s.sidebarIconActive : s.sidebarIconIdle;
    final textColor =
        widget.selected ? s.sidebarTextActive : s.sidebarTextIdle;

    final child = widget.collapsed
        ? Tooltip(
            message: widget.label,
            child: Center(
              child: Icon(
                widget.selected ? widget.selectedIcon : widget.icon,
                color: iconColor,
                size: 20,
              ),
            ),
          )
        : Row(
            children: [
              const SizedBox(width: 14),
              Icon(
                widget.selected ? widget.selectedIcon : widget.icon,
                color: iconColor,
                size: 18,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  widget.label,
                  style: TextStyle(
                    color: textColor,
                    fontSize: 13.5,
                    fontWeight:
                        widget.selected ? FontWeight.w600 : FontWeight.w500,
                    letterSpacing: 0.1,
                  ),
                ),
              ),
              if (widget.trailing != null) ...[
                widget.trailing!,
                const SizedBox(width: 10),
              ],
            ],
          );

    return Padding(
      padding: EdgeInsets.symmetric(
        horizontal: widget.collapsed ? 10 : 10,
        vertical: 4,
      ),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onTap,
          child: Stack(
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 80),
                curve: Curves.easeOut,
                height: 38,
                decoration: BoxDecoration(
                  color: bg,
                  borderRadius: BorderRadius.circular(WebTokens.rSm),
                ),
                child: child,
              ),
              // Thin left accent bar visible only for the selected row.
              if (widget.selected)
                Positioned(
                  left: 0,
                  top: 8,
                  bottom: 8,
                  child: Container(
                    width: 3,
                    decoration: BoxDecoration(
                      color: s.sidebarAccentBar,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Inbox nav row with a live unread count. Uses a ClickUp-style compact pink
/// pill instead of the previous blue chip so it reads as a notification
/// signal rather than a badge count.
class _InboxNavItem extends ConsumerWidget {
  const _InboxNavItem({
    required this.collapsed,
    required this.selected,
    required this.onTap,
  });
  final bool collapsed;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final unread = ref.watch(unreadCountProvider).maybeWhen(
          data: (c) => c,
          orElse: () => 0,
        );
    final s = ShellTokens.of(context);
    return _SideNavItem(
      icon: Icons.inbox_outlined,
      selectedIcon: Icons.inbox,
      label: 'Inbox',
      selected: selected,
      collapsed: collapsed,
      onTap: onTap,
      trailing: unread > 0 && !collapsed
          ? Container(
              constraints: const BoxConstraints(minWidth: 20),
              height: 18,
              padding: const EdgeInsets.symmetric(horizontal: 6),
              decoration: BoxDecoration(
                color: s.sidebarBadgePink,
                borderRadius: BorderRadius.circular(9),
              ),
              alignment: Alignment.center,
              child: Text(
                unread > 99 ? '99+' : '$unread',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 10.5,
                  fontWeight: FontWeight.w700,
                  height: 1,
                ),
              ),
            )
          : null,
    );
  }
}

/// Sidebar footer — compact avatar + name/email. On the dark rail we use a
/// lighter tint for the initials so the initial reads at a glance, and the
/// text tones follow [ShellTokens] so the row never fights the nav items
/// above.
class _ProfileFooter extends ConsumerStatefulWidget {
  const _ProfileFooter({required this.collapsed});
  final bool collapsed;

  @override
  ConsumerState<_ProfileFooter> createState() => _ProfileFooterState();
}

class _ProfileFooterState extends ConsumerState<_ProfileFooter> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final s = ShellTokens.of(context);
    final me = ref.watch(meProvider);
    return me.maybeWhen(
      data: (m) {
        final initial =
            m.name.trim().isNotEmpty ? m.name.trim()[0].toUpperCase() : '?';
        final avatar = Container(
          width: 32,
          height: 32,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: s.profileAvatarBg,
            shape: BoxShape.circle,
          ),
          child: Text(
            initial,
            style: TextStyle(
              color: s.profileAvatarFg,
              fontWeight: FontWeight.w700,
              fontSize: 13,
            ),
          ),
        );

        if (widget.collapsed) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 14),
            child: Center(
              child: Tooltip(message: m.name, child: avatar),
            ),
          );
        }

        return MouseRegion(
          cursor: SystemMouseCursors.click,
          onEnter: (_) => setState(() => _hover = true),
          onExit: (_) => setState(() => _hover = false),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => showProfileDialog(context),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 80),
              curve: Curves.easeOut,
              margin: const EdgeInsets.fromLTRB(10, 8, 10, 10),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
              decoration: BoxDecoration(
                color: _hover ? s.sidebarHover : s.sidebarBg,
                borderRadius: BorderRadius.circular(WebTokens.rSm),
              ),
              child: Row(
                children: [
                  avatar,
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          m.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: s.profileNameFg,
                            fontWeight: FontWeight.w600,
                            fontSize: 13,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          m.email,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: s.profileEmailFg,
                            fontSize: 11.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
      orElse: () => SizedBox(height: widget.collapsed ? 50 : 70),
    );
  }
}

// --- Top bar ----------------------------------------------------------------

class _TopBar extends ConsumerWidget {
  const _TopBar({required this.logoSlotWidth});

  /// Width of the left slot reserved for the brand logo. Matches the sidebar
  /// width below so the logo sits directly above it (Asana-style).
  final double logoSlotWidth;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ShellTokens.of(context);
    final t = WebTokens.of(context);
    final unread = ref.watch(unreadCountProvider);
    final unreadCount = unread.maybeWhen(data: (c) => c, orElse: () => 0);

    return Container(
      height: ShellTokens.topbarHeight,
      decoration: BoxDecoration(
        color: s.topbarBg,
        border: Border(bottom: BorderSide(color: s.topbarBorder, width: 1)),
      ),
      child: Row(
        children: [
          // Brand logo slot — same width as the sidebar so the logo sits
          // directly above it. When collapsed the slot is too narrow for the
          // full wordmark at height 36, so we scale via FittedBox and shrink
          // the horizontal padding to keep the mark visible.
          Builder(
            builder: (context) {
              final collapsed = logoSlotWidth < 100;
              return SizedBox(
                width: logoSlotWidth,
                child: Padding(
                  padding: EdgeInsets.symmetric(
                    horizontal: collapsed ? 8 : 18,
                  ),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: SvgPicture.asset(Assets.zebuLogo, height: 34),
                    ),
                  ),
                ),
              );
            },
          ),
          // Right action cluster. Kept lean — theme toggle, notifications,
          // and an avatar button that opens the profile popover. No invented
          // global search field here (the backend has no such endpoint).
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  const _TopBarIconButton.themeToggle(),
                  const SizedBox(width: 4),
                  _TopBarNotifButton(unread: unreadCount, tokens: t),
                  const SizedBox(width: 8),
                  const _AvatarMenuButton(),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// A unified icon button style for the top bar: 36 px hit-area, subtle hover
/// tint, hairline "ghost" border on hover so the button previews an outline
/// without hard-committing to it. Currently used only by the theme toggle;
/// exposed as a constructor variant so future top-bar actions reuse the same
/// treatment.
class _TopBarIconButton extends ConsumerWidget {
  const _TopBarIconButton.themeToggle() : _variant = _TopBarIconVariant.theme;
  final _TopBarIconVariant _variant;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    switch (_variant) {
      case _TopBarIconVariant.theme:
        return const _ThemeToggle();
    }
  }
}

enum _TopBarIconVariant { theme }

/// Dark/light toggle. Reads the current effective brightness (system-resolved
/// if the mode is [ThemeMode.system]) and flips to the opposite. Explicit
/// choices persist via [ThemeModeController.set].
class _ThemeToggle extends ConsumerStatefulWidget {
  const _ThemeToggle();

  @override
  ConsumerState<_ThemeToggle> createState() => _ThemeToggleState();
}

class _ThemeToggleState extends ConsumerState<_ThemeToggle> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final t = WebTokens.of(context);
    final mode = ref.watch(themeModeProvider);
    final systemDark =
        MediaQuery.platformBrightnessOf(context) == Brightness.dark;
    final isDark = switch (mode) {
      ThemeMode.dark => true,
      ThemeMode.light => false,
      ThemeMode.system => systemDark,
    };
    return _TopBarGhost(
      tooltip: isDark ? 'Switch to light mode' : 'Switch to dark mode',
      onTap: () => ref
          .read(themeModeProvider.notifier)
          .set(isDark ? ThemeMode.light : ThemeMode.dark),
      hover: _hover,
      onHover: (v) => setState(() => _hover = v),
      child: Icon(
        isDark ? Icons.light_mode_outlined : Icons.dark_mode_outlined,
        size: 18,
        color: t.textPrimary,
      ),
    );
  }
}

/// Notifications button + unread badge. Uses Material [Badge] so the count
/// anchors to the top-right and never grows over the icon glyph.
class _TopBarNotifButton extends StatefulWidget {
  const _TopBarNotifButton({required this.unread, required this.tokens});
  final int unread;
  final WebTokens tokens;

  @override
  State<_TopBarNotifButton> createState() => _TopBarNotifButtonState();
}

class _TopBarNotifButtonState extends State<_TopBarNotifButton> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final t = widget.tokens;
    return _TopBarGhost(
      tooltip: 'Notifications',
      onTap: () => context.go(Routes.notifications),
      hover: _hover,
      onHover: (v) => setState(() => _hover = v),
      child: Badge(
        isLabelVisible: widget.unread > 0,
        label: Text(widget.unread > 99 ? '99+' : '${widget.unread}'),
        backgroundColor: WebTokens.danger,
        textColor: Colors.white,
        textStyle: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700),
        largeSize: 16,
        padding: const EdgeInsets.symmetric(horizontal: 4),
        offset: const Offset(2, -4),
        child: Icon(
          Icons.notifications_none_rounded,
          size: 20,
          color: t.textPrimary,
        ),
      ),
    );
  }
}

/// Shared visual container for top-bar actions — 36 px square with a subtle
/// hover tint and hairline border-on-hover, so each action gets the same
/// "premium ghost" treatment without every caller re-declaring it.
class _TopBarGhost extends StatelessWidget {
  const _TopBarGhost({
    required this.child,
    required this.onTap,
    required this.tooltip,
    required this.hover,
    required this.onHover,
  });
  final Widget child;
  final VoidCallback onTap;
  final String tooltip;
  final bool hover;
  final ValueChanged<bool> onHover;

  @override
  Widget build(BuildContext context) {
    final t = WebTokens.of(context);
    return Tooltip(
      message: tooltip,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => onHover(true),
        onExit: (_) => onHover(false),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 100),
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: hover ? t.bgHover : Colors.transparent,
              borderRadius: BorderRadius.circular(WebTokens.rSm),
              border: Border.all(
                color: hover ? t.borderSubtle : Colors.transparent,
                width: 1,
              ),
            ),
            child: Center(child: child),
          ),
        ),
      ),
    );
  }
}

/// Avatar circle in the top-right that opens the profile popover. Replaces
/// the old generic `account_circle_outlined` glyph with a real initial from
/// [UserAvatar] so identity is visible without opening the menu.
class _AvatarMenuButton extends ConsumerStatefulWidget {
  const _AvatarMenuButton();

  @override
  ConsumerState<_AvatarMenuButton> createState() => _AvatarMenuButtonState();
}

class _AvatarMenuButtonState extends ConsumerState<_AvatarMenuButton> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final t = WebTokens.of(context);
    final me = ref.watch(meProvider);
    final name = me.maybeWhen(data: (m) => m.name, orElse: () => 'Profile');
    return Builder(
      builder: (anchorContext) => Tooltip(
        message: name,
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          onEnter: (_) => setState(() => _hover = true),
          onExit: (_) => setState(() => _hover = false),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => showProfileMenu(anchorContext),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 100),
              padding: const EdgeInsets.all(2),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: _hover ? WebTokens.accent : t.borderSubtle,
                  width: 1.5,
                ),
              ),
              child: UserAvatar(name: name, radius: 14),
            ),
          ),
        ),
      ),
    );
  }
}

// --- Scrollbar behavior -----------------------------------------------------

/// Web-only [ScrollBehavior] that draws a persistent Material scrollbar
/// around every child [Scrollable] regardless of the underlying
/// [TargetPlatform].
///
/// The default [MaterialScrollBehavior] skips the scrollbar on mobile
/// TargetPlatforms — but a web build emulating a mobile platform in Chrome
/// would then never draw one, and users can't tell that a list is scrollable.
class _WebScrollBehavior extends MaterialScrollBehavior {
  const _WebScrollBehavior();

  @override
  Widget buildScrollbar(
    BuildContext context,
    Widget child,
    ScrollableDetails details,
  ) {
    return Scrollbar(
      controller: details.controller,
      thumbVisibility: true,
      child: child,
    );
  }
}
