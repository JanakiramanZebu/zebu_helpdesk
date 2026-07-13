import 'package:fleather/fleather.dart';
import 'package:flutter/material.dart';

import '../core/theme/app_text.dart';
import 'composer_actions.dart';

/// A bordered rich-text message field backed by a [FleatherController].
///
/// Mirrors the ticket/task reply composer: a labelled container with a
/// formatting toolbar (bold/italic/lists/links/…), a bounded-height editor,
/// and an expand-to-fullscreen action for long messages. The parent owns the
/// [controller], so it decides how to read the body (e.g.
/// `parchmentHtml.encode(controller.document)`), clear it, or insert text.
///
/// Colours, borders and fonts come from the ambient [ThemeData] and its
/// `inputDecorationTheme` so it visually matches the app's other fields.
class RichMessageField extends StatefulWidget {
  const RichMessageField({
    super.key,
    required this.controller,
    this.label,
    this.hintText,
    this.errorText,
    this.minHeight = 120,
    this.maxHeight = 260,
    this.bordered = true,
    this.onInsertCanned,
    this.onInsertFaq,
  });

  final FleatherController controller;
  final String? label;
  final String? hintText;
  final String? errorText;
  final double minHeight;
  final double maxHeight;

  /// When false the field drops its outer border/fill and renders flat (just a
  /// toolbar row, a hairline and the editor) so it can sit inside a grouped
  /// "list" surface — the Gmail-compose look. Defaults to the bordered box.
  final bool bordered;

  /// Optional inline inserters. When set, a compact "saved replies" / "FAQ"
  /// icon pair rides in the toolbar row next to the expand button.
  final VoidCallback? onInsertCanned;
  final VoidCallback? onInsertFaq;

  @override
  State<RichMessageField> createState() => _RichMessageFieldState();
}

class _RichMessageFieldState extends State<RichMessageField> {
  final FocusNode _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    // Rebuild so the placeholder and focus border track edits/focus.
    _focus.addListener(_onChange);
    widget.controller.addListener(_onChange);
  }

  @override
  void dispose() {
    _focus.removeListener(_onChange);
    widget.controller.removeListener(_onChange);
    _focus.dispose();
    super.dispose();
  }

  void _onChange() {
    if (mounted) setState(() {});
  }

  bool get _isEmpty =>
      widget.controller.document.toPlainText().trim().isEmpty;

  Future<void> _openFullscreen() async {
    _focus.unfocus();
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        fullscreenDialog: true,
        builder: (_) => _FullscreenMessageEditor(
          controller: widget.controller,
          title: widget.label ?? 'Message',
        ),
      ),
    );
    if (mounted) setState(() {});
  }

  /// Wraps the toolbar+editor in a bordered box, or returns it flat (no border
  /// or fill) when [RichMessageField.bordered] is false so it can nest inside a
  /// grouped list surface.
  Widget _wrap(
    BuildContext context, {
    required Color borderColor,
    required bool hasError,
    required Widget child,
  }) {
    if (!widget.bordered) return child;
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).inputDecorationTheme.fillColor,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: borderColor,
          width: _focus.hasFocus || hasError ? 1.6 : 1,
        ),
      ),
      child: child,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final hasError = widget.errorText != null;
    final borderColor = hasError
        ? scheme.error
        : _focus.hasFocus
        ? scheme.primary
        : scheme.outlineVariant;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (widget.label != null) ...[
          AppText.paraText(
            context,
            widget.label!,
            fw: 0,
            color: hasError ? scheme.error : scheme.onSurfaceVariant,
          ),
          const SizedBox(height: 6),
        ],
        _wrap(
          context,
          borderColor: borderColor,
          hasError: hasError,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Toolbar + insert/expand row.
              Row(
                children: [
                  Expanded(
                    child: FleatherToolbar.basic(
                      controller: widget.controller,
                      hideBackgroundColor: true,
                      hideForegroundColor: true,
                      hideDirection: true,
                      hideListChecks: true,
                      hideAlignment: true,
                    ),
                  ),
                  if (widget.onInsertCanned != null ||
                      widget.onInsertFaq != null)
                    ComposerActionChips(
                      onCanned: widget.onInsertCanned ?? () {},
                      onFaq: widget.onInsertFaq ?? () {},
                    ),
                  IconButton(
                    tooltip: 'Expand',
                    visualDensity: VisualDensity.compact,
                    icon: Icon(
                      Icons.open_in_full,
                      size: 18,
                      color: scheme.onSurfaceVariant,
                    ),
                    onPressed: _openFullscreen,
                  ),
                  const SizedBox(width: 4),
                ],
              ),
              Divider(height: 1, color: scheme.outlineVariant),
              // Editor with a placeholder overlay when empty.
              ConstrainedBox(
                constraints: BoxConstraints(
                  minHeight: widget.minHeight,
                  maxHeight: widget.maxHeight,
                ),
                child: Stack(
                  children: [
                    FleatherEditor(
                      controller: widget.controller,
                      focusNode: _focus,
                      padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
                    ),
                    if (_isEmpty && widget.hintText != null)
                      Positioned(
                        left: 12,
                        top: 10,
                        child: IgnorePointer(
                          child: AppText.subText(
                            context,
                            widget.hintText!,
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
        if (hasError) ...[
          const SizedBox(height: 6),
          AppText.paraText(context, widget.errorText!, color: scheme.error),
        ],
      ],
    );
  }
}

/// Full-screen editor for composing a long message; shares the field's
/// [FleatherController] so edits round-trip back to the inline field.
class _FullscreenMessageEditor extends StatefulWidget {
  const _FullscreenMessageEditor({
    required this.controller,
    required this.title,
  });

  final FleatherController controller;
  final String title;

  @override
  State<_FullscreenMessageEditor> createState() =>
      _FullscreenMessageEditorState();
}

class _FullscreenMessageEditorState extends State<_FullscreenMessageEditor> {
  final FocusNode _focus = FocusNode();

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          tooltip: 'Collapse',
          icon: const Icon(Icons.close_fullscreen),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(widget.title),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: FilledButton.icon(
              onPressed: () => Navigator.of(context).pop(),
              icon: const Icon(Icons.check, size: 18),
              label: const Text('Done'),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: FleatherEditor(
              controller: widget.controller,
              focusNode: _focus,
              autofocus: true,
              expands: true,
              padding: const EdgeInsets.all(16),
            ),
          ),
          SafeArea(
            top: false,
            child: FleatherToolbar.basic(controller: widget.controller),
          ),
        ],
      ),
    );
  }
}
