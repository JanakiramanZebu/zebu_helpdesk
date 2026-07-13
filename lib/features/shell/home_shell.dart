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

class _HomeShellState extends ConsumerState<HomeShell> {
  @override
  void initState() {
    super.initState();
    // Reaching the shell means we're authenticated: start push (permission
    // prompt + FCM token registration). No-ops if Firebase isn't configured.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(pushServiceProvider).start();
    });
  }

  void _go(int index) => widget.shell.goBranch(
    index,
    initialLocation: index == widget.shell.currentIndex,
  );

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
