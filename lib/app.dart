import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/router/app_router.dart';
import 'core/theme/app_theme.dart';
import 'core/theme/theme_controller.dart';
import 'core/update/update_gate.dart';
import 'widgets/glass.dart';
import 'widgets/keyboard_dismisser.dart';
import 'widgets/offline_banner.dart';

class ZebuHelpdeskApp extends ConsumerWidget {
  const ZebuHelpdeskApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(routerProvider);
    final themeMode = ref.watch(themeModeProvider);
    return MaterialApp.router(
      title: 'Zebu Helpdesk',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: themeMode,
      routerConfig: router,
      // Dismiss the keyboard on any touch outside a focused field — see
      // [KeyboardDismisser], which listens for the raw pointer so taps that a
      // button, row or tab handles still put the keyboard away.
      builder: (context, child) {
        // The active theme (resolved from themeMode) decides the aurora
        // brightness: the whole app renders on the light or dark glass canvas
        // under the matching tint, so every screen — tabs and pushed detail
        // routes — shares one material and follows the theme toggle.
        final base = Theme.of(context);
        return KeyboardDismisser(
          child: Theme(
            data: Glass.tint(base),
            child: Glass.canvas(
              brightness: base.brightness,
              // Watches Strapi for a newer native build and raises the update
              // sheet over everything. Renders nothing of its own.
              child: UpdateGate(
                // App-wide offline strip floating above every screen.
                child: OfflineBanner(child: child ?? const SizedBox.shrink()),
              ),
            ),
          ),
        );
      },
    );
  }
}
