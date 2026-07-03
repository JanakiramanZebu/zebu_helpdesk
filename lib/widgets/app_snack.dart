import 'package:flutter/material.dart';

import '../core/theme/app_text.dart';
import '../core/theme/app_theme.dart';

/// Semantic kind of an [AppSnack] message, driving its accent color and icon.
enum _SnackKind { success, error, info }

/// App-branded SnackBars.
///
/// Floating, rounded, and on-surface (not the default dark inverse bar), with a
/// colored leading icon + accent stripe per semantic kind:
/// green for [success], red for [error], brand blue for [info]. All text uses
/// the Inter [AppText] system.
///
/// Usage:
/// ```dart
/// AppSnack.success(context, 'Ticket updated');
/// AppSnack.error(context, e.message);
/// AppSnack.info(context, 'Nothing to export');
/// ```
class AppSnack {
  AppSnack._();

  static void success(BuildContext context, String message) =>
      _show(context, message, _SnackKind.success);

  static void error(BuildContext context, String message) =>
      _show(context, message, _SnackKind.error);

  static void info(BuildContext context, String message) =>
      _show(context, message, _SnackKind.info);

  static void _show(BuildContext context, String message, _SnackKind kind) {
    final scheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final (accent, icon) = switch (kind) {
      _SnackKind.success => (AppTheme.open, Icons.check_circle_rounded),
      _SnackKind.error => (scheme.error, Icons.error_rounded),
      _SnackKind.info => (scheme.primary, Icons.info_rounded),
    };

    // Surface-toned bar with a subtle accent-tinted fill so it reads as
    // on-brand rather than a flat dark toast.
    final bg = Color.alphaBlend(
      accent.withValues(alpha: isDark ? 0.16 : 0.08),
      scheme.surface,
    );

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Row(
            children: [
              // Accent stripe + icon.
              Container(
                width: 4,
                height: 34,
                decoration: BoxDecoration(
                  color: accent,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
              const SizedBox(width: 12),
              Icon(icon, color: accent, size: 22),
              const SizedBox(width: 12),
              Expanded(
                child: AppText.subText(
                  context,
                  message,
                  color: scheme.onSurface,
                  fw: 0,
                  maxLines: 4,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          backgroundColor: bg,
          behavior: SnackBarBehavior.floating,
          elevation: 6,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
            side: BorderSide(color: accent.withValues(alpha: 0.35)),
          ),
          duration: Duration(seconds: kind == _SnackKind.error ? 5 : 3),
        ),
      );
  }
}
