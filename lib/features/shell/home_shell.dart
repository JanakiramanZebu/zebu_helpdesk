import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'widgets/floating_nav_bar.dart';

/// Bottom-navigation shell hosting the 4 primary branches, with a floating
/// frosted-glass nav bar that the branch content scrolls behind.
class HomeShell extends StatelessWidget {
  const HomeShell({super.key, required this.shell});
  final StatefulNavigationShell shell;

  void _go(int index) =>
      shell.goBranch(index, initialLocation: index == shell.currentIndex);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBody: true,
      body: shell,
      bottomNavigationBar: FloatingNavBar(
        currentIndex: shell.currentIndex,
        onTap: _go,
      ),
    );
  }
}
