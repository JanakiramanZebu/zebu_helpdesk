import 'package:flutter/material.dart';

import '../../../res/zebu_spacing.dart';
import '../../../res/zebu_text_styles.dart';
import '../../../res/zebu_theme.dart';

/// Floating create button — the web counterpart of the mobile app's FAB.
///
/// Sits bottom-right over the workspace and fans out its two options above
/// itself. It replaces a rail row that opened a full 240 px panel to offer the
/// same two choices: a whole pane is a lot of machinery for a question with
/// two answers, and the panel pushed the workspace sideways every time.
///
/// Click to open, not hover. The pointer crosses this corner on its way to
/// the scrollbar and the bulk bar, and a menu that opens on approach is a
/// menu that opens when you did not ask.
class CreateFab extends StatefulWidget {
  const CreateFab({
    super.key,
    required this.onNewTicket,
    required this.onNewTask,
  });

  final VoidCallback onNewTicket;
  final VoidCallback onNewTask;

  @override
  State<CreateFab> createState() => _CreateFabState();
}

class _CreateFabState extends State<CreateFab>
    with SingleTickerProviderStateMixin {
  late final AnimationController _anim = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 180),
  );
  bool _open = false;

  @override
  void dispose() {
    _anim.dispose();
    super.dispose();
  }

  void _toggle() {
    setState(() => _open = !_open);
    _open ? _anim.forward() : _anim.reverse();
  }

  void _pick(VoidCallback action) {
    _toggle();
    action();
  }

  @override
  Widget build(BuildContext context) {
    final t = ZebuTheme.of(context);
    return Stack(
      children: [
        // Full-bleed dismiss layer, only while open. Without it the only way
        // to back out is to hit the 56 px button again.
        if (_open)
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: _toggle,
              child: ColoredBox(color: Colors.black.withValues(alpha: 0.04)),
            ),
          ),
        Positioned(
          right: ZebuSpacing.s6,
          bottom: ZebuSpacing.s6,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              _Option(
                anim: _anim,
                order: 1,
                icon: Icons.confirmation_number_outlined,
                label: 'New ticket',
                onTap: () => _pick(widget.onNewTicket),
              ),
              _Option(
                anim: _anim,
                order: 0,
                icon: Icons.check_circle_outline,
                label: 'New task',
                onTap: () => _pick(widget.onNewTask),
              ),
              const SizedBox(height: ZebuSpacing.s3),
              _FabButton(open: _open, onTap: _toggle, accent: t.accent),
            ],
          ),
        ),
      ],
    );
  }
}

/// One fanned-out choice. Slides up and fades in, staggered by [order] so the
/// two read as arriving in sequence rather than appearing as a block.
class _Option extends StatelessWidget {
  const _Option({
    required this.anim,
    required this.order,
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final Animation<double> anim;
  final int order;
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = ZebuTheme.of(context);
    final curve = CurvedAnimation(
      parent: anim,
      curve: Interval(order * 0.15, 1, curve: Curves.easeOutCubic),
    );
    return SizeTransition(
      sizeFactor: curve,
      axisAlignment: 1,
      child: FadeTransition(
        opacity: curve,
        child: Padding(
          padding: const EdgeInsets.only(bottom: ZebuSpacing.s2),
          child: _OptionPill(
            icon: icon,
            label: label,
            onTap: onTap,
            accent: t.accent,
          ),
        ),
      ),
    );
  }
}

class _OptionPill extends StatefulWidget {
  const _OptionPill({
    required this.icon,
    required this.label,
    required this.onTap,
    required this.accent,
  });
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color accent;

  @override
  State<_OptionPill> createState() => _OptionPillState();
}

class _OptionPillState extends State<_OptionPill> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final t = ZebuTheme.of(context);
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 100),
          height: 42,
          padding: const EdgeInsets.symmetric(horizontal: ZebuSpacing.s4),
          decoration: BoxDecoration(
            color: _hover ? t.bgHover : t.bgElevated,
            borderRadius: BorderRadius.circular(ZebuRadius.rSm),
            border: Border.all(color: t.borderSubtle, width: 1),
            boxShadow: const [
              BoxShadow(
                color: Color(0x24101828),
                blurRadius: 16,
                offset: Offset(0, 6),
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(widget.icon, size: 18, color: widget.accent),
              const SizedBox(width: ZebuSpacing.s3),
              Text(
                widget.label,
                style: ZebuTextStyles.body(
                  context,
                  color: t.textPrimary,
                  fontWeight: ZebuFonts.semiBold,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FabButton extends StatefulWidget {
  const _FabButton({
    required this.open,
    required this.onTap,
    required this.accent,
  });
  final bool open;
  final VoidCallback onTap;
  final Color accent;

  @override
  State<_FabButton> createState() => _FabButtonState();
}

class _FabButtonState extends State<_FabButton> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final t = ZebuTheme.of(context);
    return Tooltip(
      message: widget.open ? 'Close' : 'Create',
      waitDuration: const Duration(milliseconds: 400),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 140),
            width: 52,
            height: 52,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: _hover ? t.accentHover : widget.accent,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: widget.accent.withValues(alpha: 0.32),
                  blurRadius: 18,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            // The glyph turns rather than swapping — a + rotating 45° into a
            // × says "this is the same control, now reversed".
            child: AnimatedRotation(
              duration: const Duration(milliseconds: 180),
              turns: widget.open ? 0.125 : 0,
              child: const Icon(
                Icons.add_rounded,
                size: 26,
                color: Colors.white,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
