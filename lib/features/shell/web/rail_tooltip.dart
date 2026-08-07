import 'dart:async';

import 'package:flutter/material.dart';

import '_shell_tokens.dart';
import '../../../res/zebu_spacing.dart';

/// Dark pill tooltip anchored to the **right** of its child.
///
/// Flutter's built-in [Tooltip] only positions above or below its target,
/// which reads wrong against a vertical icon rail — the label wants to sit
/// beside the glyph, the way Pinterest, Intercom, and Zendesk all do it.
/// This is the same anchored-overlay technique `showAppDropdown` uses, in
/// hover form: a [LayerLink] pins a [CompositedTransformFollower] to the
/// target's centre-right edge, and an [OverlayPortal] mounts it above every
/// other layer so it is never clipped by the rail's own bounds.
///
/// Set [enabled] to false to suppress the tooltip entirely — the rail does
/// this the moment it hover-expands, because the labels are then visible
/// inline and a tooltip would just double up on them.
class RailTooltip extends StatefulWidget {
  const RailTooltip({
    super.key,
    required this.message,
    required this.child,
    this.enabled = true,
  });

  final String message;
  final Widget child;

  /// When false the tooltip never shows, and hides immediately if visible.
  final bool enabled;

  /// Hover dwell before the pill appears. Long enough that sweeping the
  /// pointer across the rail on the way elsewhere doesn't strobe labels.
  static const waitDuration = Duration(milliseconds: 320);

  @override
  State<RailTooltip> createState() => _RailTooltipState();
}

class _RailTooltipState extends State<RailTooltip> {
  final _portal = OverlayPortalController();
  final _link = LayerLink();
  Timer? _timer;

  @override
  void didUpdateWidget(RailTooltip old) {
    super.didUpdateWidget(old);
    // The rail expanded (or the item was disabled) while the pill was up —
    // drop it now rather than waiting for the pointer to leave.
    if (!widget.enabled) _hide();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _scheduleShow() {
    if (!widget.enabled) return;
    _timer?.cancel();
    _timer = Timer(RailTooltip.waitDuration, () {
      if (mounted && widget.enabled) _portal.show();
    });
  }

  void _hide() {
    _timer?.cancel();
    if (_portal.isShowing) _portal.hide();
  }

  @override
  Widget build(BuildContext context) {
    final s = ShellTokens.of(context);
    return CompositedTransformTarget(
      link: _link,
      child: MouseRegion(
        onEnter: (_) => _scheduleShow(),
        onExit: (_) => _hide(),
        child: OverlayPortal(
          controller: _portal,
          overlayChildBuilder: (_) => Positioned(
            left: 0,
            top: 0,
            // The follower is hit-test transparent so the pill never steals
            // the pointer from the rail item it is describing.
            child: IgnorePointer(
              child: CompositedTransformFollower(
                link: _link,
                targetAnchor: Alignment.centerRight,
                followerAnchor: Alignment.centerLeft,
                offset: const Offset(10, 0),
                child: _Pill(message: widget.message, tokens: s),
              ),
            ),
          ),
          child: widget.child,
        ),
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({required this.message, required this.tokens});
  final String message;
  final ShellTokens tokens;

  @override
  Widget build(BuildContext context) {
    // Overlay children sit outside the app's Material tree, so the text
    // needs its own Material ancestor to pick up a baseline text style.
    return Material(
      color: Colors.transparent,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
        decoration: BoxDecoration(
          color: tokens.tooltipBg,
          borderRadius: BorderRadius.circular(ZebuRadius.rXs),
          boxShadow: ZebuElevation.shadowMd,
        ),
        child: Text(
          message,
          style: TextStyle(
            color: tokens.tooltipFg,
            fontSize: 12,
            fontWeight: FontWeight.w500,
            height: 1.1,
          ),
        ),
      ),
    );
  }
}
