import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../res/zebu_spacing.dart';
import '../../res/zebu_text_styles.dart';
import '../../res/zebu_theme.dart';

/// Modal shell for the app's form dialogs — header, scrolling body, footer.
///
/// Built from the "add subtask" reference: a titled header with a subtitle
/// naming the record being acted on, a body of labelled fields, and a footer
/// that separates a left-hand option from the right-hand commit pair. The
/// shell is shared so a second dialog can't invent its own padding, scrim, or
/// button sizes — the pattern this codebase keeps re-learning.
///
/// Keyboard: `Esc` dismisses, `Cmd`/`Ctrl + Enter` submits. A form dialog an
/// agent opens dozens of times a day has to be closable without the mouse.

/// Scrim behind the dialog — a blue-black at 45 %, not neutral black, so the
/// page beneath reads as dimmed rather than dirty.
const _kScrim = Color(0x73101828);

/// Pressed/hover step for a destructive commit — no palette equivalent, and
/// the danger tone has no hover pair of its own.
const _kDangerHover = Color(0xFF912018);

/// Opens [child] as a modal, with the shell's fade + settle transition.
Future<T?> showZebuDialog<T>(
  BuildContext context, {
  required Widget child,
  String barrierLabel = 'Dialog',
  bool dismissible = true,
}) {
  return showGeneralDialog<T>(
    context: context,
    barrierDismissible: dismissible,
    barrierLabel: barrierLabel,
    barrierColor: _kScrim,
    transitionDuration: const Duration(milliseconds: 200),
    pageBuilder: (_, _, _) => const SizedBox.shrink(),
    transitionBuilder: (context, anim, _, _) {
      final curved = CurvedAnimation(parent: anim, curve: Curves.easeOutCubic);
      return FadeTransition(
        opacity: curved,
        // Settles from 95 % rather than growing from nothing: the dialog
        // should read as arriving, not as being inflated.
        child: ScaleTransition(
          scale: Tween<double>(begin: 0.95, end: 1).animate(curved),
          child: child,
        ),
      );
    },
  );
}

/// The dialog card itself.
class ZebuDialogShell extends StatelessWidget {
  const ZebuDialogShell({
    super.key,
    required this.title,
    required this.body,
    required this.actions,
    this.subtitle,
    this.onDismiss,
    this.onSubmit,
    this.maxWidth = 470,
  });

  final String title;

  /// Names the record being acted on — "On #4263 · Square off all request".
  final Widget? subtitle;
  final Widget body;

  /// Right-hand commit actions in a bottom footer. Leave empty to omit the
  /// footer entirely — a confirm puts its single full-width button inside the
  /// body instead, directly under the question it answers.
  final List<Widget> actions;

  final VoidCallback? onDismiss;
  final VoidCallback? onSubmit;
  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    final t = ZebuTheme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(ZebuSpacing.s6),
        child: CallbackShortcuts(
          bindings: {
            if (onDismiss != null)
              const SingleActivator(LogicalKeyboardKey.escape): onDismiss!,
            if (onSubmit != null) ...{
              const SingleActivator(LogicalKeyboardKey.enter, meta: true):
                  onSubmit!,
              const SingleActivator(LogicalKeyboardKey.enter, control: true):
                  onSubmit!,
            },
          },
          child: FocusScope(
            autofocus: true,
            child: Material(
              color: Colors.transparent,
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: maxWidth),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: t.bgElevated,
                    borderRadius: BorderRadius.circular(ZebuRadius.rSm),
                    boxShadow: const [
                      BoxShadow(
                        color: Color(0x33101828),
                        blurRadius: 40,
                        offset: Offset(0, 18),
                      ),
                    ],
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(ZebuRadius.rSm),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _header(context, t),
                        Flexible(
                          child: SingleChildScrollView(
                            padding: const EdgeInsets.all(ZebuSpacing.s5),
                            child: body,
                          ),
                        ),
                        if (actions.isNotEmpty) _footer(context, t),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _header(BuildContext context, ZebuTheme t) => Container(
    padding: const EdgeInsets.fromLTRB(
      ZebuSpacing.s4,
      ZebuSpacing.s2,
      ZebuSpacing.s2,
      ZebuSpacing.s2,
    ),
    decoration: BoxDecoration(
      border: Border(bottom: BorderSide(color: t.borderSubtle, width: 1)),
    ),
    child: Row(
      // Top-aligned only when there is a subtitle to sit under the title.
      // Without one the close button is the taller child, so `start` pinned
      // the title up and dropped the whole height difference into a gap
      // beneath it.
      crossAxisAlignment: subtitle == null
          ? CrossAxisAlignment.center
          : CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                title,
                style: ZebuTextStyles.sectionTitle(
                  context,
                  color: t.textPrimary,
                  fontWeight: ZebuFonts.bold,
                ),
              ),
              if (subtitle != null) ...[
                const SizedBox(height: 3),
                DefaultTextStyle.merge(
                  style: ZebuTextStyles.small(context, color: t.textSlateMuted),
                  child: subtitle!,
                ),
              ],
            ],
          ),
        ),
        const SizedBox(width: ZebuSpacing.s3),
        if (onDismiss != null) _DialogCloseBtn(onTap: onDismiss!),
      ],
    ),
  );

  Widget _footer(BuildContext context, ZebuTheme t) => Container(
    padding: const EdgeInsets.symmetric(
      horizontal: ZebuSpacing.s5,
      vertical: ZebuSpacing.s3,
    ),
    decoration: BoxDecoration(
      // Hairline only. The tint existed to balance a left-hand checkbox;
      // with a single button it read as a leftover grey band.
      // border: Border(top: BorderSide(color: t.borderSubtle, width: 1)),
    ),
    child: Row(
      children: [
        const Spacer(),
        for (final a in actions) ...[const SizedBox(width: 9), a],
      ],
    ),
  );
}

class _DialogCloseBtn extends StatelessWidget {
  const _DialogCloseBtn({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = ZebuTheme.of(context);
    // Always filled, no hover state. The tile is what makes the glyph read as
    // a button rather than a stray mark, so it has nothing to gain by hiding
    // until the pointer finds it — and in a modal the close is the one
    // control an agent should never have to hunt for.
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Container(
          width: 30,
          height: 30,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: t.bgHover,
            borderRadius: BorderRadius.circular(ZebuRadius.rSm),
          ),
          child: Icon(Icons.close, size: 17, color: t.textSlateMuted),
        ),
      ),
    );
  }
}

/// Labelled field wrapper — label, optional marker, control, error line.
class ZebuDialogField extends StatelessWidget {
  const ZebuDialogField({
    super.key,
    required this.label,
    required this.child,
    this.errorText,
  });

  final String label;
  final Widget child;
  final String? errorText;

  @override
  Widget build(BuildContext context) {
    final t = ZebuTheme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          style: ZebuTextStyles.body(
            context,
            color: t.textSlate,
            fontWeight: ZebuFonts.medium,
          ),
        ),
        const SizedBox(height: 8),
        child,
        if (errorText != null) ...[
          const SizedBox(height: 6),
          Row(
            children: [
              Icon(Icons.error_outline_rounded, size: 16, color: t.danger),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  errorText!,
                  style: ZebuTextStyles.eyebrow(
                    context,
                    color: t.danger,
                    fontWeight: ZebuFonts.medium,
                  ),
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }
}

/// Text input with a focus ring, sized for a dialog form.
class ZebuDialogInput extends StatefulWidget {
  const ZebuDialogInput({
    super.key,
    required this.controller,
    this.hint,
    this.focusNode,
    this.enabled = true,
    this.hasError = false,
    this.minLines,
    this.maxLines = 1,
    this.keyboardType,
    this.inputFormatters,
    this.onChanged,
    this.onSubmitted,
  });

  final TextEditingController controller;

  /// Placeholder. Usually omitted — the label already names the field, and a
  /// worked example inside the box reads as content on every open after the
  /// first.
  final String? hint;
  final FocusNode? focusNode;
  final bool enabled;
  final bool hasError;
  final int? minLines;
  final int? maxLines;
  final TextInputType? keyboardType;
  final List<TextInputFormatter>? inputFormatters;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;

  @override
  State<ZebuDialogInput> createState() => _ZebuDialogInputState();
}

class _ZebuDialogInputState extends State<ZebuDialogInput> {
  late final FocusNode _node = widget.focusNode ?? FocusNode();
  bool _focused = false;
  bool _hover = false;

  @override
  void initState() {
    super.initState();
    _node.addListener(_onFocus);
  }

  void _onFocus() {
    if (_node.hasFocus != _focused) setState(() => _focused = _node.hasFocus);
  }

  @override
  void dispose() {
    _node.removeListener(_onFocus);
    if (widget.focusNode == null) _node.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = ZebuTheme.of(context);
    final active = widget.hasError || _focused;
    final ring = widget.hasError ? t.danger : t.accent;
    final single = widget.maxLines == 1;

    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        padding: EdgeInsets.symmetric(
          horizontal: 11,
          vertical: single ? 9 : 10,
        ),
        decoration: BoxDecoration(
          color: widget.enabled ? t.bgElevated : t.bgTertiary,
          borderRadius: BorderRadius.circular(ZebuRadius.rSm),
          // Accent border at rest, matching [ZebuSelect]: a field and a select
          // are the same kind of thing and should not disagree about it.
          // Hover and focus deepen the same colour rather than introducing
          // it. No glow ring — the reference's 3 px spread outside a 1.5 px
          // border read as two borders, not one focused one.
          border: Border.all(
            color: !widget.enabled
                ? t.borderStrong
                : widget.hasError
                ? ring
                : (active || _hover ? t.accentHover : t.accent),
            width: 1,
          ),
        ),
        child: TextField(
          controller: widget.controller,
          focusNode: _node,
          enabled: widget.enabled,
          minLines: widget.minLines,
          maxLines: widget.maxLines,
          cursorColor: t.accent,
          cursorWidth: 1.5,
          keyboardType: widget.keyboardType,
          inputFormatters: widget.inputFormatters,
          style: ZebuTextStyles.body(context, color: t.textPrimary),
          textInputAction: single
              ? TextInputAction.done
              : TextInputAction.newline,
          onChanged: widget.onChanged,
          onSubmitted: widget.onSubmitted,
          decoration: InputDecoration(
            isDense: true,
            // The global `inputDecorationTheme` paints a filled, outlined field
            // — right for full-page forms, wrong here because the container
            // above already owns the border. `border` alone does not disable
            // it: `enabledBorder` / `focusedBorder` from the theme take
            // precedence, so Flutter drew its rounded outline *inside* ours and
            // the field came out double-ringed. All six slots plus `filled`
            // have to be cleared.
            border: InputBorder.none,
            enabledBorder: InputBorder.none,
            focusedBorder: InputBorder.none,
            disabledBorder: InputBorder.none,
            errorBorder: InputBorder.none,
            focusedErrorBorder: InputBorder.none,
            filled: false,
            fillColor: Colors.transparent,
            contentPadding: EdgeInsets.zero,
            hintText: widget.hint,
            hintStyle: widget.hint == null
                ? null
                : ZebuTextStyles.body(context, color: t.textSlateMuted),
          ),
        ),
      ),
    );
  }
}

/// Filled commit button. Shows a spinner and an alternate label while busy.
class ZebuDialogPrimaryBtn extends StatefulWidget {
  const ZebuDialogPrimaryBtn({
    super.key,
    required this.label,
    required this.onTap,
    this.busy = false,
    this.busyLabel,
    this.destructive = false,
    this.fullWidth = false,
  });

  final String label;
  final VoidCallback onTap;
  final bool busy;
  final String? busyLabel;

  /// Fills with [ZebuTheme.danger] instead of the accent. For commits that
  /// destroy something — the colour is the last warning before it happens.
  final bool destructive;

  /// Stretches to the available width, for a dialog whose only action sits
  /// in the body rather than a footer.
  final bool fullWidth;

  @override
  State<ZebuDialogPrimaryBtn> createState() => _ZebuDialogPrimaryBtnState();
}

class _ZebuDialogPrimaryBtnState extends State<ZebuDialogPrimaryBtn> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final t = ZebuTheme.of(context);
    final busy = widget.busy;
    return MouseRegion(
      cursor: busy ? SystemMouseCursors.progress : SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: busy ? null : widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          height: 38,
          // Floor width so a short label still reads as a button — "Add"
          // shrink-wraps to about 60 px, which looks like a chip.
          // constraints: const BoxConstraints(minWidth: ),
          padding: const EdgeInsets.symmetric(horizontal: ZebuSpacing.s4),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: widget.destructive
                ? (busy || _hover ? _kDangerHover : t.danger)
                : (busy || _hover ? t.accentHover : t.accent),
            borderRadius: BorderRadius.circular(ZebuRadius.rXs),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (busy) ...[
                const SizedBox(
                  width: 12,
                  height: 12,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation(Colors.white),
                    backgroundColor: Color(0x59FFFFFF),
                  ),
                ),
                const SizedBox(width: ZebuSpacing.s2),
              ],
              Text(
                busy ? (widget.busyLabel ?? widget.label) : widget.label,
                // Medium, not bold: at 14 px on a saturated fill, w600 reads
                // as shouting and w400 reads as text that happens to sit on a
                // blue block. w500 is the weight the Actions button uses.
                style: ZebuTextStyles.body(
                  context,
                  color: Colors.white,
                  fontWeight: ZebuFonts.medium,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
