import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../../core/assets.dart';
import '../../../core/theme/app_text.dart';
import '../../../core/theme/app_theme.dart';
import '../../../widgets/glass.dart';

/// Floating, frosted-glass bottom navigation bar in the **task-app pattern**: a
/// rounded aurora-glass bar carrying four destinations, split around a raised
/// brand-blue **"+" create button** that pokes up out of the bar's center.
///
/// The four tabs (Home / Ticket / Tasks / Inbox) map to shell branches 0–3;
/// the fifth branch (More) is reached from the header, not the bar. Tapping the
/// center button raises a small popup above it to create a **ticket** or a
/// **task** ([onCreateTicket] / [onCreateTask]) — it does not switch tabs. The
/// **Inbox** tab carries an unread [notificationCount] badge.
class FloatingNavBar extends StatelessWidget {
  const FloatingNavBar({
    super.key,
    required this.currentIndex,
    required this.onTap,
    required this.onCreateTicket,
    required this.onCreateTask,
    this.notificationCount = 0,
  });

  final int currentIndex;
  final ValueChanged<int> onTap;

  /// Chosen "New ticket" from the center create popup.
  final VoidCallback onCreateTicket;

  /// Chose "New task" from the center create popup.
  final VoidCallback onCreateTask;

  /// Unread notification count shown as a badge on the Inbox tab.
  final int notificationCount;

  // The four bar destinations, in order. The center gap for the "+" is inserted
  // between index 1 (Ticket) and index 2 (Tasks).
  static const _items = <({String icon, String label})>[
    (icon: Assets.navDashboard, label: 'Home'),
    (icon: Assets.navTickets, label: 'Tickets'),
    (icon: Assets.navTasks, label: 'Tasks'),
    (icon: Assets.navInbox, label: 'Inbox'),
  ];

  // Diameter of the raised create button and how far it pokes above the bar.
  static const double _fab = 56;
  static const double _barHeight = 64;
  static const double _protrusion = 22;

  /// The brand blue, resolved for the current brightness.
  static Color brandBlue(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark
      ? AppTheme.brandLight
      : AppTheme.brand;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bottomInset = MediaQuery.of(context).padding.bottom;
    // Translucent fill so the blur behind it reads as frosted glass.
    final barColor = (isDark ? const Color(0xFF141A2B) : Colors.white)
        .withValues(alpha: isDark ? 0.66 : 0.72);

    return Padding(
      padding: EdgeInsets.fromLTRB(
        16,
        0,
        16,
        (bottomInset > 0 ? bottomInset : 0) + 10,
      ),
      child: SizedBox(
        // Tall enough to hold the bar plus the button poking out the top.
        height: _barHeight + _protrusion,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            // --- The frosted bar, pinned to the bottom -----------------------
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              height: _barHeight,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(26),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(
                        alpha: isDark ? 0.42 : 0.14,
                      ),
                      blurRadius: 26,
                      offset: const Offset(0, 10),
                    ),
                  ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(26),
                  child: Glass.frost(
                    sigma: 22,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: barColor,
                        borderRadius: BorderRadius.circular(26),
                        border: Border.all(color: Glass.border(context, 0.28)),
                      ),
                      child: Row(
                        children: [
                          _NavItem(
                            icon: _items[0].icon,
                            label: _items[0].label,
                            selected: currentIndex == 0,
                            onTap: () => onTap(0),
                          ),
                          _NavItem(
                            icon: _items[1].icon,
                            label: _items[1].label,
                            selected: currentIndex == 1,
                            onTap: () => onTap(1),
                          ),
                          // Center gap the "+" sits over.
                          const SizedBox(width: _fab + 12),
                          _NavItem(
                            icon: _items[2].icon,
                            label: _items[2].label,
                            selected: currentIndex == 2,
                            onTap: () => onTap(2),
                          ),
                          _NavItem(
                            icon: _items[3].icon,
                            label: _items[3].label,
                            selected: currentIndex == 3,
                            badgeCount: notificationCount,
                            onTap: () => onTap(3),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),

            // --- The raised center create button -----------------------------
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: Center(
                child: _CreateButton(
                  onCreateTicket: onCreateTicket,
                  onCreateTask: onCreateTask,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The raised brand-blue "+" button. Tapping it opens a small speed-dial popup
/// above the button offering "New ticket" / "New task", and rotates the "+"
/// into an "×" while open.
class _CreateButton extends StatefulWidget {
  const _CreateButton({required this.onCreateTicket, required this.onCreateTask});

  final VoidCallback onCreateTicket;
  final VoidCallback onCreateTask;

  @override
  State<_CreateButton> createState() => _CreateButtonState();
}

class _CreateButtonState extends State<_CreateButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 200),
  );
  OverlayEntry? _entry;

  @override
  void dispose() {
    _entry?.remove();
    _ctrl.dispose();
    super.dispose();
  }

  void _toggle() => _entry == null ? _open() : _close();

  void _open() {
    final box = context.findRenderObject() as RenderBox;
    final origin = box.localToGlobal(Offset.zero);
    final screen = MediaQuery.of(context).size;
    // Distance from the screen bottom up to the button's top edge — the popup
    // sits just above that so it "grows" out of the button.
    final bottom = screen.height - origin.dy + 12;

    _entry = OverlayEntry(
      builder: (_) => _CreatePopup(
        animation: _ctrl,
        bottom: bottom,
        onDismiss: _close,
        onTicket: () {
          _close();
          widget.onCreateTicket();
        },
        onTask: () {
          _close();
          widget.onCreateTask();
        },
      ),
    );
    Overlay.of(context).insert(_entry!);
    _ctrl.forward();
    setState(() {});
  }

  Future<void> _close() async {
    if (_entry == null) return;
    await _ctrl.reverse();
    _entry?.remove();
    _entry = null;
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final gradient = LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: const [AppTheme.brandLight, AppTheme.brand],
    );

    return Semantics(
      button: true,
      label: 'Create',
      child: Material(
        color: Colors.transparent,
        shape: const CircleBorder(),
        clipBehavior: Clip.antiAlias,
        child: Ink(
          decoration: BoxDecoration(
            gradient: gradient,
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: AppTheme.brand.withValues(alpha: 0.5),
                blurRadius: 18,
                offset: const Offset(0, 6),
              ),
            ],
            // A ring the color of the canvas so it reads as lifted off the bar.
            border: Border.all(color: Glass.overlayFill(context), width: 3),
          ),
          child: InkWell(
            onTap: _toggle,
            customBorder: const CircleBorder(),
            child: SizedBox(
              width: FloatingNavBar._fab,
              height: FloatingNavBar._fab,
              child: Center(
                // Rotate + → × as the popup opens (0.125 turns = 45°).
                child: RotationTransition(
                  turns: Tween<double>(begin: 0, end: 0.125).animate(_ctrl),
                  child: const Icon(
                    Icons.add_rounded,
                    color: Colors.white,
                    size: 30,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The overlay content for the create speed-dial: a tap-to-dismiss scrim plus
/// two labelled actions that rise above the "+" button.
class _CreatePopup extends StatelessWidget {
  const _CreatePopup({
    required this.animation,
    required this.bottom,
    required this.onDismiss,
    required this.onTicket,
    required this.onTask,
  });

  final Animation<double> animation;
  final double bottom;
  final VoidCallback onDismiss;
  final VoidCallback onTicket;
  final VoidCallback onTask;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        // Dim scrim that closes on tap.
        Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onDismiss,
            child: FadeTransition(
              opacity: animation,
              child: ColoredBox(color: Colors.black.withValues(alpha: 0.35)),
            ),
          ),
        ),
        Positioned(
          left: 0,
          right: 0,
          bottom: bottom,
          child: IgnorePointer(
            ignoring: false,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _PopupAction(
                  animation: animation,
                  interval: const Interval(0.15, 1.0, curve: Curves.easeOut),
                  icon: Icons.confirmation_number_outlined,
                  label: 'New ticket',
                  onTap: onTicket,
                ),
                const SizedBox(height: 12),
                _PopupAction(
                  animation: animation,
                  interval: const Interval(0.0, 0.85, curve: Curves.easeOut),
                  icon: Icons.check_circle_outline,
                  label: 'New task',
                  onTap: onTask,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// A single labelled pill in the create popup: rounded card + brand-blue icon.
class _PopupAction extends StatelessWidget {
  const _PopupAction({
    required this.animation,
    required this.interval,
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final Animation<double> animation;
  final Interval interval;
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final blue = FloatingNavBar.brandBlue(context);
    final curved = CurvedAnimation(parent: animation, curve: interval);

    return FadeTransition(
      opacity: curved,
      child: SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(0, 0.4),
          end: Offset.zero,
        ).animate(curved),
        child: Material(
          color: Glass.overlayFill(context),
          elevation: 6,
          shadowColor: Colors.black.withValues(alpha: 0.3),
          borderRadius: BorderRadius.circular(16),
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(16),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icon, size: 20, color: blue),
                  const SizedBox(width: 10),
                  AppText.custmText(
                    context,
                    label,
                    fs: 14,
                    fw: 2,
                    color: Glass.textPrimary(context),
                  ),
                ],
              ),
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
    final tint = selected ? FloatingNavBar.brandBlue(context) : muted;

    return Expanded(
      child: Semantics(
        selected: selected,
        button: true,
        label: label,
        child: InkResponse(
          onTap: onTap,
          radius: 40,
          splashColor: FloatingNavBar.brandBlue(context).withValues(alpha: 0.10),
          highlightColor: Colors.transparent,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              _Glyph(
                icon: icon,
                color: tint,
                badgeCount: badgeCount,
                badgeBorder: scheme.surface,
              ),
              const SizedBox(height: 4),
              AppText.custmText(
                context,
                label,
                fs: 10.5,
                color: tint,
                fw: selected ? 2 : 1,
                maxLines: 1,
                overflow: TextOverflow.clip,
                letterSpacing: 0.1,
              ),
              // A tiny underline that fades in on the active tab.
              AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                curve: Curves.easeOut,
                margin: const EdgeInsets.only(top: 3),
                width: selected ? 16 : 0,
                height: 2,
                decoration: BoxDecoration(
                  color: FloatingNavBar.brandBlue(context),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ],
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
    required this.badgeBorder,
  });

  final String icon;
  final Color color;
  final int badgeCount;

  /// Border color of the count badge, matched to whatever it's drawn over.
  final Color badgeBorder;

  @override
  Widget build(BuildContext context) {
    final glyph = SvgPicture.asset(
      icon,
      width: 22,
      height: 22,
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
              border: Border.all(color: badgeBorder, width: 1.5),
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
