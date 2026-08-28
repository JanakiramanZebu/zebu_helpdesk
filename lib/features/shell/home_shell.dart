import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/router/routes.dart';
import '../../providers.dart';
import 'widgets/floating_nav_bar.dart';

/// Bottom-navigation shell hosting the 5 primary branches (Dashboard / Tickets
/// / Tasks / Alerts / More), with a floating frosted-glass nav bar that the
/// branch content scrolls behind. The Alerts item is badged with the unread
/// notification count.
class HomeShell extends ConsumerStatefulWidget {
  const HomeShell({super.key, required this.shell});
  final StatefulNavigationShell shell;

  @override
  ConsumerState<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends ConsumerState<HomeShell>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Reaching the shell means we're authenticated: start push (permission
    // prompt + FCM token registration). No-ops if Firebase isn't configured.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(pushServiceProvider).start();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// Alerts that land while the app is backgrounded are delivered to the system
  /// tray, not to `onMessage` — nothing in the running app hears about them. So
  /// on the way back to the foreground, refetch the badge and signal the Alerts
  /// list to reload; otherwise both keep showing the pre-push state until the
  /// user thinks to pull down.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) return;
    ref.invalidate(notificationCountsProvider);
    ref.read(notificationsChangedProvider.notifier).bump();
    // A denied-then-granted permission, or a token minted while we were away,
    // only takes effect if we try again.
    ref.read(pushServiceProvider).start();
  }

  /// Every tab tap opens that branch at its initial route *and* in its initial
  /// state: bumping the branch's epoch drops the screen's State (see
  /// [branchEpochProvider]), so Tickets/Tasks/Alerts come up unfiltered,
  /// unsearched, scrolled to the top and freshly loaded instead of resuming
  /// wherever the agent left off.
  void _go(int index) {
    ref.read(branchEpochProvider.notifier).bump(index);
    widget.shell.goBranch(index, initialLocation: true);
  }

  @override
  Widget build(BuildContext context) {
    final shell = widget.shell;
    final unread = ref.watch(unreadCountProvider);

    // The dark aurora canvas + glass tint are provided app-wide (see app.dart),
    // so the shell just needs a transparent Scaffold over it.
    return Scaffold(
      backgroundColor: Colors.transparent,
      extendBody: true,
      body: shell,
      bottomNavigationBar: FloatingNavBar(
        currentIndex: shell.currentIndex,
        onTap: _go,
        onCreateTicket: () => context.push(Routes.ticketNew),
        onCreateTask: () => context.push(Routes.taskNew),
        notificationCount: unread.maybeWhen(data: (c) => c, orElse: () => 0),
      ),
    );
  }
}
