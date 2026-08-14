import 'package:flutter/material.dart';

import '../../res/zebu_theme.dart';

/// A scrolling body with a footer that casts a shadow **only while there is
/// more content below it**.
///
/// A dialog that scrolls looks exactly like a dialog that does not: the last
/// visible row sits flush against the footer either way, and nothing says
/// whether it is the last row or merely the last one you can see. A shadow
/// that appears only when something is hidden turns the footer edge into the
/// answer — and disappears once you reach the end, so it never lies.
class ZebuScrollableBody extends StatefulWidget {
  const ZebuScrollableBody({
    super.key,
    required this.child,
    this.footer,
    this.padding = EdgeInsets.zero,
  });

  /// Scrolling content.
  final Widget child;

  /// Pinned under it. Null draws the shadow against the bottom edge instead,
  /// for a panel whose content simply runs out of room.
  final Widget? footer;

  final EdgeInsets padding;

  @override
  State<ZebuScrollableBody> createState() => _ZebuScrollableBodyState();
}

class _ZebuScrollableBodyState extends State<ZebuScrollableBody> {
  final _scroll = ScrollController();
  bool _more = false;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_sync);
    // Metrics do not exist until the first layout, and a form that opens
    // already overflowing has to shadow immediately, not on first scroll.
    WidgetsBinding.instance.addPostFrameCallback((_) => _sync());
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _sync() {
    if (!_scroll.hasClients) return;
    final p = _scroll.position;
    // A pixel of slack: `maxScrollExtent` and `pixels` can land a hair apart
    // at the very bottom, which flickered the shadow against the end stop.
    final more = p.maxScrollExtent - p.pixels > 1;
    if (more != _more) setState(() => _more = more);
  }

  @override
  Widget build(BuildContext context) {
    final t = ZebuTheme.of(context);

    final scroller = NotificationListener<ScrollMetricsNotification>(
      // Fires when the *content* resizes rather than when it moves — adding
      // four attachments can make a body scrollable without anyone scrolling.
      onNotification: (_) {
        WidgetsBinding.instance.addPostFrameCallback((_) => _sync());
        return false;
      },
      child: SingleChildScrollView(
        controller: _scroll,
        padding: widget.padding,
        child: widget.child,
      ),
    );

    final shadow = AnimatedContainer(
      duration: const Duration(milliseconds: 150),
      decoration: BoxDecoration(
        // Opaque: the shadow is cast *onto* the footer, so anything scrolling
        // under it has to be covered rather than tinted.
        color: t.bgElevated,
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF101828).withValues(alpha: _more ? 0.10 : 0),
            blurRadius: 10,
            offset: const Offset(0, -3),
          ),
        ],
      ),
      child: widget.footer,
    );

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Flexible(child: scroller),
        shadow,
      ],
    );
  }
}
