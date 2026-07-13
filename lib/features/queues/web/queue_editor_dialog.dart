import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_exception.dart';
import '../../../models/saved_queue.dart';
import '../../../providers.dart';
import '../../dashboard/web/_tokens.dart';

const _kFlatRadius = 8.0;

/// Web-styled create / rename dialog for saved queues. Matches the
/// [_CreateOrgDialog] chrome (WebTokens shell, flat radius, brand-blue
/// primary, danger error banner).
class QueueEditorDialog extends ConsumerStatefulWidget {
  const QueueEditorDialog({super.key, this.existing});
  final SavedQueue? existing;

  @override
  ConsumerState<QueueEditorDialog> createState() => _QueueEditorDialogState();
}

class _QueueEditorDialogState extends ConsumerState<QueueEditorDialog> {
  late final _name = TextEditingController(
    text: widget.existing?.name ?? '',
  );
  final _q = TextEditingController();

  bool _saving = false;
  String? _formError;
  final _fieldErrors = <String, String>{};

  bool get _isEdit => widget.existing != null;

  @override
  void dispose() {
    _name.dispose();
    _q.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() {
      _saving = true;
      _formError = null;
      _fieldErrors.clear();
    });
    final repo = ref.read(queuesRepositoryProvider);
    try {
      if (_isEdit) {
        await repo.update(widget.existing!.id, {'name': _name.text.trim()});
      } else {
        final q = _q.text.trim();
        await repo.create(
          name: _name.text.trim(),
          criteria: q.isEmpty ? null : {'q': q},
        );
      }
      if (mounted) Navigator.pop(context, true);
    } on ApiException catch (e) {
      setState(() {
        _formError = e.fields.isEmpty ? e.message : null;
        _fieldErrors.addAll(e.fields);
      });
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = WebTokens.of(context);
    return AlertDialog(
      backgroundColor: t.bgElevated,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      insetPadding: const EdgeInsets.all(40),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(WebTokens.rMd),
        side: BorderSide(color: t.borderSubtle, width: 1),
      ),
      titlePadding: const EdgeInsets.fromLTRB(
        WebTokens.s5,
        WebTokens.s5,
        WebTokens.s5,
        WebTokens.s3,
      ),
      contentPadding: const EdgeInsets.fromLTRB(
        WebTokens.s5,
        0,
        WebTokens.s5,
        WebTokens.s4,
      ),
      actionsPadding: const EdgeInsets.fromLTRB(
        WebTokens.s5,
        0,
        WebTokens.s5,
        WebTokens.s4,
      ),
      title: Row(
        children: [
          Expanded(
            child: Text(
              _isEdit ? 'Rename queue' : 'New personal queue',
              style: t.pageTitle,
            ),
          ),
          _CloseIconBtn(
            onTap: _saving ? null : () => Navigator.pop(context, false),
          ),
        ],
      ),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _FieldLabel(text: 'Name'),
            const SizedBox(height: 6),
            _ThemedTextField(
              controller: _name,
              autofocus: true,
              hasError: _fieldErrors['name'] != null,
            ),
            if (_fieldErrors['name'] != null) ...[
              const SizedBox(height: 4),
              Text(
                _fieldErrors['name']!,
                style: t.bodySm.copyWith(color: t.danger),
              ),
            ],
            if (!_isEdit) ...[
              const SizedBox(height: WebTokens.s3),
              _FieldLabel(text: 'Search filter (optional)'),
              const SizedBox(height: 6),
              _ThemedTextField(
                controller: _q,
                hint: 'Keyword to match',
              ),
            ],
            if (_formError != null) ...[
              const SizedBox(height: WebTokens.s3),
              _ErrorBanner(message: _formError!),
            ],
          ],
        ),
      ),
      actions: [
        _SecondaryButton(
          label: 'Cancel',
          onTap: _saving ? null : () => Navigator.pop(context, false),
        ),
        const SizedBox(width: WebTokens.s2),
        _PrimaryButton(
          label: _isEdit ? 'Save' : 'Create queue',
          busy: _saving,
          onTap: _saving ? null : _save,
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Themed primitives (mirrors _CreateOrgDialog / CannedEditorDialog)
// ---------------------------------------------------------------------------

class _FieldLabel extends StatelessWidget {
  const _FieldLabel({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    final t = WebTokens.of(context);
    return Text(
      text,
      style: t.bodySm.copyWith(
        color: t.textPrimary,
        fontWeight: FontWeight.w600,
      ),
    );
  }
}

class _ThemedTextField extends StatelessWidget {
  const _ThemedTextField({
    required this.controller,
    this.hint,
    this.autofocus = false,
    this.hasError = false,
  });

  final TextEditingController controller;
  final String? hint;
  final bool autofocus;
  final bool hasError;

  @override
  Widget build(BuildContext context) {
    final t = WebTokens.of(context);
    final border = OutlineInputBorder(
      borderRadius: BorderRadius.circular(_kFlatRadius),
      borderSide: BorderSide(
        color: hasError ? t.danger : t.borderSubtle,
        width: 1,
      ),
    );
    final focusedBorder = OutlineInputBorder(
      borderRadius: BorderRadius.circular(_kFlatRadius),
      borderSide: BorderSide(
        color: hasError ? t.danger : t.accent,
        width: 1.4,
      ),
    );
    return TextField(
      controller: controller,
      autofocus: autofocus,
      style: t.bodyBase,
      decoration: InputDecoration(
        filled: true,
        fillColor: t.bgElevated,
        hoverColor: Colors.transparent,
        border: border,
        enabledBorder: border,
        focusedBorder: focusedBorder,
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: WebTokens.s3,
          vertical: 12,
        ),
        hintText: hint,
        hintStyle: t.bodyBase.copyWith(color: t.textSecondary),
      ),
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message});
  final String message;

  @override
  Widget build(BuildContext context) {
    final t = WebTokens.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: WebTokens.s3,
        vertical: WebTokens.s2,
      ),
      decoration: BoxDecoration(
        color: t.dangerLight,
        border: Border.all(color: t.danger, width: 1),
        borderRadius: BorderRadius.circular(_kFlatRadius),
      ),
      child: Row(
        children: [
          Icon(Icons.error_outline, size: 16, color: t.danger),
          const SizedBox(width: WebTokens.s2),
          Expanded(
            child: Text(
              message,
              style: t.bodySm.copyWith(color: t.danger),
            ),
          ),
        ],
      ),
    );
  }
}

class _CloseIconBtn extends StatefulWidget {
  const _CloseIconBtn({required this.onTap});
  final VoidCallback? onTap;

  @override
  State<_CloseIconBtn> createState() => _CloseIconBtnState();
}

class _CloseIconBtnState extends State<_CloseIconBtn> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final t = WebTokens.of(context);
    final disabled = widget.onTap == null;
    return Tooltip(
      message: 'Close',
      child: MouseRegion(
        cursor: disabled
            ? SystemMouseCursors.basic
            : SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: GestureDetector(
          onTap: widget.onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 100),
            width: 32,
            height: 32,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: _hover && !disabled ? t.bgHover : t.bgTertiary,
              borderRadius: BorderRadius.circular(WebTokens.rSm),
            ),
            child: Icon(Icons.close, size: 16, color: t.textSecondary),
          ),
        ),
      ),
    );
  }
}

class _SecondaryButton extends StatefulWidget {
  const _SecondaryButton({required this.label, required this.onTap});
  final String label;
  final VoidCallback? onTap;

  @override
  State<_SecondaryButton> createState() => _SecondaryButtonState();
}

class _SecondaryButtonState extends State<_SecondaryButton> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final t = WebTokens.of(context);
    final disabled = widget.onTap == null;
    return MouseRegion(
      cursor: disabled
          ? SystemMouseCursors.basic
          : SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 100),
          padding: const EdgeInsets.symmetric(
            horizontal: WebTokens.s4,
            vertical: 10,
          ),
          decoration: BoxDecoration(
            color: _hover && !disabled ? t.bgHover : t.bgElevated,
            border: Border.all(color: t.borderDefault, width: 1),
            borderRadius: BorderRadius.circular(_kFlatRadius),
          ),
          child: Text(
            widget.label,
            style: t.bodySm.copyWith(
              color: t.textPrimary,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }
}

class _PrimaryButton extends StatefulWidget {
  const _PrimaryButton({
    required this.label,
    required this.onTap,
    this.busy = false,
  });
  final String label;
  final VoidCallback? onTap;
  final bool busy;

  @override
  State<_PrimaryButton> createState() => _PrimaryButtonState();
}

class _PrimaryButtonState extends State<_PrimaryButton> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    // Filled primary button keeps the Mynt brand blue in both modes.
    final disabled = widget.onTap == null;
    final base = disabled
        ? WebTokens.accentLight.withValues(alpha: 0.4)
        : WebTokens.accentLight;
    final fill = _hover && !disabled
        ? Color.lerp(base, Colors.black, 0.08) ?? base
        : base;
    return MouseRegion(
      cursor: disabled
          ? SystemMouseCursors.basic
          : SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 100),
          padding: const EdgeInsets.symmetric(
            horizontal: WebTokens.s4,
            vertical: 10,
          ),
          decoration: BoxDecoration(
            color: fill,
            borderRadius: BorderRadius.circular(_kFlatRadius),
          ),
          child: widget.busy
              ? const SizedBox(
                  height: 16,
                  width: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : Text(
                  widget.label,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
        ),
      ),
    );
  }
}
