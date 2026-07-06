import 'package:flutter/material.dart';

/// Wraps a page body so a detail panel can slide in from the right.
///
/// Set [openId] to a non-null value to open the panel; set it back to null
/// (or call [onClose]) to slide it back out. [panelBuilder] renders the
/// panel content for the current open id — a callback so the same host
/// can serve any detail screen (task, ticket, user, org, …).
///
/// Panel width is responsive per the Material 3 window classes:
///   * < 900 px → panel fills the viewport (the list underneath would be
///     too cramped to remain useful in split mode).
///   * ≥ 900 px → panel takes ~58% of the viewport, clamped so ultrawide
///     monitors don't stretch it past [_kPanelMaxWidth] and small desktop
///     widths still get a legible panel via [_kPanelMinWidth].
///
/// This widget is web-only in spirit — mobile detail screens push over
/// the shell rather than slide in — but it doesn't hard-depend on the
/// web tokens, so it lives under `widgets/`.
class SlideOverHost extends StatelessWidget {
  const SlideOverHost({
    super.key,
    required this.child,
    required this.openId,
    required this.onClose,
    required this.panelBuilder,
    this.fullscreen = false,
  });

  /// Content rendered underneath the panel (typically the list screen).
  final Widget child;

  /// Identifier of the item shown in the panel, or null when closed.
  /// Changing this to a new non-null value swaps the panel contents in place;
  /// setting it to null slides the panel back out.
  final int? openId;

  /// Called from the panel's close button (or programmatically) to slide
  /// the panel back out.
  final VoidCallback onClose;

  /// Builds the panel body for the given id. Called each time [openId]
  /// changes to a new non-null value — the returned widget is keyed by the
  /// id so its state resets between different items.
  final Widget Function(BuildContext context, int id, VoidCallback onClose)
      panelBuilder;

  /// When true the panel takes the full viewport width and the list
  /// underneath is pushed off to the left. The panel's own header renders
  /// an expand/collapse toggle that flips this on the parent state.
  final bool fullscreen;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final double panelWidth;
        if (fullscreen) {
          panelWidth = width;
        } else if (width < _kSplitBreakpoint) {
          panelWidth = width;
        } else {
          panelWidth = (width * _kPanelRatio)
              .clamp(_kPanelMinWidth, _kPanelMaxWidth);
        }
        final isOpen = openId != null;
        // Split-pane layout: the underlying content's right edge animates
        // outward so the panel slides into space vacated by the list, instead
        // of overlaying it. Both edges use the same duration/curve so the
        // transition reads as a single motion.
        return Stack(
          fit: StackFit.expand,
          children: [
            AnimatedPositioned(
              duration: _kAnimDuration,
              curve: _kAnimCurve,
              left: 0,
              top: 0,
              bottom: 0,
              right: isOpen ? panelWidth : 0,
              child: child,
            ),
            AnimatedPositioned(
              duration: _kAnimDuration,
              curve: _kAnimCurve,
              top: 0,
              bottom: 0,
              right: isOpen ? 0 : -panelWidth,
              width: panelWidth,
              // Host-level left-edge seam: a 1 px hairline border draws the
              // split between the list and the panel. The previous version
              // added a leftward-bleeding shadow, but the seam read as a
              // heavy elevation against the flat list bg — removed at the
              // user's request so the split feels flush with the rest of
              // the page.
              //
              // `position: foreground` is deliberate — the panel's inner
              // Material paints its opaque bg over the box, so a default
              // (background) border sits underneath and is invisible.
              // Painting the border on top of the child keeps the seam
              // crisp against the panel's white surface.
              child: DecoratedBox(
                position: DecorationPosition.foreground,
                decoration: BoxDecoration(
                  border: Border(
                    left: BorderSide(
                      color: const Color(0xFFD6D6D6),
                      width: 1,
                    ),
                  ),
                ),
                child: _PanelSlot(
                  openId: openId,
                  onClose: onClose,
                  panelBuilder: panelBuilder,
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

/// Keeps the panel content mounted through the slide-out animation so it
/// doesn't visibly clear before the transition finishes.
class _PanelSlot extends StatefulWidget {
  const _PanelSlot({
    required this.openId,
    required this.onClose,
    required this.panelBuilder,
  });
  final int? openId;
  final VoidCallback onClose;
  final Widget Function(BuildContext context, int id, VoidCallback onClose)
      panelBuilder;

  @override
  State<_PanelSlot> createState() => _PanelSlotState();
}

class _PanelSlotState extends State<_PanelSlot> {
  int? _visibleId;

  @override
  void initState() {
    super.initState();
    _visibleId = widget.openId;
  }

  @override
  void didUpdateWidget(covariant _PanelSlot old) {
    super.didUpdateWidget(old);
    if (widget.openId != null && widget.openId != _visibleId) {
      setState(() => _visibleId = widget.openId);
    } else if (widget.openId == null && _visibleId != null) {
      Future.delayed(_kAnimDuration, () {
        if (mounted && widget.openId == null) {
          setState(() => _visibleId = null);
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final id = _visibleId;
    if (id == null) return const SizedBox.shrink();
    return KeyedSubtree(
      key: ValueKey(id),
      child: widget.panelBuilder(context, id, widget.onClose),
    );
  }
}

// --- Responsive width + animation constants ---------------------------------
// Kept file-private so the values live with the widget that consumes them.

const _kSplitBreakpoint = 905.0;
// Bumped from 0.58 → 0.68 (and max 920 → 1200) so the panel is wide enough
// to host a two-column body (message column + fields sidebar) without the
// message column collapsing under a rigid 300 px sidebar.
const _kPanelRatio = 0.68;
const _kPanelMinWidth = 540.0;
const _kPanelMaxWidth = 1200.0;

const _kAnimDuration = Duration(milliseconds: 260);
const _kAnimCurve = Curves.easeOutCubic;
