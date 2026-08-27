import 'package:flutter/material.dart';

import '../core/api/api_exception.dart';
import '../core/theme/app_text.dart';

/// Makes a non-scrolling state view (an [EmptyView], [ErrorView] or
/// [LoadingView]) pullable underneath a [RefreshIndicator].
///
/// A `RefreshIndicator` only fires on an **overscroll**, and on Android the
/// default `ClampingScrollPhysics` produces none at all when the content fits
/// the viewport — so a centred empty state, or a list short enough to fit on
/// screen, silently swallows the gesture. Wrapping the state in a scrollable
/// that is forced to always accept a drag is what gives the pull something to
/// act on.
///
/// Use it for the states; for the populated list, pass
/// [alwaysScrollablePhysics] to the `ListView` itself.
class RefreshableState extends StatelessWidget {
  const RefreshableState({super.key, required this.child, this.minHeight = 360});

  final Widget child;

  /// Height reserved for the state view inside the scrollable, so it still
  /// reads as a centred empty/error panel rather than a squashed strip.
  final double minHeight;

  @override
  Widget build(BuildContext context) => ListView(
    physics: alwaysScrollablePhysics,
    children: [SizedBox(height: minHeight, child: child)],
  );
}

/// The physics every scrollable under a [RefreshIndicator] needs: a drag is
/// accepted even when there is nothing to scroll.
const alwaysScrollablePhysics = AlwaysScrollableScrollPhysics();

/// Centered loading spinner.
class LoadingView extends StatelessWidget {
  const LoadingView({super.key, this.message});
  final String? message;

  @override
  Widget build(BuildContext context) => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const CircularProgressIndicator(strokeWidth: 2.5),
        if (message != null) ...[
          const SizedBox(height: 12),
          AppText.subText(context, message!),
        ],
      ],
    ),
  );
}

/// Friendly error state with an optional retry.
///
/// Network/timeout failures ([ApiException.isNetworkError]) get a dedicated
/// "no connection" glyph and title so they read as a connectivity problem
/// rather than a generic app error. Set [compact] for a tighter layout when
/// shown inside a sheet or small panel.
class ErrorView extends StatelessWidget {
  const ErrorView({
    super.key,
    required this.error,
    this.onRetry,
    this.compact = false,
  });

  final Object error;
  final VoidCallback? onRetry;
  final bool compact;

  bool get _isNetwork =>
      error is ApiException && (error as ApiException).isNetworkError;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final message = error is ApiException
        ? (error as ApiException).message
        : 'Something went wrong.';

    final IconData icon = _isNetwork
        ? Icons.wifi_off_rounded
        : Icons.error_outline_rounded;
    final Color iconColor = _isNetwork ? scheme.onSurfaceVariant : scheme.error;
    final String? title = _isNetwork ? 'No connection' : null;

    final double iconSize = compact ? 40 : 48;

    return Center(
      child: Padding(
        padding: EdgeInsets.all(compact ? 20 : 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: EdgeInsets.all(compact ? 14 : 18),
              decoration: BoxDecoration(
                color: iconColor.withValues(alpha: 0.10),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: iconSize, color: iconColor),
            ),
            SizedBox(height: compact ? 12 : 16),
            if (title != null) ...[
              AppText.titleText(
                context,
                title,
                fw: 2,
                align: TextAlign.center,
              ),
              const SizedBox(height: 4),
            ],
            AppText.subText(
              context,
              message,
              color: scheme.onSurfaceVariant,
              align: TextAlign.center,
            ),
            if (onRetry != null) ...[
              SizedBox(height: compact ? 14 : 18),
              OutlinedButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh, size: 18),
                label: AppText.subText(context, 'Retry'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Empty-list placeholder.
class EmptyView extends StatelessWidget {
  const EmptyView({
    super.key,
    this.icon = Icons.inbox_outlined,
    required this.message,
    this.hint,
  });
  final IconData icon;
  final String message;
  final String? hint;

  @override
  Widget build(BuildContext context) {
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 48, color: muted),
            const SizedBox(height: 12),
            AppText.titleText(context, message, align: TextAlign.center),
            if (hint != null) ...[
              const SizedBox(height: 6),
              AppText.subText(
                context,
                hint!,
                color: muted,
                align: TextAlign.center,
              ),
            ],
          ],
        ),
      ),
    );
  }
}
