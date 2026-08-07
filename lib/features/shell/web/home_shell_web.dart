import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/routes.dart';
import '../../tasks/web/create_task_screen_web.dart';
import '../../tickets/web/create_ticket_screen_web.dart';
import '_shell_tokens.dart';
import 'nav_panel.dart';
import 'nav_rail.dart';
import 'profile_menu_popover.dart';
import '../../../res/zebu_theme.dart';
import '../../../res/zebu_text_styles.dart';

/// Web-only top-level shell. Replaces `HomeShell` on the web target.
///
/// Three columns on one canvas:
///
/// ```
///   ┌────┬───────────────┬──────────────────────────┐
///   │rail│  sub-panel    │      workspace card      │
///   │ 72 │  280 · animated to 0 when there is       │
///   │    │  nothing to show                         │
///   └────┴───────────────┴──────────────────────────┘
/// ```
///
/// The rail is icon-only at rest and hover-expands to a labelled sidebar,
/// **floating over** the other two columns so the page never reflows just
/// because the pointer crossed it. The sub-panel is the opposite: it takes
/// real layout space and pushes the workspace, because its contents are a
/// place you work from rather than a menu you glance at.
///
/// Two things can occupy the panel slot:
///   * a **section panel** tied to the active destination — persistent, and
///     collapsed/restored by clicking the section you are already in;
///   * a **transient panel** opened by an action (Create) — dismisses on
///     choice, on ✕, on re-clicking the CTA, or on a click in the content.
///
/// There is no top bar. It previously held only the brand lockup, a theme
/// toggle, and an avatar; all three now live in the rail, so the bar was
/// 60 px of empty chrome. See commit 2262f5a to restore it.
class HomeShellWeb extends ConsumerStatefulWidget {
  const HomeShellWeb({super.key, required this.shell});
  final StatefulNavigationShell shell;

  @override
  ConsumerState<HomeShellWeb> createState() => _HomeShellWebState();
}

class _HomeShellWebState extends ConsumerState<HomeShellWeb> {
  /// Pointer is dwelling on the rail — see [_onRailEnter] for why this is
  /// timer-gated rather than bound straight to the MouseRegion.
  bool _railExpanded = false;

  /// Transient Create panel is up.
  bool _createOpen = false;

  /// The profile popover is open. It anchors to the rail's footer row, so
  /// the rail has to stay expanded underneath it for as long as it is up —
  /// letting the pointer-exit collapse it would leave the menu attached to
  /// nothing.
  bool _profileMenuOpen = false;

  /// Agent collapsed the section panel by re-clicking its rail item.
  /// Session-scoped for now; persisting it is a follow-up once the panel
  /// earns its keep.
  bool _panelCollapsed = false;

  Timer? _hoverTimer;

  // Hover-expanding on a bare `onEnter` makes the rail strobe every time the
  // pointer crosses it on the way somewhere else. A short dwell on entry and
  // a slightly longer grace on exit is what makes it feel deliberate — the
  // same tuning Intercom uses.
  static const _enterDelay = Duration(milliseconds: 140);
  static const _exitDelay = Duration(milliseconds: 180);

  @override
  void dispose() {
    _hoverTimer?.cancel();
    super.dispose();
  }

  void _setRail(bool value, Duration delay) {
    _hoverTimer?.cancel();
    if (_railExpanded == value) return;
    _hoverTimer = Timer(delay, () {
      if (mounted) setState(() => _railExpanded = value);
    });
  }

  void _onRailEnter() => _setRail(true, _enterDelay);
  void _onRailExit() => _setRail(false, _exitDelay);

  /// Collapses the rail immediately, skipping the exit grace period — used
  /// after a selection, where waiting would leave the rail hanging open over
  /// the page the agent just navigated to.
  void _collapseRailNow() {
    _hoverTimer?.cancel();
    if (_railExpanded) setState(() => _railExpanded = false);
  }

  void _toggleCreate() {
    _collapseRailNow();
    setState(() => _createOpen = !_createOpen);
  }

  void _closeCreate() {
    if (_createOpen) setState(() => _createOpen = false);
  }

  void _select(int index) {
    _collapseRailNow();
    _closeCreate();

    // Clicking the section you are already in toggles its panel. Only
    // Workspace has one; every other section keeps the plain "reset to my
    // initial location" behaviour.
    if (index == widget.shell.currentIndex) {
      if (_hasSectionPanel(index)) {
        setState(() => _panelCollapsed = !_panelCollapsed);
      } else {
        widget.shell.goBranch(index, initialLocation: true);
      }
      return;
    }

    // Entering a section always arrives with its panel open, whatever state
    // the previous section's panel was left in.
    setState(() => _panelCollapsed = false);

    // Workspace has no screen of its own — it is a panel of destinations —
    // so entering it lands on the first of them.
    if (index == kIdxWorkspace) {
      context.go(Routes.users);
      return;
    }

    widget.shell.goBranch(index);
  }

  void _goWorkspace(String path) {
    _collapseRailNow();
    context.go(path);
  }

  /// Opens the profile popover and holds the rail open for its lifetime.
  ///
  /// The pointer necessarily leaves the rail to reach the menu, which would
  /// otherwise trip the exit timer and collapse the surface the menu is
  /// anchored to. `showProfileMenu` completes when the popover is dismissed,
  /// so awaiting it is exactly the window the rail must stay open for.
  Future<void> _openProfileMenu(BuildContext anchor) async {
    _hoverTimer?.cancel();
    setState(() => _profileMenuOpen = true);
    try {
      await showProfileMenu(anchor);
    } finally {
      if (mounted) setState(() => _profileMenuOpen = false);
    }
  }

  /// Whether [index] has a second level at all.
  ///
  /// Only Workspace does. Tickets / Tasks / Inbox keep their saved views as a
  /// `SegmentedTabBar` on the screen itself rather than in this panel — the
  /// tabs sit with the table they filter, which is where they were.
  static bool _hasSectionPanel(int index) => index == kIdxWorkspace;

  /// The panel belonging to the active section, or null when it has none.
  Widget? _sectionPanel(int index, String path) => switch (index) {
    kIdxWorkspace => WorkspacePanel(currentPath: path, onGo: _goWorkspace),
    _ => null,
  };

  @override
  Widget build(BuildContext context) {
    final base = Theme.of(context);
    final t = ZebuTheme.of(context);
    final s = ShellTokens.of(context);

    final path = GoRouterState.of(context).uri.path;
    final index = widget.shell.currentIndex;

    // Below the breakpoint a 280 px panel plus an open detail slide-over
    // leaves the list column unusable, so the panel stands down.
    final tooNarrow =
        MediaQuery.sizeOf(context).width < ShellTokens.panelCollapseBreakpoint;

    // Workspace is the only section with a second level: the destinations
    // that used to sit behind the "More" tab.
    final sectionPanel = _sectionPanel(index, path);
    final hasSection = sectionPanel != null;
    final showPanel =
        _createOpen || (hasSection && !_panelCollapsed && !tooNarrow);

    // The panel widget is always built, and visibility is expressed purely
    // as width. Tearing the child out at the same moment the width animates
    // would pop the contents away before the column finished closing.
    final panel = _createOpen
        ? CreatePanel(
            onClose: _closeCreate,
            onNewTicket: () {
              _closeCreate();
              showCreateTicketDialog(context);
            },
            onNewTask: () {
              _closeCreate();
              showCreateTaskDialog(context);
            },
          )
        : (sectionPanel ?? const SizedBox.shrink());

    // Apply the Zebu Premium typeface (Inter) to the entire web tree — the
    // family called out globally in DESIGN_SYSTEM.md. Mobile never reaches
    // this widget, so this scoped override never affects Android/iOS, which
    // already use Inter via AppTheme.
    return Theme(
      data: base.copyWith(
        textTheme: ZebuFonts.textTheme(base.textTheme),
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
          body: Stack(
            children: [
              // --- Layout row: rail gutter | panel | workspace ------------
              Row(
                children: [
                  // The rail itself floats in the Stack above; this reserves
                  // its resting footprint so content starts clear of it.
                  const SizedBox(width: ShellTokens.railWidth),
                  _PanelSlot(open: showPanel, child: panel),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(
                        ShellTokens.workspaceGutter,
                        ShellTokens.workspaceGutter,
                        ShellTokens.workspaceGutter,
                        ShellTokens.workspaceGutter,
                      ),
                      // Inset workspace: the routed content lives in a
                      // rounded card floating on the chrome canvas. The
                      // hairline is painted as a *foreground* decoration
                      // because every routed screen fills an opaque
                      // bgPrimary that would otherwise bury a background
                      // border; the ClipRRect keeps full-bleed screen
                      // content and slide-over panels inside the rounded
                      // corners. The base ColoredBox guarantees the canvas
                      // never flashes through during branch swaps.
                      child: DecoratedBox(
                        position: DecorationPosition.foreground,
                        decoration: BoxDecoration(
                          border: Border.all(color: s.cardBorder, width: 1),
                          borderRadius: BorderRadius.circular(
                            ShellTokens.workspaceRadius,
                          ),
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(
                            ShellTokens.workspaceRadius,
                          ),
                          child: ColoredBox(
                            color: t.bgPrimary,
                            child: widget.shell,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),

              // --- Dismiss barrier for the transient Create panel ---------
              // Covers only the workspace column, so the first click in the
              // content closes the panel instead of acting on the page.
              if (_createOpen)
                Positioned(
                  left: ShellTokens.railWidth + ShellTokens.panelWidth,
                  top: 0,
                  right: 0,
                  bottom: 0,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: _closeCreate,
                  ),
                ),

              // --- Section-panel collapse chevron ------------------------
              // Parked on request. The panel can still be collapsed and
              // restored by clicking the section you are already in (see
              // [_select]), so the capability is intact — this is only the
              // edge affordance. Restore this block and [_CollapseChevron]
              // below to bring it back.
              //
              // if (hasSection && !_createOpen && !tooNarrow)
              //   AnimatedPositioned(
              //     duration: const Duration(milliseconds: 200),
              //     curve: Curves.easeOutCubic,
              //     left: showPanel
              //         ? ShellTokens.railWidth + ShellTokens.panelWidth - 11
              //         : ShellTokens.railWidth + 2,
              //     top: ShellTokens.workspaceGutter + 22,
              //     child: _CollapseChevron(
              //       collapsed: !showPanel,
              //       onTap: () =>
              //           setState(() => _panelCollapsed = !_panelCollapsed),
              //     ),
              //   ),

              // --- Floating rail -----------------------------------------
              Positioned(
                left: 0,
                top: 0,
                bottom: 0,
                child: MouseRegion(
                  onEnter: (_) => _onRailEnter(),
                  onExit: (_) => _onRailExit(),
                  child: NavRail(
                    expanded: _railExpanded || _profileMenuOpen,
                    currentIndex: widget.shell.currentIndex,
                    createOpen: _createOpen,
                    onSelect: _select,
                    onCreate: _toggleCreate,
                    onProfile: _openProfileMenu,
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

// ---------------------------------------------------------------------------
// Panel slot
// ---------------------------------------------------------------------------

/// Animates the sub-panel column between zero and [ShellTokens.panelWidth],
/// pushing the workspace as it goes.
///
/// The child is laid out at full panel width throughout via [OverflowBox] and
/// revealed by clipping, so its contents never reflow mid-animation — the
/// same technique the rail uses for its labels.
class _PanelSlot extends StatelessWidget {
  const _PanelSlot({required this.open, required this.child});
  final bool open;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOutCubic,
      width: open ? ShellTokens.panelWidth : 0,
      child: ClipRect(
        child: OverflowBox(
          alignment: Alignment.centerLeft,
          minWidth: ShellTokens.panelWidth,
          maxWidth: ShellTokens.panelWidth,
          child: Padding(
            padding: const EdgeInsets.symmetric(
              vertical: ShellTokens.workspaceGutter,
            ),
            child: child,
          ),
        ),
      ),
    );
  }
}

// Parked with its usage above — restore both together.
// /// Zendesk-style edge affordance for collapsing the section panel — an
// /// agent reading a long ticket thread can reclaim 280 px without losing
// /// their place in the section.
// class _CollapseChevron extends StatefulWidget {
//   const _CollapseChevron({required this.collapsed, required this.onTap});
//   final bool collapsed;
//   final VoidCallback onTap;
//
//   @override
//   State<_CollapseChevron> createState() => _CollapseChevronState();
// }

// class _CollapseChevronState extends State<_CollapseChevron> {
//   bool _hover = false;
//
//   @override
//   Widget build(BuildContext context) {
//     final t = ZebuTheme.of(context);
//     final s = ShellTokens.of(context);
//     return Tooltip(
//       message: widget.collapsed ? 'Show panel' : 'Hide panel',
//       child: MouseRegion(
//         cursor: SystemMouseCursors.click,
//         onEnter: (_) => setState(() => _hover = true),
//         onExit: (_) => setState(() => _hover = false),
//         child: GestureDetector(
//           behavior: HitTestBehavior.opaque,
//           onTap: widget.onTap,
//           child: Container(
//             width: 22,
//             height: 22,
//             alignment: Alignment.center,
//             decoration: BoxDecoration(
//               color: _hover ? t.bgHover : t.bgElevated,
//               shape: BoxShape.circle,
//               border: Border.all(color: s.cardBorder, width: 1),
//               boxShadow: ZebuElevation.shadowSm,
//             ),
//             child: Icon(
//               widget.collapsed
//                   ? Icons.chevron_right_rounded
//                   : Icons.chevron_left_rounded,
//               size: 16,
//               color: _hover ? t.textPrimary : t.textSecondary,
//             ),
//           ),
//         ),
//       ),
//     );
//   }
// }

// ---------------------------------------------------------------------------
// Scrollbar behavior
// ---------------------------------------------------------------------------

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
