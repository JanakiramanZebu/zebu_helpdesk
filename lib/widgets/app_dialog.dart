import 'package:flutter/material.dart';

/// Mynt Plus-style confirmation dialog: a rounded white card with a close (X)
/// button top-right, a centered bold title + muted message, and a single
/// full-width primary action button.
///
/// Returns `true` when the action button is tapped, and `false`/`null` when
/// dismissed via the X, the barrier, or the back button.
Future<bool?> showAppConfirmDialog(
  BuildContext context, {
  String? title,
  required String message,
  String confirmLabel = 'Yes',
  bool destructive = false,
}) {
  return showDialog<bool>(
    context: context,
    builder: (ctx) => _AppDialogCard(
      title: title,
      message: message,
      actionLabel: confirmLabel,
      destructive: destructive,
      onAction: () => Navigator.pop(ctx, true),
      onClose: () => Navigator.pop(ctx, false),
    ),
  );
}

/// Mynt Plus-style informational dialog: the same card with a single dismiss
/// button (defaults to "OK"). Use for notices that need acknowledgement only.
Future<void> showAppMessageDialog(
  BuildContext context, {
  String? title,
  required String message,
  String buttonLabel = 'OK',
}) {
  return showDialog<void>(
    context: context,
    builder: (ctx) => _AppDialogCard(
      title: title,
      message: message,
      actionLabel: buttonLabel,
      onAction: () => Navigator.pop(ctx),
      onClose: () => Navigator.pop(ctx),
    ),
  );
}

/// The shared Mynt Plus dialog card used by both helpers above.
class _AppDialogCard extends StatelessWidget {
  const _AppDialogCard({
    required this.message,
    required this.actionLabel,
    required this.onAction,
    required this.onClose,
    this.title,
    this.destructive = false,
  });

  final String? title;
  final String message;
  final String actionLabel;
  final VoidCallback onAction;
  final VoidCallback onClose;
  final bool destructive;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final actionColor = destructive ? scheme.error : scheme.primary;

    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 28),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 10, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Align(
              alignment: Alignment.centerRight,
              child: IconButton(
                icon: const Icon(Icons.close, size: 22),
                color: scheme.onSurfaceVariant,
                visualDensity: VisualDensity.compact,
                onPressed: onClose,
              ),
            ),
            if (title != null) ...[
              Text(
                title!,
                textAlign: TextAlign.center,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 8),
            ],
            Text(
              message,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: scheme.onSurfaceVariant,
                height: 1.35,
              ),
            ),
            const SizedBox(height: 22),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(48),
                  backgroundColor: actionColor,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                onPressed: onAction,
                child: Text(actionLabel),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
