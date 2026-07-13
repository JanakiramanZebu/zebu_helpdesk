import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/network/connectivity_service.dart';

/// App-wide "You're offline" strip. Wraps the whole app below the router so it
/// floats above every screen without each one having to opt in. Collapses to
/// zero height (animated) whenever connectivity is up or still resolving.
///
/// Insert once in `MaterialApp.builder` around the router's [child].
class OfflineBanner extends ConsumerWidget {
  const OfflineBanner({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Only show when we positively know we're offline (ignore loading/error).
    final offline = ref
        .watch(connectivityProvider)
        .maybeWhen(data: (online) => !online, orElse: () => false);

    return Material(
      type: MaterialType.transparency,
      child: Column(
        children: [
          _Bar(visible: offline),
          Expanded(child: child),
        ],
      ),
    );
  }
}

class _Bar extends StatelessWidget {
  const _Bar({required this.visible});

  final bool visible;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return AnimatedSize(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOut,
      alignment: Alignment.topCenter,
      child: visible
          ? SafeArea(
              bottom: false,
              child: Container(
                width: double.infinity,
                color: scheme.errorContainer,
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.wifi_off_rounded,
                      size: 16,
                      color: scheme.onErrorContainer,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'No internet connection',
                      style: TextStyle(
                        color: scheme.onErrorContainer,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            )
          : const SizedBox.shrink(),
    );
  }
}
