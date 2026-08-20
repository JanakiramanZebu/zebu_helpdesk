import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

/// Drops keyboard focus on any touch that lands outside the focused field.
///
/// A plain `GestureDetector` around the app can't do this: it competes in the
/// gesture arena and loses to whatever the user actually tapped, so tapping a
/// list row, a tab or a button left the keyboard up. A [Listener] sits outside
/// the arena and sees every pointer down, whatever ends up handling it.
///
/// Wraps the whole app (see `ZebuHelpdeskApp`), so every screen behaves the
/// same and no field has to opt in.
class KeyboardDismisser extends StatefulWidget {
  const KeyboardDismisser({super.key, required this.child});

  final Widget child;

  /// Drops focus (and the keyboard with it) if anything holds it.
  static void dismiss() {
    final focus = FocusManager.instance.primaryFocus;
    if (focus != null && focus.hasFocus) focus.unfocus();
  }

  @override
  State<KeyboardDismisser> createState() => _KeyboardDismisserState();
}

class _KeyboardDismisserState extends State<KeyboardDismisser> {
  /// How far outside the editable's own box a touch still counts as "on the
  /// field" — enough to cover chrome drawn beside it, like the search pill's
  /// inline clear button, so clearing a search doesn't close the keyboard.
  static const double _fieldSlack = 24;

  void _onPointerDown(PointerDownEvent event) {
    final focus = FocusManager.instance.primaryFocus;
    if (focus == null || !focus.hasFocus) return;
    if (_hitsTextField(event.position) || _nearFocusedField(focus, event)) {
      return;
    }
    focus.unfocus();
  }

  /// Whether the touch landed on something belonging to a text field — the
  /// field itself, another one, or its selection handles and toolbar. Flutter
  /// marks all of those with a [TextFieldTapRegion] (group [EditableText]), so
  /// the hit-test path answers this without guessing at coordinates. Without
  /// it, tapping "Paste" on the selection toolbar would drop the focus the
  /// paste needs.
  bool _hitsTextField(Offset globalPosition) {
    final box = context.findRenderObject();
    if (box is! RenderBox || !box.hasSize) return false;
    final result = BoxHitTestResult();
    box.hitTest(result, position: box.globalToLocal(globalPosition));
    for (final entry in result.path) {
      final target = entry.target;
      if (target is RenderTapRegion && target.groupId == EditableText) {
        return true;
      }
    }
    return false;
  }

  /// Fallback for chrome that sits beside the field without being part of its
  /// tap region: anything within [_fieldSlack] of the focused editable.
  bool _nearFocusedField(FocusNode focus, PointerDownEvent event) {
    final box = focus.context?.findRenderObject();
    if (box is! RenderBox || !box.hasSize || !box.attached) return false;
    final rect = box.localToGlobal(Offset.zero) & box.size;
    return rect.inflate(_fieldSlack).contains(event.position);
  }

  @override
  Widget build(BuildContext context) =>
      Listener(onPointerDown: _onPointerDown, child: widget.child);
}

/// Drops keyboard focus whenever the route stack changes, so a field focused on
/// one page can't carry the keyboard into the next — including navigation the
/// user didn't tap for (a notification tap, an auth redirect, a deep link).
class KeyboardDismissObserver extends NavigatorObserver {
  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      KeyboardDismisser.dismiss();

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      KeyboardDismisser.dismiss();

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) =>
      KeyboardDismisser.dismiss();

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      KeyboardDismisser.dismiss();
}
