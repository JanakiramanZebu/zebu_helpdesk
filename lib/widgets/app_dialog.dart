import 'package:flutter/material.dart';

import '../res/zebu_spacing.dart';
import '../res/zebu_text_styles.dart';
import '../res/zebu_theme.dart';
import 'web/zebu_dialog.dart';

/// Confirmation dialog, built on the app's shared [ZebuDialogShell] so it
/// carries the same frame, scrim, close button and keyboard handling as every
/// other dialog. It used to be its own card — different radius, a stadium
/// button, centred copy — which made the one dialog an agent sees before
/// something irreversible the least familiar surface in the app.
///
/// Returns `true` when the action is confirmed, `false`/`null` when dismissed
/// via the close button, `Esc`, or the barrier.
Future<bool?> showAppConfirmDialog(
  BuildContext context, {
  String? title,
  required String message,
  String confirmLabel = 'Yes',
  bool destructive = false,
}) {
  return showZebuDialog<bool>(
    context,
    barrierLabel: title ?? confirmLabel,
    child: Builder(
      builder: (ctx) => _AppDialogCard(
        title: title ?? confirmLabel,
        message: message,
        actionLabel: confirmLabel,
        destructive: destructive,
        onAction: () => Navigator.pop(ctx, true),
        onClose: () => Navigator.pop(ctx, false),
      ),
    ),
  );
}

/// Informational dialog: the same shell with a single acknowledge button.
Future<void> showAppMessageDialog(
  BuildContext context, {
  String? title,
  required String message,
  String buttonLabel = 'OK',
}) {
  return showZebuDialog<void>(
    context,
    barrierLabel: title ?? buttonLabel,
    child: Builder(
      builder: (ctx) => _AppDialogCard(
        title: title ?? buttonLabel,
        message: message,
        actionLabel: buttonLabel,
        onAction: () => Navigator.pop(ctx),
        onClose: () => Navigator.pop(ctx),
      ),
    ),
  );
}

class _AppDialogCard extends StatelessWidget {
  const _AppDialogCard({
    required this.title,
    required this.message,
    required this.actionLabel,
    required this.onAction,
    required this.onClose,
    this.destructive = false,
  });

  final String title;
  final String message;
  final String actionLabel;
  final VoidCallback onAction;
  final VoidCallback onClose;
  final bool destructive;

  @override
  Widget build(BuildContext context) {
    final t = ZebuTheme.of(context);
    return ZebuDialogShell(
      title: title,
      // Narrower than a form dialog — one sentence and one button don't
      // need 470 px, and a wide card makes a short question look uncertain.
      maxWidth: 400,
      onDismiss: onClose,
      onSubmit: onAction,
      // The action lives in the body, not a footer — the watchlist-delete
      // pattern. A confirm is one question and one answer, so a divider and a
      // right-aligned button made two zones out of a card that has one idea
      // in it.
      body: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            message,
            textAlign: TextAlign.center,
            style: ZebuTextStyles.body(
              context,
              color: t.textPrimary,
              fontWeight: ZebuFonts.medium,
            ).copyWith(height: 1.45),
          ),
          const SizedBox(height: ZebuSpacing.s6),
          ZebuDialogPrimaryBtn(
            label: actionLabel,
            destructive: destructive,
            fullWidth: true,
            onTap: onAction,
          ),
        ],
      ),
      actions: const [],
    );
  }
}
