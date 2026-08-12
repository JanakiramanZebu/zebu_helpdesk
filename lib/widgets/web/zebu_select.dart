import 'package:flutter/material.dart';

import '../../res/zebu_spacing.dart';
import '../../res/zebu_text_styles.dart';
import '../../res/zebu_theme.dart';

/// The box that opens a dropdown — not the menu itself.
///
/// Deliberately the same shape as a text input: white fill, hairline border,
/// accent border while active. A select and a field are both "a place where a
/// value goes", so they read as one family and differ only by the chevron.
///
/// This exists because the app had three of these — the filter panel's, the
/// create-ticket form's, and the detail panel's — which had already drifted
/// apart on fill, radius, height and hover behaviour.
///
/// [onTap] is awaited, so the open state is managed here rather than by every
/// caller: the border turns accent and the chevron flips for exactly as long
/// as the menu is up.
class ZebuSelect extends StatefulWidget {
  const ZebuSelect({
    super.key,
    required this.label,
    required this.onTap,
    this.leadingIcon,
    this.trailingIcon,
    this.isPlaceholder = false,
    this.hasError = false,
    this.enabled = true,
    this.onClear,
    this.height = 40,
  });

  /// The chosen value, or the placeholder when nothing is set.
  final String label;

  /// Opens the menu. Receives the box's own context so the caller can anchor
  /// an overlay directly beneath it.
  final Future<void> Function(BuildContext anchor) onTap;

  final IconData? leadingIcon;

  /// Replaces the chevron — for a select whose action is "add another"
  /// rather than "choose one".
  final IconData? trailingIcon;

  /// Renders [label] in the muted placeholder tone.
  final bool isPlaceholder;

  final bool hasError;
  final bool enabled;

  /// Shows a small clear button before the chevron when a value is set.
  final VoidCallback? onClear;

  final double height;

  @override
  State<ZebuSelect> createState() => _ZebuSelectState();
}

class _ZebuSelectState extends State<ZebuSelect> {
  bool _hover = false;
  bool _open = false;

  Future<void> _handleTap(BuildContext anchor) async {
    if (!widget.enabled || _open) return;
    setState(() => _open = true);
    try {
      await widget.onTap(anchor);
    } finally {
      if (mounted) setState(() => _open = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = ZebuTheme.of(context);
    final on = widget.enabled;

    // Accent border at rest, not just while open — trying the scalper
    // treatment, where the outline is what marks a box as interactive rather
    // than a field you type into. Hover deepens it; disabled falls back to a
    // neutral hairline so an inert control doesn't claim the brand colour.
    //
    // Revert to `_open ? t.accent : t.borderStrong` for the input-matching
    // version, where blue means "this one is open".
    final border = widget.hasError
        ? t.danger
        : !on
        ? t.borderStrong
        : (_hover || _open ? t.accentHover : t.accent);

    return Builder(
      builder: (anchor) => MouseRegion(
        cursor: on ? SystemMouseCursors.click : SystemMouseCursors.basic,
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => _handleTap(anchor),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            height: widget.height,
            padding: const EdgeInsets.symmetric(horizontal: 11),
            decoration: BoxDecoration(
              color: on ? t.bgElevated : t.bgTertiary,
              border: Border.all(color: border, width: 1),
              borderRadius: BorderRadius.circular(ZebuRadius.rSm),
            ),
            child: Row(
              children: [
                if (widget.leadingIcon != null) ...[
                  Icon(widget.leadingIcon, size: 16, color: t.iconMuted),
                  const SizedBox(width: ZebuSpacing.s2),
                ],
                Expanded(
                  child: Text(
                    widget.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: ZebuTextStyles.body(
                      context,
                      color: widget.isPlaceholder || !on
                          ? t.textSlateMuted
                          : t.textPrimary,
                      fontWeight: ZebuFonts.medium,
                    ),
                  ),
                ),
                if (widget.onClear != null && !widget.isPlaceholder) ...[
                  _ClearBtn(onTap: widget.onClear!),
                  const SizedBox(width: 2),
                ],
                const SizedBox(width: 6),
                // The chevron turns rather than swapping glyphs — same
                // control, now pointing at the menu it opened.
                AnimatedRotation(
                  duration: const Duration(milliseconds: 140),
                  turns: _open && widget.trailingIcon == null ? 0.5 : 0,
                  child: Icon(
                    widget.trailingIcon ?? Icons.keyboard_arrow_down,
                    size: 20,
                    color: _open ? t.accent : t.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ClearBtn extends StatefulWidget {
  const _ClearBtn({required this.onTap});
  final VoidCallback onTap;

  @override
  State<_ClearBtn> createState() => _ClearBtnState();
}

class _ClearBtnState extends State<_ClearBtn> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final t = ZebuTheme.of(context);
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        // Stops the clear from also opening the menu it sits inside.
        onTap: widget.onTap,
        child: Container(
          width: 20,
          height: 20,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: _hover ? t.bgHover : t.bgHover.withValues(alpha: 0),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Icon(Icons.close, size: 14, color: t.textSlateMuted),
        ),
      ),
    );
  }
}
