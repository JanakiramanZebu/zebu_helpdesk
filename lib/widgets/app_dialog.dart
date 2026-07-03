import 'package:flutter/material.dart';

import '../core/theme/app_text.dart';

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

/// Mynt Plus-style dialog scaffold for **input** dialogs (a field, slider,
/// picker list, etc.). Mirrors the "Create Basket" / "Market Protection"
/// sheets from the Mynt Plus app: a rounded card with a title row (bold title
/// left, ✕ close right) over a hairline divider, an arbitrary [child] body,
/// and a single full-width primary action button. Dismiss is via the ✕ or the
/// barrier — there is no secondary "Cancel" button.
///
/// Colours and fonts come entirely from the ambient [ThemeData]; this widget
/// hard-codes no palette of its own. Drop it straight into a [showDialog]
/// builder in place of an [AlertDialog].
class AppDialog extends StatelessWidget {
  const AppDialog({
    super.key,
    required this.title,
    required this.child,
    this.actionLabel,
    this.onAction,
    this.actionEnabled = true,
    this.actionBusy = false,
    this.destructive = false,
    this.scrollable = false,
  });

  /// Bold heading shown at the top-left of the card.
  final String title;

  /// Dialog body — the field(s), slider, or list this dialog is built around.
  final Widget child;

  /// Label for the full-width primary button. When null, no button is shown
  /// (useful for picker dialogs where tapping a list row is the action).
  final String? actionLabel;

  /// Invoked when the primary button is tapped.
  final VoidCallback? onAction;

  /// Whether the primary button is tappable. Ignored when [actionBusy].
  final bool actionEnabled;

  /// Shows a spinner in the primary button and disables it.
  final bool actionBusy;

  /// Tints the primary button with the error colour.
  final bool destructive;

  /// Whether [child] should scroll if it overflows. Leave `false` when the
  /// child manages its own scrolling (e.g. it already contains a list).
  final bool scrollable;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final actionColor = destructive ? scheme.error : scheme.primary;

    // Structure mirrors the confirm dialog (_AppDialogCard), which lays out
    // reliably: let the framework [Dialog] supply the width (via its own
    // ConstrainedBox), and keep the content in a MainAxisSize.min Column.
    //
    // The body is height-capped and scrolls if it would overflow. It is NOT
    // wrapped in a vertical scroll view unconditionally: doing so relaxes the
    // horizontal constraint to unbounded and breaks any Row/Expanded in the
    // body ("BoxConstraints forces an infinite width"). Instead the whole
    // Column scrolls as one unit inside a bounded-height viewport, so every
    // child keeps the Dialog's tight width.
    final maxHeight = MediaQuery.of(context).size.height * 0.8;

    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: maxHeight),
        child: SingleChildScrollView(
          physics: const ClampingScrollPhysics(),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(child: AppText.titleText(context, title, fw: 2)),
                    const SizedBox(width: 8),
                    _DialogCloseButton(scheme: scheme),
                  ],
                ),
                const SizedBox(height: 12),
                Divider(height: 1, thickness: 1, color: scheme.outlineVariant),
                const SizedBox(height: 18),
                child,
                if (actionLabel != null) ...[
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
                      onPressed: (actionBusy || !actionEnabled)
                          ? null
                          : onAction,
                      child: actionBusy
                          ? const SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2.4,
                                color: Colors.white,
                              ),
                            )
                          : Text(actionLabel!),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _DialogCloseButton extends StatelessWidget {
  const _DialogCloseButton({required this.scheme});
  final ColorScheme scheme;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: scheme.onSurface.withValues(alpha: 0.06),
      shape: const CircleBorder(),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => Navigator.of(context).maybePop(),
        child: Padding(
          padding: const EdgeInsets.all(7),
          child: Icon(Icons.close, size: 18, color: scheme.onSurfaceVariant),
        ),
      ),
    );
  }
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
              AppText.titleText(
                context,
                title!,
                fw: 2,
                align: TextAlign.center,
              ),
              const SizedBox(height: 8),
            ],
            AppText.subText(
              context,
              message,
              align: TextAlign.center,
              color: scheme.onSurfaceVariant,
              lineHeight: 1.35,
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
