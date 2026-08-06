import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/assets.dart';
import '../../../core/router/routes.dart';
import '../../../providers.dart';
import '../../../core/theme/theme_controller.dart';
import '../../../widgets/app_dropdown.dart';
import '../../../widgets/svg_icon.dart';
import '../../../widgets/user_avatar.dart';
import '../../dashboard/web/_tokens.dart';
import '../../profile/web/profile_screen_web.dart';
import '../../tasks/web/create_task_screen_web.dart';
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
    final sidebarWidth = collapsed
        ? ShellTokens.sidebarCollapsed
        : ShellTokens.sidebarExpanded;

    // Apply the Zebu Premium typeface (Inter) to the entire web tree — the
    // family called out globally in DESIGN_SYSTEM.md. Mobile never reaches
    // this widget, so this scoped override never affects Android/iOS, which
    // already use Inter via AppTheme.
    final base = Theme.of(context);
    final t = WebTokens.of(context);
    final s = ShellTokens.of(context);
    return Theme(
      data: base.copyWith(
        textTheme: GoogleFonts.interTextTheme(base.textTheme),
        scrollbarTheme: ScrollbarThemeData(
          thumbVisibility: const WidgetStatePropertyAll(true),
          thickness: const WidgetStatePropertyAll(8),
          radius: const Radius.circular(4),
          // Keep thumb ends clear of the workspace card's rounded corners.
          mainAxisMargin: 4,
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
          backgroundColor: s.canvas,
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
                    // Inset workspace: the routed content lives in a rounded
                    // card floating on the chrome canvas. The hairline is
                    // painted as a *foreground* decoration because every
                    // routed screen fills an opaque bgPrimary that would
                    // otherwise bury a background border; the ClipRRect keeps
                    // full-bleed screen content and slide-over panels inside
                    // the rounded corners. The base ColoredBox guarantees the
                    // canvas never flashes through during branch swaps.
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.all(
                          ShellTokens.workspaceGutter,
                        ),
                        child: DecoratedBox(
                          position: DecorationPosition.foreground,
                          decoration: BoxDecoration(
                            border: Border.all(
                              color: s.workspaceBorder,
                              width: 1,
                            ),
                            borderRadius: BorderRadius.circular(
                              ShellTokens.workspaceRadius,
                            ),
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(
                              ShellTokens.workspaceRadius,
                            ),
                            child: ColoredBox(color: t.bgPrimary, child: shell),
                          ),
                        ),
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
  }
}

// Branch indices must match the order declared in `app_router.dart`. On web
// the router adds a dedicated Inbox branch between Tasks and More, so the web
// destination list is 5 entries wide (mobile still uses 4). Each destination
// uses the mobile app's custom nav glyph (one SVG per destination — the
// selected state is a color tint, matching the mobile FloatingNavBar).
const _destinations = <_NavDest>[
  _NavDest(label: 'Dashboard', svg: Assets.navDashboard),
  _NavDest(label: 'Tickets', svg: Assets.navTickets),
  _NavDest(label: 'Tasks', svg: Assets.navTasks),
  _NavDest(label: 'Inbox', svg: Assets.navInbox),
  _NavDest(label: 'More', svg: Assets.navMore),
];

// Named indices so intent is obvious at the call sites below.
const _idxDashboard = 0;
const _idxTickets = 1;
const _idxTasks = 2;
const _idxInbox = 3;
const _idxMore = 4;

class _NavDest {
  const _NavDest({required this.label, required this.svg});
  final String label;

  /// Mobile nav glyph asset (`Assets.nav*`) — tinted per selection state.
  final String svg;
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
    final t = WebTokens.of(context);
    final width = collapsed
        ? ShellTokens.sidebarCollapsed
        : ShellTokens.sidebarExpanded;
    return Container(
      width: width,
      // Rich brand-tinted rail — a soft vertical gradient (see
      // [ShellTokens.sidebarGradient]) gives the sidebar depth and ties it to
      // the Mynt-blue brand instead of reading as flat white chrome. The
      // inset workspace card's hairline still provides the right-edge break.
      decoration: BoxDecoration(gradient: s.sidebarGradient),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 14),
          _CreateButton(collapsed: collapsed),
          const SizedBox(height: 18),
          _SectionLabel(text: 'Menu', collapsed: collapsed),
          _SideNavItem(
            svg: _destinations[_idxDashboard].svg,
            label: _destinations[_idxDashboard].label,
            tone: t.accent,
            selected: currentIndex == _idxDashboard,
            collapsed: collapsed,
            onTap: () => onTap(_idxDashboard),
          ),
          _SideNavItem(
            svg: _destinations[_idxTickets].svg,
            label: _destinations[_idxTickets].label,
            tone: WebTokens.indigo,
            selected: currentIndex == _idxTickets,
            collapsed: collapsed,
            onTap: () => onTap(_idxTickets),
          ),
          _SideNavItem(
            svg: _destinations[_idxTasks].svg,
            label: _destinations[_idxTasks].label,
            tone: WebTokens.success,
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
          const SizedBox(height: 10),
          _SectionLabel(text: 'Workspace', collapsed: collapsed),
          _SideNavItem(
            svg: _destinations[_idxMore].svg,
            label: _destinations[_idxMore].label,
            tone: const Color(0xFF8B5CF6),
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

/// Small uppercase section label that groups a run of nav items. In
/// collapsed mode we render a hairline divider instead so the grouping
/// still reads without a label crashing into the icon-only rail.
class _SectionLabel extends StatelessWidget {
  const _SectionLabel({required this.text, required this.collapsed});
  final String text;
  final bool collapsed;

  @override
  Widget build(BuildContext context) {
    final s = ShellTokens.of(context);
    if (collapsed) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(14, 4, 14, 8),
        child: Container(height: 1, color: s.sidebarDivider),
      );
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 2, 22, 8),
      child: Text(
        text.toUpperCase(),
        style: TextStyle(
          fontSize: 10.5,
          fontWeight: FontWeight.w700,
          color: s.sidebarTextIdle,
          letterSpacing: 0.9,
        ),
      ),
    );
  }
}

/// Sidebar primary action — brand-gradient CTA, ported from the mobile
/// FloatingNavBar create button (`[brandLight, brand]` topLeft→bottomRight).
/// Hover deepens both gradient stops in the same family so the
/// AnimatedContainer lerps smoothly; no lift, no glow.
/// Sidebar primary CTA. A gradient "Create ▾" split that opens a small menu
/// offering New ticket / New task (Asana's "+ Create" pattern), so task
/// creation has a first-class entry point alongside tickets.
class _CreateButton extends StatefulWidget {
  const _CreateButton({required this.collapsed});
  final bool collapsed;

  @override
  State<_CreateButton> createState() => _CreateButtonState();
}

class _CreateButtonState extends State<_CreateButton> {
  bool _hover = false;
  bool _pressed = false;

  void _setPressed(bool v) {
    if (_pressed != v) setState(() => _pressed = v);
  }

  Future<void> _openMenu(BuildContext anchorContext) async {
    final choice = await showAppDropdown<String>(
      anchorContext,
      minWidth: 200,
      entries: const [
        AppDropdownItem(
          value: 'ticket',
          label: 'New ticket',
          icon: Icons.confirmation_number_outlined,
        ),
        AppDropdownItem(
          value: 'task',
          label: 'New task',
          icon: Icons.check_circle_outline,
        ),
      ],
    );
    if (!mounted || choice == null) return;
    if (choice == 'ticket') {
      showCreateTicketDialog(context);
    } else {
      showCreateTaskDialog(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = ShellTokens.of(context);
    final borderColor = _hover ? s.ctaBorderHover : s.ctaBorder;
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: widget.collapsed ? 12 : 11),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: Builder(
          builder: (anchorContext) => GestureDetector(
            onTap: () => _openMenu(anchorContext),
            onTapDown: (_) => _setPressed(true),
            onTapUp: (_) => _setPressed(false),
            onTapCancel: () => _setPressed(false),
            child: AnimatedScale(
              scale: _pressed ? 0.97 : 1,
              duration: const Duration(milliseconds: 110),
              curve: Curves.easeOut,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 140),
                curve: Curves.easeOut,
                height: 40,
                decoration: BoxDecoration(
                  // Flat solid brand-blue fill (no dark-navy gradient bottom).
                  // Hover deepens one step in the same family.
                  color: _hover ? s.ctaBgHover : s.ctaBg,
                  borderRadius: BorderRadius.circular(WebTokens.rSm),
                  border: borderColor == null
                      ? null
                      : Border.all(color: borderColor, width: 1),
                ),
                child: widget.collapsed
                    ? Tooltip(
                        message: 'Create',
                        child: Center(
                          child: Icon(
                            Icons.add_rounded,
                            color: s.ctaIconFg,
                            size: 22,
                          ),
                        ),
                      )
                    : Row(
                        children: [
                          const SizedBox(width: 12),
                          Icon(Icons.add_rounded, color: s.ctaIconFg, size: 20),
                          const SizedBox(width: 8),
                          Text(
                            'Create',
                            style: TextStyle(
                              color: s.ctaFg,
                              fontSize: 13.5,
                              fontWeight: FontWeight.w600,
                              letterSpacing: 0.2,
                            ),
                          ),
                          const Spacer(),
                          Icon(
                            Icons.keyboard_arrow_down_rounded,
                            color: s.ctaFg,
                            size: 18,
                          ),
                          const SizedBox(width: 10),
                        ],
                      ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SideNavItem extends StatefulWidget {
  const _SideNavItem({
    required this.svg,
    required this.label,
    required this.tone,
    required this.selected,
    required this.collapsed,
    required this.onTap,
    this.trailing,
  });

  /// Mobile nav glyph asset (`Assets.nav*`) — rendered inside a per-destination
  /// coloured tile that fills solid + glows when the row is selected.
  final String svg;
  final String label;

  /// Destination accent — each nav item owns a distinct hue (ClickUp / Height
  /// style) so the rail reads as a colourful, modern task tool.
  final Color tone;
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
    final tone = widget.tone;
    // Modern task-tool rail (ClickUp / Height): each destination owns a hue.
    // The selected row washes its tone at low alpha across the whole pill and
    // the label goes strong-neutral for readability; hover shows a neutral
    // preview fill. Idle is transparent so the brand-tinted rail shows through.
    final bg = widget.selected
        ? tone.withValues(alpha: 0.14)
        : (_hover ? tone.withValues(alpha: 0.07) : Colors.transparent);
    final textColor = widget.selected ? s.profileNameFg : s.sidebarTextIdle;

    // Coloured icon tile — the signature of the modern look. Idle rows carry a
    // soft tone-tinted tile with a tone-coloured glyph; the selected row fills
    // the tile solid with a white glyph and a soft tone-coloured glow. Every
    // value tweens so switching branches glides rather than snapping.
    final iconChip = AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOut,
      width: 30,
      height: 30,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: widget.selected
            ? tone
            : tone.withValues(alpha: _hover ? 0.20 : 0.12),
        borderRadius: BorderRadius.circular(WebTokens.rMd),
        boxShadow: widget.selected
            ? [
                BoxShadow(
                  color: tone.withValues(alpha: 0.35),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ]
            : null,
      ),
      child: SvgIcon(
        widget.svg,
        size: 18,
        color: widget.selected ? Colors.white : tone,
      ),
    );

    final child = widget.collapsed
        ? Tooltip(
            message: widget.label,
            child: Center(child: iconChip),
          )
        : Row(
            children: [
              const SizedBox(width: 10),
              iconChip,
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  widget.label,
                  style: TextStyle(
                    color: textColor,
                    fontSize: 13.5,
                    fontWeight: widget.selected
                        ? FontWeight.w600
                        : FontWeight.w500,
                    letterSpacing: 0.15,
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
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            curve: Curves.easeOut,
            height: 44,
            decoration: BoxDecoration(
              color: bg,
              // Big soft radius → a "floating pill" nav row, the modern
              // task-tool look. A hairline in the row's tone appears only when
              // selected so the active pill reads as a crisp coloured chip.
              borderRadius: BorderRadius.circular(WebTokens.r2xl),
              border: Border.all(
                color: widget.selected
                    ? tone.withValues(alpha: 0.28)
                    : Colors.transparent,
                width: 1,
              ),
            ),
            child: child,
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
    final unread = ref
        .watch(unreadCountProvider)
        .maybeWhen(data: (c) => c, orElse: () => 0);
    final s = ShellTokens.of(context);
    return _SideNavItem(
      svg: Assets.navInbox,
      label: 'Inbox',
      tone: s.sidebarBadgePink,
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
        final initial = m.name.trim().isNotEmpty
            ? m.name.trim()[0].toUpperCase()
            : '?';
        // Availability dot on the avatar's corner — mobile _AvatarWithStatus
        // parity: 10px dot ringed by the rail color so it reads as sitting
        // on top of the avatar. Green = available, grey = away.
        final avatar = SizedBox(
          width: 32,
          height: 32,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Container(
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
              ),
              Positioned(
                right: -1,
                bottom: -1,
                child: Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    color: m.available
                        ? WebTokens.success
                        : const Color(0xFF737373),
                    shape: BoxShape.circle,
                    border: Border.all(color: s.canvas, width: 2),
                  ),
                ),
              ),
            ],
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
              duration: const Duration(milliseconds: 140),
              curve: Curves.easeOut,
              margin: const EdgeInsets.fromLTRB(10, 8, 10, 10),
              padding: const EdgeInsets.fromLTRB(8, 8, 6, 8),
              decoration: BoxDecoration(
                color: _hover ? s.sidebarHover : s.sidebarBg,
                borderRadius: BorderRadius.circular(WebTokens.rSm),
                // Hairline border appears only on hover, so the footer sits
                // flush at rest but promotes into a card the moment it's
                // interactive — mirrors the KPI tile hover treatment.
                border: Border.all(
                  color: _hover ? s.sidebarBorder : Colors.transparent,
                  width: 1,
                ),
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
                  // Trailing kebab hints that the row opens a menu. Fades
                  // in / brightens on hover so at rest it's just a whisper.
                  Icon(
                    Icons.more_horiz_rounded,
                    size: 18,
                    color: _hover ? s.profileNameFg : s.profileEmailFg,
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

/// Custom Zebu wording lockup shown in the app-bar brand slot — a rounded
/// product-icon tile beside the "Zebu Helpdesk" name + "Support workspace"
/// subtitle. Replaces the standalone SVG wordmark. Collapses to the icon mark
/// alone when the rail is narrow.
class _BrandLockup extends StatelessWidget {
  const _BrandLockup({required this.collapsed});
  final bool collapsed;

  @override
  Widget build(BuildContext context) {
    final s = ShellTokens.of(context);
    final mark = Container(
      width: 32,
      height: 32,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(WebTokens.rMd),
        boxShadow: WebTokens.shadowSm,
        border: Border.all(color: s.workspaceBorder, width: 1),
      ),
      child: Image.asset(Assets.appIcon, fit: BoxFit.cover),
    );

    if (collapsed) return mark;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        mark,
        const SizedBox(width: 10),
        Flexible(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Zebu Helpdesk',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: s.profileNameFg,
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.3,
                  height: 1.1,
                ),
              ),
              const SizedBox(height: 1),
              Text(
                'Support workspace',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: s.sidebarTextIdle,
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                  height: 1.1,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

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
      // Defined app-bar band — a subtle tinted surface closed off by a bottom
      // hairline so the top bar reads as its own chrome, not empty white space.
      decoration: BoxDecoration(
        color: s.topbarBg,
        border: Border(bottom: BorderSide(color: s.topbarBorder, width: 1)),
      ),
      child: Row(
        children: [
          // Brand slot — the custom Zebu wording lockup (icon tile + name +
          // subtitle) sits here, same width as the sidebar so it aligns above
          // it. Collapses to just the icon mark on the narrow rail.
          Builder(
            builder: (context) {
              final collapsed = logoSlotWidth < 100;
              return SizedBox(
                width: logoSlotWidth,
                child: Padding(
                  padding: EdgeInsets.symmetric(horizontal: collapsed ? 8 : 16),
                  child: Align(
                    alignment: collapsed
                        ? Alignment.center
                        : Alignment.centerLeft,
                    child: _BrandLockup(collapsed: collapsed),
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
                  const SizedBox(width: 8),
                  // _TopBarNotifButton(unread: unreadCount, tokens: t),
                  // const SizedBox(width: 8),
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
        backgroundColor: t.danger,
        textColor: Colors.white,
        textStyle: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700),
        largeSize: 16,
        padding: const EdgeInsets.symmetric(horizontal: 4),
        offset: const Offset(2, -4),
        child: SvgIcon(Assets.bell, size: 20, color: t.textPrimary),
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
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              // Elevated white pill so each action reads as a real button that
              // pops against the tinted top-bar band — not a bare glyph. Hover
              // warms the fill + border for a tactile step-up.
              color: hover ? t.bgHover : t.bgElevated,
              borderRadius: BorderRadius.circular(WebTokens.rMd),
              border: Border.all(
                color: hover ? t.borderStrong : t.borderDefault,
                width: 1,
              ),
              boxShadow: WebTokens.shadowXs,
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
                  color: _hover ? t.accent : t.borderSubtle,
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
