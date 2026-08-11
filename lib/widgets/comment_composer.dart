import 'dart:async';

import 'package:dio/dio.dart' show MultipartFile;
import 'package:file_picker/file_picker.dart';
import 'package:fleather/fleather.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:parchment/codecs.dart';

import '../res/zebu_theme.dart';
import '../res/zebu_spacing.dart';
import '../res/zebu_text_styles.dart';

const _kFlatRadius = 5.0;

/// Reply / Note scope. `replyAndNote` shows the mode pills and starts on
/// Reply; `noteOnly` hides the pills and always submits as a note.
enum ComposerScope { replyAndNote, noteOnly }

/// A rich-text comment composer shared by every web slide-over panel
/// (ticket, task, user notes).
///
/// Layout is a single bordered box containing:
///   1. The [FleatherEditor] (auto-grow, min 56 px, max 260 px).
///   2. A row of picked-file chips (if any) above the toolbar.
///   3. A compact bottom toolbar in the same border: bold / italic /
///      underline / strike / lists / link on the left, emoji + attach on
///      the right, and the send button pinned rightmost.
///
/// The Reply / Note pills sit *outside* the border (above), so switching
/// modes doesn't repaint the whole box.
///
/// The consumer supplies [onSend] which receives the composed HTML body
/// plus the picked files as [MultipartFile]s. Returning `true` clears the
/// editor + attachments; returning `false` keeps them so the user can
/// retry after fixing an error.
class CommentComposer extends StatefulWidget {
  const CommentComposer({
    super.key,
    required this.onSend,
    this.scope = ComposerScope.replyAndNote,
    this.allowAttachments = true,
    this.disabled = false,
    this.replyHint = 'Write a reply…',
    this.noteHint = 'Add an internal note…',
    this.replyLabel = 'Send reply',
    this.noteLabel = 'Save note',
  });

  final Future<bool> Function({
    required bool asNote,
    required String bodyHtml,
    required List<MultipartFile> files,
  })
  onSend;

  final ComposerScope scope;
  final bool allowAttachments;
  final bool disabled;
  final String replyHint;
  final String noteHint;
  final String replyLabel;
  final String noteLabel;

  @override
  State<CommentComposer> createState() => _CommentComposerState();
}

class _CommentComposerState extends State<CommentComposer> {
  final FleatherController _controller = FleatherController();
  final FocusNode _focus = FocusNode();
  final List<PlatformFile> _files = [];
  bool _asNote = false;
  bool _sending = false;

  @override
  void initState() {
    super.initState();
    _asNote = widget.scope == ComposerScope.noteOnly;
    _controller.addListener(_onChange);
    _focus.addListener(_onChange);
  }

  @override
  void dispose() {
    _controller.removeListener(_onChange);
    _focus.removeListener(_onChange);
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _onChange() {
    if (mounted) setState(() {});
  }

  bool get _isEmpty => _controller.document.toPlainText().trim().isEmpty;
  bool get _canSend => !_isEmpty || _files.isNotEmpty;

  void _clearDocument() {
    final len = _controller.document.length;
    if (len > 1) {
      _controller.replaceText(
        0,
        len - 1,
        '',
        selection: const TextSelection.collapsed(offset: 0),
      );
    }
  }

  /// Inserts [text] at the current selection, replacing any selected range.
  /// Used by the emoji picker.
  void _insertAtCursor(String text) {
    final sel = _controller.selection;
    final start = sel.start.clamp(0, _controller.document.length);
    final end = sel.end.clamp(start, _controller.document.length);
    _controller.replaceText(
      start,
      end - start,
      text,
      selection: TextSelection.collapsed(offset: start + text.length),
    );
    _focus.requestFocus();
  }

  Future<void> _pickFiles() async {
    final res = await FilePicker.platform.pickFiles(
      allowMultiple: true,
      withData: true,
    );
    if (res == null || !mounted) return;
    setState(() {
      for (final f in res.files) {
        if (f.bytes == null) continue;
        if (_files.any((e) => e.name == f.name)) continue;
        _files.add(f);
      }
    });
  }

  Future<void> _submit() async {
    if (!_canSend || _sending || widget.disabled) return;
    setState(() => _sending = true);
    try {
      final body = _isEmpty ? '' : parchmentHtml.encode(_controller.document);
      final files = [
        for (final f in _files)
          if (f.bytes != null)
            MultipartFile.fromBytes(f.bytes!, filename: f.name),
      ];
      final ok = await widget.onSend(
        asNote: _asNote,
        bodyHtml: body,
        files: files,
      );
      if (ok && mounted) {
        _clearDocument();
        setState(() => _files.clear());
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _openEmojiPicker(BuildContext anchor) async {
    final picked = await showEmojiPicker(anchor);
    if (picked != null) _insertAtCursor(picked);
  }

  Future<void> _openLinkDialog(BuildContext ctx) async {
    // Drop the editor's IME connection so the popover TextFields can
    // receive keystrokes. Fleather's hidden input otherwise steals focus.
    _focus.unfocus();

    // Snapshot the selection range in plain text so the popover knows
    // which slice of the document its Text field maps to.
    final sel = _controller.selection;
    final plain = _controller.document.toPlainText();
    // ParchmentDocument always ends with a trailing '\n' — cap indices
    // one short so we don't accidentally include it in the selection
    // range or overrun with substring().
    final maxTextLen = plain.isEmpty ? 0 : plain.length - 1;
    final start = sel.start.clamp(0, maxTextLen).toInt();
    final end = sel.end.clamp(start, maxTextLen).toInt();
    final initialText = plain.substring(start, end);

    // Submit-based flow: the popover only reports back on Apply. Esc /
    // outside-tap discards. That way accidental keystrokes in the picker
    // don't rewrite the document until the user explicitly commits.
    final res = await _showLinkPicker(ctx, initialText: initialText);
    if (res == null) {
      // Cancelled — leave the document untouched, restore editor focus.
      _focus.requestFocus();
      return;
    }
    final text = res.text.isEmpty ? res.url : res.text;
    final oldLen = end - start;
    _controller.replaceText(
      start,
      oldLen,
      text,
      selection: TextSelection(
        baseOffset: start,
        extentOffset: start + text.length,
      ),
    );
    _controller.formatSelection(ParchmentAttribute.link.fromString(res.url));
    _controller.updateSelection(
      TextSelection.collapsed(offset: start + text.length),
    );
    _focus.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    final t = ZebuTheme.of(context);
    // Filled Send button keeps the Mynt brand blue in both modes — the
    // dark-mode cyan accent is reserved for text/borders. Notes swap to
    // warning amber as before.
    final tone = _asNote ? t.note : t.accent;
    final showToggle = widget.scope == ComposerScope.replyAndNote;
    final hint = _asNote ? widget.noteHint : widget.replyHint;
    final sendLabel = _asNote ? widget.noteLabel : widget.replyLabel;
    final locked = widget.disabled || _sending;

    return Container(
      padding: const EdgeInsets.fromLTRB(
        ZebuSpacing.s4,
        ZebuSpacing.s3,
        ZebuSpacing.s4,
        ZebuSpacing.s4,
      ),
      decoration: BoxDecoration(
        color: t.bgElevated,
        border: Border(top: BorderSide(color: t.borderSubtle, width: 1)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (showToggle) ...[
            Align(
              alignment: Alignment.centerLeft,
              child: _ModeSegmented(
                asNote: _asNote,
                onChanged: locked ? null : (v) => setState(() => _asNote = v),
              ),
            ),
            const SizedBox(height: ZebuSpacing.s2),
          ],
          // Single bordered container — editor, chips, and toolbar all live
          // inside so the box reads as one comment "capsule".
          Container(
            decoration: BoxDecoration(
              color: t.bgElevated,
              border: Border.all(
                color: _focus.hasFocus ? tone : t.borderSubtle,
                width: _focus.hasFocus ? 1.4 : 1,
              ),
              borderRadius: BorderRadius.circular(_kFlatRadius),
            ),
            clipBehavior: Clip.antiAlias,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Editor. Wrapped in a [FleatherTheme] override so
                // consecutive paragraphs sit tight instead of Fleather's
                // default 6 px top + 10 px bottom (that gap read as
                // wasted air when each line was a short note).
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    ZebuSpacing.s3,
                    ZebuSpacing.s2,
                    ZebuSpacing.s3,
                    ZebuSpacing.s2,
                  ),
                  child: Stack(
                    children: [
                      Builder(
                        builder: (ctx) {
                          final base = FleatherThemeData.fallback(ctx);
                          // Fleather's fallback link uses `colorScheme.
                          // primaryContainer`, which resolves to a pale
                          // tint under Material 3 — links looked disabled
                          // in the composer. Override to the brand accent
                          // + underline so the styling reads the same as
                          // the rendered HTML thread bubble.
                          final tight = base.copyWith(
                            paragraph: TextBlockTheme(
                              style: base.paragraph.style,
                              spacing: const VerticalSpacing(top: 0, bottom: 2),
                            ),
                            lists: TextBlockTheme(
                              style: base.lists.style,
                              spacing: const VerticalSpacing(top: 0, bottom: 2),
                              lineSpacing: const VerticalSpacing(bottom: 0),
                            ),
                            link: base.link.copyWith(
                              color: t.accent,
                              decoration: TextDecoration.underline,
                              decorationColor: t.accent,
                            ),
                          );
                          return FleatherTheme(
                            data: tight,
                            child: FleatherEditor(
                              controller: _controller,
                              focusNode: _focus,
                              minHeight: 56,
                              maxHeight: 260,
                              readOnly: locked,
                              padding: EdgeInsets.zero,
                            ),
                          );
                        },
                      ),
                      if (_isEmpty)
                        Positioned(
                          left: 0,
                          top: 0,
                          child: IgnorePointer(
                            child: Text(
                              hint,
                              style: ZebuTextStyles.body(
                                context,
                              ).copyWith(color: t.textSecondary),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                if (_files.isNotEmpty)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.fromLTRB(
                      ZebuSpacing.s3,
                      6,
                      ZebuSpacing.s3,
                      6,
                    ),
                    decoration: BoxDecoration(
                      border: Border(
                        top: BorderSide(color: t.borderSubtle, width: 1),
                      ),
                    ),
                    child: Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        for (final f in _files)
                          _FileChip(
                            name: f.name,
                            onRemove: locked
                                ? null
                                : () => setState(() => _files.remove(f)),
                          ),
                      ],
                    ),
                  ),
                // Bottom toolbar — same border, thin separator above.
                Container(
                  padding: const EdgeInsets.fromLTRB(6, 4, 6, 4),
                  decoration: BoxDecoration(
                    // color: t.bgTertiary.withValues(alpha: 0.5),
                    // border: Border(
                    //   top: BorderSide(color: t.borderSubtle, width: 1),
                    // ),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Expanded(
                        child: _FormattingToolbar(
                          controller: _controller,
                          disabled: locked,
                          onLink: _openLinkDialog,
                        ),
                      ),
                      Builder(
                        builder: (btnCtx) => _MiniIconButton(
                          icon: Icons.emoji_emotions_outlined,
                          tooltip: 'Emoji',
                          onTap: locked ? null : () => _openEmojiPicker(btnCtx),
                        ),
                      ),
                      if (widget.allowAttachments)
                        _MiniIconButton(
                          icon: Icons.attach_file,
                          tooltip: 'Attach files',
                          onTap: locked ? null : _pickFiles,
                        ),
                      const SizedBox(width: 6),
                      _SendButton(
                        label: sendLabel,
                        tone: tone,
                        disabled: !_canSend || locked,
                        loading: _sending,
                        onTap: _submit,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Formatting toolbar — custom compact buttons wired to the FleatherController.
// Renders bold / italic / underline / strike / bullet list / numbered list /
// blockquote / link with a Wrap so it re-flows on narrow panels instead of
// overflowing horizontally.
// ---------------------------------------------------------------------------

class _FormattingToolbar extends StatelessWidget {
  const _FormattingToolbar({
    required this.controller,
    required this.disabled,
    required this.onLink,
  });
  final FleatherController controller;
  final bool disabled;

  /// Fires with the link button's own build context so the popover can
  /// anchor its overlay directly beneath the icon.
  final ValueChanged<BuildContext> onLink;

  Widget _toggle(
    IconData icon,
    ParchmentAttribute attribute, {
    String? tooltip,
  }) {
    return ToggleStyleButton(
      attribute: attribute,
      icon: icon,
      controller: controller,
      childBuilder: (context, attr, ic, isToggled, onPressed) =>
          _MiniIconButton(
            icon: ic,
            tooltip: tooltip,
            active: isToggled,
            onTap: (disabled || onPressed == null) ? null : onPressed,
          ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 2,
      runSpacing: 2,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        _toggle(Icons.format_bold, ParchmentAttribute.bold, tooltip: 'Bold'),
        _toggle(
          Icons.format_italic,
          ParchmentAttribute.italic,
          tooltip: 'Italic',
        ),
        _toggle(
          Icons.format_underline,
          ParchmentAttribute.underline,
          tooltip: 'Underline',
        ),
        _toggle(
          Icons.strikethrough_s,
          ParchmentAttribute.strikethrough,
          tooltip: 'Strikethrough',
        ),
        const _VDivider(),
        _toggle(
          Icons.format_list_bulleted,
          ParchmentAttribute.block.bulletList,
          tooltip: 'Bulleted list',
        ),
        _toggle(
          Icons.format_list_numbered,
          ParchmentAttribute.block.numberList,
          tooltip: 'Numbered list',
        ),
        _toggle(
          Icons.format_quote,
          ParchmentAttribute.block.quote,
          tooltip: 'Quote',
        ),
        const _VDivider(),
        // Wrapped in a Builder so the callback receives the button's own
        // BuildContext — the popover uses it as the overlay anchor.
        Builder(
          builder: (btnCtx) => _MiniIconButton(
            icon: Icons.link,
            tooltip: 'Insert link',
            onTap: disabled ? null : () => onLink(btnCtx),
          ),
        ),
      ],
    );
  }
}

class _VDivider extends StatelessWidget {
  const _VDivider();

  @override
  Widget build(BuildContext context) {
    final t = ZebuTheme.of(context);
    return Container(
      width: 1,
      height: 18,
      margin: const EdgeInsets.symmetric(horizontal: 4),
      color: t.borderSubtle,
    );
  }
}

// ---------------------------------------------------------------------------
// Compact icon button — 26 × 26, 15 px glyph, hover + active tints. Used
// throughout the toolbar so every button reads as the same primitive.
// ---------------------------------------------------------------------------

class _MiniIconButton extends StatefulWidget {
  const _MiniIconButton({
    required this.icon,
    required this.onTap,
    this.tooltip,
    this.active = false,
  });
  final IconData icon;
  final VoidCallback? onTap;
  final String? tooltip;
  final bool active;

  @override
  State<_MiniIconButton> createState() => _MiniIconButtonState();
}

class _MiniIconButtonState extends State<_MiniIconButton> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final t = ZebuTheme.of(context);
    final disabled = widget.onTap == null;
    final bg = widget.active
        ? t.accent.withValues(alpha: 0.14)
        : (_hover && !disabled ? t.bgHover : Colors.transparent);
    final fg = disabled
        ? t.textSecondary.withValues(alpha: 0.4)
        : widget.active
        ? t.accent
        : (_hover ? t.textPrimary : t.textSecondary);
    final child = MouseRegion(
      cursor: disabled
          ? SystemMouseCursors.forbidden
          : SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        // Full 26 × 26 target so a click anywhere in the button — not just
        // on the 15 px icon glyph — registers. The default `deferToChild`
        // behavior only hit-tests the icon itself, which made the link
        // button feel unresponsive (and the Insert-link dialog appear to
        // "not open") when clicks landed in the padding.
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 100),
          width: 26,
          height: 26,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(ZebuRadius.rSm),
          ),
          child: Icon(widget.icon, size: 20, color: fg),
        ),
      ),
    );
    return widget.tooltip == null
        ? child
        : Tooltip(
            message: widget.tooltip!,
            // Material's default (24 px) leaves a visible gap above the
            // 26 × 26 toolbar button; tighten it so the label reads as
            // a hint attached to the icon, not a floating chip.
            verticalOffset: 14,
            child: child,
          );
  }
}

// ---------------------------------------------------------------------------
// Reply / Note pill.
// ---------------------------------------------------------------------------

/// Reply / Note switch, as a segmented control.
///
/// Previously two separate outlined chips, which read as two independent
/// actions rather than one either-or choice — nothing about the shape said
/// that picking one unpicked the other. A single track split in two says it
/// structurally.
///
/// The distinction is worth the care: a **reply is emailed to the customer**
/// and a **note never leaves the team**. Note therefore carries the warning
/// tone rather than the brand accent, so the selected half looks materially
/// different depending on where a submission is going.
class _ModeSegmented extends StatelessWidget {
  const _ModeSegmented({required this.asNote, required this.onChanged});

  final bool asNote;

  /// Null while a submission is in flight — the whole control locks.
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    final t = ZebuTheme.of(context);
    return Container(
      // Recessed track, no border: the fill alone reads as a well, and a
      // hairline around it made the control look like a bordered button
      // group with an odd grey inside rather than one switch.
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: t.isLight ? const Color(0xFFF2F4F7) : t.surfaceMuted,
        borderRadius: BorderRadius.circular(9),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _ModeSegment(
            label: 'Reply',
            active: !asNote,
            tone: t.accent,
            onTap: onChanged == null ? null : () => onChanged!(false),
          ),
          _ModeSegment(
            label: 'Note',
            active: asNote,
            tone: t.note,
            onTap: onChanged == null ? null : () => onChanged!(true),
          ),
        ],
      ),
    );
  }
}

class _ModeSegment extends StatefulWidget {
  const _ModeSegment({
    required this.label,
    required this.active,
    required this.tone,
    required this.onTap,
  });
  final String label;
  final bool active;
  final Color tone;
  final VoidCallback? onTap;

  @override
  State<_ModeSegment> createState() => _ModeSegmentState();
}

class _ModeSegmentState extends State<_ModeSegment> {
  @override
  Widget build(BuildContext context) {
    final t = ZebuTheme.of(context);
    return MouseRegion(
      cursor: widget.onTap == null
          ? SystemMouseCursors.forbidden
          : SystemMouseCursors.click,
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          curve: Curves.easeOut,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
          decoration: BoxDecoration(
            // The selected half lifts to an elevated surface inside the
            // recessed track — the standard segmented-control read. Idle
            // halves show the track through, with no hover fill: both halves
            // are always visible and one is always selected, so a hover state
            // added motion without adding information.
            color: widget.active
                ? t.bgElevated
                : t.bgElevated.withValues(alpha: 0),
            borderRadius: BorderRadius.circular(6),
            // A touch heavier than shadowXs — the lift has to survive being
            // read against a grey track rather than a white page.
            boxShadow: widget.active
                ? const [
                    BoxShadow(
                      color: Color(0x1A101828),
                      blurRadius: 2,
                      offset: Offset(0, 1),
                    ),
                  ]
                : null,
          ),
          child: Text(
            widget.label,
            style: ZebuTextStyles.small(context).copyWith(
              color: widget.active ? widget.tone : t.textSlateMuted,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }
}

class _FileChip extends StatefulWidget {
  const _FileChip({required this.name, required this.onRemove});
  final String name;
  final VoidCallback? onRemove;

  @override
  State<_FileChip> createState() => _FileChipState();
}

class _FileChipState extends State<_FileChip> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final t = ZebuTheme.of(context);
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: t.bgTertiary,
          border: Border.all(
            color: _hover ? t.borderDefault : t.borderSubtle,
            width: 1,
          ),
          borderRadius: BorderRadius.circular(_kFlatRadius),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.attach_file, size: 12, color: t.textSecondary),
            const SizedBox(width: 4),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 200),
              child: Text(
                widget.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: ZebuTextStyles.small(
                  context,
                ).copyWith(fontWeight: FontWeight.w500),
              ),
            ),
            if (widget.onRemove != null) ...[
              const SizedBox(width: 4),
              GestureDetector(
                onTap: widget.onRemove,
                child: MouseRegion(
                  cursor: SystemMouseCursors.click,
                  child: Icon(Icons.close, size: 12, color: t.textSecondary),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Filled send button.
// ---------------------------------------------------------------------------

class _SendButton extends StatefulWidget {
  const _SendButton({
    required this.label,
    required this.tone,
    required this.disabled,
    required this.onTap,
    required this.loading,
  });
  final String label;
  final Color tone;
  final bool disabled;
  final bool loading;
  final VoidCallback onTap;

  @override
  State<_SendButton> createState() => _SendButtonState();
}

class _SendButtonState extends State<_SendButton> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final effective = widget.disabled
        ? widget.tone.withValues(alpha: 0.4)
        : widget.tone;
    return MouseRegion(
      cursor: widget.disabled
          ? SystemMouseCursors.forbidden
          : SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: widget.disabled ? null : widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          curve: Curves.easeOut,
          padding: const EdgeInsets.symmetric(
            horizontal: ZebuSpacing.s3,
            vertical: 8,
          ),
          decoration: BoxDecoration(
            color: _hover && !widget.disabled
                ? Color.lerp(effective, Colors.black, 0.08)
                : effective,
            borderRadius: BorderRadius.circular(_kFlatRadius),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (widget.loading)
                const SizedBox(
                  width: 12,
                  height: 12,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              else
                const Icon(Icons.send, size: 12, color: Colors.white),
              const SizedBox(width: 6),
              Text(
                widget.label,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Emoji picker — anchored overlay grid (6 × 8 curated emojis). Same
// overlay + outside-tap-to-dismiss pattern as `showAppDropdown`.
// ---------------------------------------------------------------------------

const List<String> _kEmojis = [
  '😀',
  '😁',
  '😂',
  '🤣',
  '😃',
  '😄',
  '😅',
  '😊',
  '😉',
  '😍',
  '🥰',
  '😘',
  '🤗',
  '🤔',
  '🤨',
  '😐',
  '😑',
  '😶',
  '🙄',
  '😏',
  '😴',
  '🤯',
  '😳',
  '🥺',
  '😢',
  '😭',
  '😤',
  '😠',
  '😡',
  '🤬',
  '🤢',
  '🤧',
  '👍',
  '👎',
  '👏',
  '🙏',
  '🤝',
  '💪',
  '✌️',
  '🤞',
  '👌',
  '👋',
  '🙌',
  '🤲',
  '🙈',
  '🙉',
  '🙊',
  '💬',
  '❤️',
  '💔',
  '💯',
  '🔥',
  '⭐',
  '✨',
  '⚡',
  '💡',
  '✅',
  '❌',
  '⚠️',
  '❓',
  '❗',
  '📌',
  '🔔',
  '🎉',
];

Future<String?> showEmojiPicker(BuildContext anchorContext) async {
  final box = anchorContext.findRenderObject();
  if (box is! RenderBox || !box.attached) return null;
  final overlayState = Overlay.of(anchorContext);
  final overlayBox = overlayState.context.findRenderObject()! as RenderBox;
  final anchorTopLeft = box.localToGlobal(Offset.zero, ancestor: overlayBox);
  final anchorSize = box.size;
  final viewport = overlayBox.size;
  final t = ZebuTheme.of(anchorContext);

  const menuWidth = 280.0;
  const menuHeight = 224.0;

  final menuLeft = (anchorTopLeft.dx + anchorSize.width - menuWidth).clamp(
    8.0,
    viewport.width - menuWidth - 8.0,
  );
  // Prefer above the anchor since the composer sits at the bottom of the
  // panel; fall back to below when there's no room upwards.
  final aboveTop = anchorTopLeft.dy - menuHeight - 6;
  final belowTop = anchorTopLeft.dy + anchorSize.height + 6;
  final menuTop = aboveTop >= 8 ? aboveTop : belowTop;

  final completer = Completer<String?>();
  late OverlayEntry entry;

  void dismiss(String? value) {
    if (completer.isCompleted) return;
    completer.complete(value);
    entry.remove();
  }

  entry = OverlayEntry(
    builder: (ctx) => Stack(
      children: [
        Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => dismiss(null),
          ),
        ),
        Positioned(
          left: menuLeft,
          top: menuTop,
          width: menuWidth,
          height: menuHeight,
          child: Focus(
            autofocus: true,
            onKeyEvent: (_, event) {
              if (event is KeyDownEvent &&
                  event.logicalKey == LogicalKeyboardKey.escape) {
                dismiss(null);
                return KeyEventResult.handled;
              }
              return KeyEventResult.ignored;
            },
            child: Material(
              color: t.bgElevated,
              surfaceTintColor: Colors.transparent,
              elevation: 6,
              borderRadius: BorderRadius.circular(8),
              clipBehavior: Clip.antiAlias,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: t.borderSubtle, width: 1),
                ),
                child: GridView.count(
                  padding: const EdgeInsets.all(8),
                  crossAxisCount: 8,
                  mainAxisSpacing: 2,
                  crossAxisSpacing: 2,
                  children: [
                    for (final e in _kEmojis)
                      _EmojiCell(emoji: e, onTap: () => dismiss(e)),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    ),
  );

  overlayState.insert(entry);
  return completer.future;
}

class _EmojiCell extends StatefulWidget {
  const _EmojiCell({required this.emoji, required this.onTap});
  final String emoji;
  final VoidCallback onTap;

  @override
  State<_EmojiCell> createState() => _EmojiCellState();
}

class _EmojiCellState extends State<_EmojiCell> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final t = ZebuTheme.of(context);
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 100),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: _hover ? t.bgHover : Colors.transparent,
            borderRadius: BorderRadius.circular(4),
          ),
          child: Text(widget.emoji, style: const TextStyle(fontSize: 18)),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Link picker — an Overlay-based popup with URL (+ optional text) fields.
//
// The earlier version was a `showDialog` Material dialog, but on Flutter
// Web it silently failed to appear when invoked from inside the Fleather-
// focused composer: the tap fired, `showDialog` was called, no dialog
// painted. Reproduced on multiple browsers. Rather than keep fighting
// Navigator + IME interactions, we host the picker in an OverlayEntry —
// exactly the pattern [showEmojiPicker] already uses in this file, and
// which works reliably from every panel context.
// ---------------------------------------------------------------------------

/// Value returned by the picker when the user commits with Apply.
class _LinkResult {
  const _LinkResult({required this.url, required this.text});
  final String url;
  final String text;
}

/// Inline anchored popover for inserting / editing a link. Two fields
/// (display Text + URL) plus an Apply button; the picker collects input
/// and returns a [_LinkResult] on Apply, or `null` on Esc / outside-tap.
///
/// Positioned above the link toolbar button (falls back below when the
/// button is near the top of the viewport). No scrim — the popover feels
/// inline rather than modal.
///
/// **Why submit-based rather than live-editing:** an earlier iteration
/// mutated the document on every keystroke, but that meant Esc /
/// outside-tap could not "cancel" — the changes were already committed.
/// Apply-to-commit puts the user in control: the document only changes
/// when they say so.
Future<_LinkResult?> _showLinkPicker(
  BuildContext anchorContext, {
  required String initialText,
}) async {
  final box = anchorContext.findRenderObject();
  if (box is! RenderBox || !box.attached) return null;
  final overlayState = Overlay.of(anchorContext, rootOverlay: true);
  final overlayBox = overlayState.context.findRenderObject()! as RenderBox;
  final anchorTopLeft = box.localToGlobal(Offset.zero, ancestor: overlayBox);
  final anchorSize = box.size;
  final viewport = overlayBox.size;

  const popoverWidth = 320.0;
  const popoverHeight = 132.0;

  // Right-align the popover under the button so it stays visually tied
  // to its anchor; clamp so it never runs off the viewport.
  final popoverLeft = (anchorTopLeft.dx + anchorSize.width - popoverWidth)
      .clamp(8.0, viewport.width - popoverWidth - 8.0);
  final aboveTop = anchorTopLeft.dy - popoverHeight - 8;
  final belowTop = anchorTopLeft.dy + anchorSize.height + 8;
  final popoverTop = aboveTop >= 8 ? aboveTop : belowTop;

  final completer = Completer<_LinkResult?>();
  late OverlayEntry entry;

  void dismiss(_LinkResult? value) {
    if (completer.isCompleted) return;
    completer.complete(value);
    entry.remove();
  }

  entry = OverlayEntry(
    builder: (ctx) => Stack(
      children: [
        // Transparent outside-tap barrier — no scrim so the popover
        // feels inline rather than modal.
        Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => dismiss(null),
            child: const SizedBox.expand(),
          ),
        ),
        Positioned(
          left: popoverLeft,
          top: popoverTop,
          width: popoverWidth,
          child: FocusScope(
            autofocus: true,
            onKeyEvent: (_, event) {
              if (event is KeyDownEvent &&
                  event.logicalKey == LogicalKeyboardKey.escape) {
                dismiss(null);
                return KeyEventResult.handled;
              }
              return KeyEventResult.ignored;
            },
            child: _LinkCard(
              initialText: initialText,
              onApply: (result) => dismiss(result),
            ),
          ),
        ),
      ],
    ),
  );

  overlayState.insert(entry);
  return completer.future;
}

class _LinkCard extends StatefulWidget {
  const _LinkCard({required this.initialText, required this.onApply});

  /// Text currently occupying the range being linked — primes the Text
  /// field so users see (and can edit) what will be turned into a link.
  final String initialText;

  /// Called with the committed link when the user clicks Apply / hits
  /// Enter. Never called for Esc / outside-tap — those dismiss with
  /// `null` at the picker level.
  final ValueChanged<_LinkResult> onApply;

  @override
  State<_LinkCard> createState() => _LinkCardState();
}

class _LinkCardState extends State<_LinkCard> {
  late final TextEditingController _text;
  final _url = TextEditingController();
  final _urlFocus = FocusNode();

  @override
  void initState() {
    super.initState();
    _text = TextEditingController(text: widget.initialText);
    // Both listeners just repaint so the Apply button's enabled state
    // tracks the current input.
    _text.addListener(_repaint);
    _url.addListener(_repaint);
    // Autofocus the URL field — matches the "Add URL" flow. Scheduled
    // post-frame so the overlay has time to mount.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _urlFocus.requestFocus();
    });
  }

  @override
  void dispose() {
    _text.removeListener(_repaint);
    _url.removeListener(_repaint);
    _text.dispose();
    _url.dispose();
    _urlFocus.dispose();
    super.dispose();
  }

  void _repaint() {
    if (mounted) setState(() {});
  }

  /// Scheme-less URLs (`example.com`) auto-prefix `https://` so the
  /// inline flow stays low-friction.
  String _normalize(String raw) {
    final u = raw.trim();
    if (u.isEmpty) return u;
    if (u.startsWith('http://') ||
        u.startsWith('https://') ||
        u.startsWith('mailto:')) {
      return u;
    }
    return 'https://$u';
  }

  /// Apply is enabled once there's a URL to link to. The Text field is
  /// optional — if it's blank we'll fall back to the URL string as the
  /// display text (the caller in [_openLinkDialog] handles that).
  bool get _canApply => _url.text.trim().isNotEmpty;

  void _apply() {
    if (!_canApply) return;
    widget.onApply(
      _LinkResult(url: _normalize(_url.text), text: _text.text.trim()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = ZebuTheme.of(context);
    return Material(
      color: t.bgElevated,
      elevation: 10,
      borderRadius: BorderRadius.circular(ZebuRadius.rMd),
      clipBehavior: Clip.antiAlias,
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border.all(color: t.borderSubtle, width: 1),
          borderRadius: BorderRadius.circular(ZebuRadius.rMd),
        ),
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _PopoverField(
                controller: _text,
                hint: 'Text',
                onSubmitted: (_) => _apply(),
              ),
              const SizedBox(height: 6),
              // URL + Apply on one row — mirrors the reference design
              // (link icon prefix on the field, "Apply" trailing).
              Row(
                children: [
                  Expanded(
                    child: _PopoverField(
                      controller: _url,
                      focusNode: _urlFocus,
                      hint: 'Add URL',
                      keyboardType: TextInputType.url,
                      prefixIcon: Icon(
                        Icons.link,
                        size: 16,
                        color: t.textSecondary,
                      ),
                      onSubmitted: (_) => _apply(),
                    ),
                  ),
                  const SizedBox(width: 6),
                  _ApplyButton(onTap: _canApply ? _apply : null),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PopoverField extends StatelessWidget {
  const _PopoverField({
    required this.controller,
    required this.hint,
    this.focusNode,
    this.keyboardType,
    this.onSubmitted,
    this.prefixIcon,
  });
  final TextEditingController controller;
  final String hint;
  final FocusNode? focusNode;
  final TextInputType? keyboardType;
  final ValueChanged<String>? onSubmitted;

  /// Optional widget rendered before the input (link icon on the URL
  /// row, per the reference popover).
  final Widget? prefixIcon;

  @override
  Widget build(BuildContext context) {
    final t = ZebuTheme.of(context);
    return TextField(
      controller: controller,
      focusNode: focusNode,
      keyboardType: keyboardType,
      onSubmitted: onSubmitted,
      style: ZebuTextStyles.body(context).copyWith(color: t.textPrimary),
      decoration: InputDecoration(
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 10,
          vertical: 10,
        ),
        hintText: hint,
        hintStyle: ZebuTextStyles.body(
          context,
        ).copyWith(color: t.textSecondary),
        prefixIcon: prefixIcon == null
            ? null
            : Padding(
                padding: const EdgeInsets.only(left: 10, right: 6),
                child: prefixIcon,
              ),
        prefixIconConstraints: const BoxConstraints(minWidth: 0, minHeight: 0),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(ZebuRadius.rSm),
          borderSide: BorderSide(color: t.borderSubtle, width: 1),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(ZebuRadius.rSm),
          borderSide: BorderSide(color: t.borderSubtle, width: 1),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(ZebuRadius.rSm),
          borderSide: BorderSide(color: t.accent, width: 1.4),
        ),
      ),
    );
  }
}

/// Compact "Apply" button for the link popover. Blue text when enabled,
/// dims when the URL field is empty. Not a FilledButton so it stays
/// visually flat inside the small popover — matches the reference.
class _ApplyButton extends StatefulWidget {
  const _ApplyButton({required this.onTap});
  final VoidCallback? onTap;

  @override
  State<_ApplyButton> createState() => _ApplyButtonState();
}

class _ApplyButtonState extends State<_ApplyButton> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final t = ZebuTheme.of(context);
    final enabled = widget.onTap != null;
    final fg = enabled ? t.accent : t.textSecondary.withValues(alpha: 0.4);
    return MouseRegion(
      cursor: enabled ? SystemMouseCursors.click : SystemMouseCursors.forbidden,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 100),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: enabled && _hover
                ? t.accent.withValues(alpha: 0.08)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(ZebuRadius.rSm),
          ),
          child: Text(
            'Apply',
            style: ZebuTextStyles.body(
              context,
            ).copyWith(color: fg, fontWeight: FontWeight.w600),
          ),
        ),
      ),
    );
  }
}
