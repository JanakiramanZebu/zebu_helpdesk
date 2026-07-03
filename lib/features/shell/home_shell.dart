import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../providers.dart';
import 'widgets/floating_nav_bar.dart';

/// Bottom-navigation shell hosting the 5 primary branches (Dashboard / Tickets
/// / Tasks / Alerts / More), with a floating frosted-glass nav bar that the
/// branch content scrolls behind. The Alerts item is badged with the unread
/// notification count.
class HomeShell extends ConsumerWidget {
  const HomeShell({super.key, required this.shell});
  final StatefulNavigationShell shell;

  void _go(int index) =>
      shell.goBranch(index, initialLocation: index == shell.currentIndex);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final unread = ref.watch(unreadCountProvider);

    return Scaffold(
      extendBody: true,
      body: shell,
      bottomNavigationBar: FloatingNavBar(
        currentIndex: shell.currentIndex,
        onTap: _go,
        notificationCount: unread.maybeWhen(data: (c) => c, orElse: () => 0),
      ),
    );
  }
}
