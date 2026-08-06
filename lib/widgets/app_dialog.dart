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

    // Compact centered card: header row (title left, X right), divider,
    // then message + full-width primary button. Constrained to 360 px so
    // it doesn't stretch across wide desktop viewports.
    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      backgroundColor: scheme.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 360),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 8, 14),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      title ?? '',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, size: 20),
                    color: scheme.onSurfaceVariant,
                    visualDensity: VisualDensity.compact,
                    onPressed: onClose,
                  ),
                ],
              ),
            ),
            Divider(height: 1, color: scheme.outlineVariant),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 22, 20, 20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    message,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: scheme.onSurface,
                      height: 1.35,
                    ),
                  ),
                  const SizedBox(height: 22),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      // Stadium pill — mobile `_DialogPrimaryButton` parity.
                      // Solid fill (not gradient) so destructive dialogs keep
                      // their error color.
                      style: FilledButton.styleFrom(
                        minimumSize: const Size.fromHeight(48),
                        backgroundColor: actionColor,
                        foregroundColor: Colors.white,
                        shape: const StadiumBorder(),
                        textStyle: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      onPressed: onAction,
                      child: Text(actionLabel),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
