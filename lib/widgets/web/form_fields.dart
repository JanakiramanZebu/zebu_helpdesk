import 'package:flutter/material.dart';

import '../../res/zebu_spacing.dart';
import '../../res/zebu_text_styles.dart';
import '../../res/zebu_theme.dart';
import 'zebu_select.dart';

/// The form furniture the create dialogs share: section eyebrow, field label,
/// text input, select.
///
/// These lived privately in `create_ticket_screen_web.dart` and again, copied,
/// in `create_task_screen_web.dart`. The copies drifted exactly as you would
/// expect — the ticket dialog's labels moved to `body`/medium with an 8 px
/// gap, the task dialog's stayed on `small`/semiBold with 6, and the task
/// file's comment still claimed the two matched. One definition is the only
/// thing that actually keeps them in step.
///
/// The new-ticket dialog is the reference: it was reviewed field by field, so
/// where the two disagreed its version won.

/// Uppercase eyebrow above a group of fields.
class ZebuSectionTitle extends StatelessWidget {
  const ZebuSectionTitle(this.label, {super.key, this.hint, this.trailing});

  final String label;

  /// Sits beside [label] in the muted tone, the same relationship
  /// `ZebuPropertyGrid` draws between "PROPERTIES" and "all optional". Saying
  /// "optional" once up here lets the fields below stop qualifying themselves.
  final String? hint;

  /// An action for the whole section, at the far end of the heading row.
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final t = ZebuTheme.of(context);
    return Row(
      children: [
        Text(label.toUpperCase(), style: ZebuTextStyles.eyebrow(context)),
        if (hint != null) ...[
          const SizedBox(width: ZebuSpacing.s2),
          Text(
            hint!,
            style: ZebuTextStyles.small(context, color: t.textSlateMuted),
          ),
        ],
        if (trailing != null) ...[const Spacer(), trailing!],
      ],
    );
  }
}

/// Label above a control, with an optional inline error beneath it.
class ZebuLabeledField extends StatelessWidget {
  const ZebuLabeledField({
    super.key,
    required this.label,
    required this.child,
    this.error,
    this.trailing,
  });

  final String label;
  final Widget child;
  final String? error;

  /// An action that acts on this field, at the far end of the label row.
  /// Keeps a helper next to the thing it helps with, instead of floating as a
  /// sibling of the field where it reads as another field.
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final t = ZebuTheme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 12 px slate, 8 px above the control, and no required asterisk. The
        // asterisk marked fields before anyone had done anything wrong, and
        // submit validation names the missing field far more precisely, at the
        // moment it actually matters.
        Row(
          children: [
            Text(
              label,
              style: ZebuTextStyles.body(
                context,
                color: t.textSlate,
                fontWeight: ZebuFonts.regular,
              ),
            ),
            if (trailing != null) ...[const Spacer(), trailing!],
          ],
        ),
        const SizedBox(height: 8),
        child,
        if (error != null) ...[
          const SizedBox(height: 6),
          Row(
            children: [
              Icon(Icons.error_outline_rounded, size: 12, color: t.danger),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  error!,
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

/// Single- or multi-line text field for a create form.
/// Height of a single-line form control — input and select alike.
///
/// Named rather than inlined so a test can assert the two match without
/// pinning the number twice.
const double kZebuFieldHeight = 40;

class ZebuFormInput extends StatelessWidget {
  const ZebuFormInput({
    super.key,
    required this.controller,
    required this.hint,
    this.minLines,
    this.maxLines = 1,
    this.onChanged,
    this.hasError = false,
  });

  final TextEditingController controller;
  final String hint;
  final int? minLines;
  final int maxLines;

  /// Fired on every keystroke. Used to drop this field's validation error the
  /// moment it is being fixed — a red border that persists while you type the
  /// correction is worse than no validation at all.
  final ValueChanged<String>? onChanged;
  final bool hasError;

  @override
  Widget build(BuildContext context) {
    final t = ZebuTheme.of(context);
    // Accent border at rest, matching [ZebuSelect] — a field and a select are
    // the same kind of thing, so a blue-outlined picker beside a grey input
    // would say they behave differently when they don't. Focus deepens the
    // colour rather than introducing it.
    OutlineInputBorder outline(Color c, [double w = 1]) => OutlineInputBorder(
      borderRadius: BorderRadius.circular(ZebuRadius.rSm),
      borderSide: BorderSide(color: c, width: w),
    );
    final border = outline(hasError ? t.danger : t.accent);
    final focusedBorder = outline(hasError ? t.danger : t.accentHover, 1.4);

    // A single-line input is pinned to [kZebuFieldHeight] and centres its text
    // in it, so it stands exactly as tall as the select beside it whatever the
    // font does. Left to padding it measured 45 against the select's 40 — a
    // step you see immediately on Title / Department and Requester /
    // Collaborators, where the two share a row.
    final fixedHeight = maxLines == 1 && (minLines ?? 1) == 1;

    final field = TextField(
      controller: controller,
      onChanged: onChanged,
      minLines: minLines,
      maxLines: maxLines,
      style: ZebuTextStyles.body(context),
      decoration: InputDecoration(
        filled: true,
        fillColor: t.bgElevated,
        hoverColor: Colors.transparent,
        border: border,
        enabledBorder: border,
        focusedBorder: focusedBorder,
        isDense: true,
        contentPadding: EdgeInsets.symmetric(
          horizontal: ZebuSpacing.s3,
          // Only a box that has to grow with its content keeps a
          // padding-derived height.
          vertical: fixedHeight ? 0 : 12,
        ),
        hintText: hint,
        hintStyle: ZebuTextStyles.body(context, color: t.textSlateMuted),
      ),
    );

    // A `SizedBox`, not `InputDecoration.constraints`. The decoration's own
    // constraints measured 40 in a widget test and still painted a ~23 px box
    // in the app, as though the constraint were not there. An outer tight box
    // is not something the decorator can decline; it fills it and centres the
    // text inside.
    return fixedHeight
        ? SizedBox(height: kZebuFieldHeight, child: field)
        : field;
  }
}

/// Thin adapter over the shared [ZebuSelect] for a form row.
///
/// Both dialogs used to hand-roll their own select — fill, border, hover and
/// chevron each — and both had already drifted to a grey hairline at rest
/// where every other select in the app carries the accent outline.
class ZebuSelectField extends StatelessWidget {
  const ZebuSelectField({
    super.key,
    required this.onTap,
    this.icon,
    this.value,
    this.placeholder,
    this.trailingIcon,
    this.hasError = false,
  });

  final VoidCallback onTap;
  final IconData? icon;
  final String? value;
  final String? placeholder;
  final IconData? trailingIcon;
  final bool hasError;

  @override
  Widget build(BuildContext context) {
    final has = value != null && value!.isNotEmpty;
    return ZebuSelect(
      label: has ? value! : (placeholder ?? 'Select…'),
      isPlaceholder: !has,
      leadingIcon: icon,
      trailingIcon: trailingIcon,
      hasError: hasError,
      onTap: (_) async => onTap(),
    );
  }
}
