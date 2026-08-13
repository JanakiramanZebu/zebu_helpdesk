import 'package:flutter/material.dart';

import '../../res/zebu_text_styles.dart';
import '../../res/zebu_theme.dart';
import 'anchored_popover.dart';

/// A text-only action: a label that tints and grows a soft pill under the
/// pointer, with no border, fill or elevation at rest.
///
/// Written for the date picker's footer — Apply and Clear — and pulled out
/// here because the pair is the app's answer to "an action that sits at the
/// end of a surface without competing with the content above it". A filled
/// button in that slot draws more of the eye than the thing being confirmed.
///
/// Use [ZebuActionTone.primary] to commit, [ZebuActionTone.danger] to destroy
/// and [ZebuActionTone.muted] to dismiss. The tone carries the meaning; a
/// destructive action never needs the word "permanently" if it is already red.
///
/// A null [onTap] greys the label and stops the pointer — a disabled action
/// says "not yet" more quietly than an error would, which is why Apply is
/// simply inert until a day is picked.
enum ZebuActionTone {
  /// Accent. Commits — Apply, Save, Add.
  primary,

  /// The pinned red pair. Destroys or unsets — Clear, Remove, Delete.
  danger,

  /// Secondary ink. Steps back — Cancel, Not now.
  muted,
}

class ZebuTextAction extends StatefulWidget {
  const ZebuTextAction({
    super.key,
    required this.label,
    required this.onTap,
    this.tone = ZebuActionTone.primary,
    this.fontSize = 12.5,
  });

  final String label;

  /// Null disables the action: greyed, and the pointer stays an arrow.
  final VoidCallback? onTap;

  final ZebuActionTone tone;

  /// 12.5 is the footer size the picker uses. Raise it where the action sits
  /// on its own rather than beside a control.
  final double fontSize;

  @override
  State<ZebuTextAction> createState() => _ZebuTextActionState();
}

class _ZebuTextActionState extends State<ZebuTextAction> {
  bool _hover = false;

  /// Tones come from the popover palette so an action dropped into a menu, a
  /// picker or a dialog footer cannot drift from the surface around it.
  (Color ink, Color fill) _tones(ZebuTheme t) => switch (widget.tone) {
    ZebuActionTone.primary => (t.accent, zebuPopoverHoverBg(t)),
    ZebuActionTone.danger => (zebuPopoverDanger(t), zebuPopoverDangerBg(t)),
    ZebuActionTone.muted => (zebuPopoverInkMuted(t), zebuPopoverHoverBg(t)),
  };

  @override
  Widget build(BuildContext context) {
    final t = ZebuTheme.of(context);
    final (ink, fill) = _tones(t);
    final enabled = widget.onTap != null;

    return MouseRegion(
      cursor: enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 80),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            // Idle is the same fill at zero alpha, never `Colors.transparent`
            // — that is transparent *black*, and a tinted pill lerping from it
            // washes through grey on the way in.
            color: _hover && enabled ? fill : fill.withValues(alpha: 0),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Text(
            widget.label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: ZebuTextStyles.small(
              context,
              fontWeight: ZebuFonts.semiBold,
              color: enabled ? ink : ink.withValues(alpha: 0.38),
            ).copyWith(fontSize: widget.fontSize),
          ),
        ),
      ),
    );
  }
}
