import 'package:flutter/material.dart';

import '../../res/zebu_theme.dart';
import '../../res/zebu_spacing.dart';

/// Card-styled wrapper for the full-width tables used across the web list
/// screens (Tickets, Tasks, Users, Organizations, Canned, FAQ, Queues,
/// Notifications). Insets the table from the page edges, wraps it in a
/// hairline-bordered rounded surface, and clips inner content so the header
/// strip's top corners follow the outer radius.
///
/// Every list screen shares the same `PageHeader + SegmentedTabBar +
/// Expanded(table)` layout, and every table sits directly against the
/// content edges by default — this shell is what makes the table read as a
/// discrete card sitting on the warm-paper page bg.
class ListTableShell extends StatelessWidget {
  const ListTableShell({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.fromLTRB(
      ZebuSpacing.s6,
      ZebuSpacing.s4,
      ZebuSpacing.s6,
      ZebuSpacing.s6,
    ),
  });

  /// Table body — typically the `LayoutBuilder → Scrollbar →
  /// SingleChildScrollView → Column [Header + Rows]` tree each list screen
  /// already builds.
  final Widget child;

  /// Inset from the page edges. L/R/bottom = 24 px (matches the shared
  /// horizontal rhythm the [PageHeader] uses, so the card's edges line up
  /// with the page title). Top = 16 px so the card sits with a small gap
  /// under the SegmentedTabBar rather than flush against it.
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final t = ZebuTheme.of(context);
    // Square corners, and `borderDefault` rather than `borderSubtle`: the
    // page, the card, and the rows are all white now, so the subtle hairline
    // was too close to the background to register.
    //
    // The border is painted as a **foreground** decoration. `DecoratedBox`
    // draws its decoration behind the child, and the grid fills the whole box
    // with an opaque header strip and body — which buried the border
    // entirely. Painting it in front puts the outline back on top of the
    // content, the same trick the shell's workspace card uses.
    return Padding(
      padding: padding,
      child: DecoratedBox(
        position: DecorationPosition.foreground,
        decoration: BoxDecoration(
          border: Border.all(color: t.borderDefault, width: 1),
        ),
        child: ColoredBox(
          color: t.bgElevated,
          child: ClipRect(child: child),
        ),
      ),
    );
  }
}
