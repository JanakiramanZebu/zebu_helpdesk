import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/router/app_router.dart';
import 'core/theme/app_theme.dart';
import 'core/theme/theme_controller.dart';
import 'widgets/glass.dart';
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
      // Dismiss the keyboard when tapping anywhere outside a focused field.
      // Applied app-wide so every screen behaves consistently. Translucent hit
      // behavior lets buttons/list items still receive their taps.
      builder: (context, child) {
        // The active theme (resolved from themeMode) decides the aurora
        // brightness: the whole app renders on the light or dark glass canvas
        // under the matching tint, so every screen — tabs and pushed detail
        // routes — shares one material and follows the theme toggle.
        final base = Theme.of(context);
        return GestureDetector(
          behavior: HitTestBehavior.translucent,
          onTap: () => FocusManager.instance.primaryFocus?.unfocus(),
          child: Theme(
            data: Glass.tint(base),
            child: Glass.canvas(
              brightness: base.brightness,
              // App-wide offline strip floating above every screen.
              child: OfflineBanner(child: child ?? const SizedBox.shrink()),
            ),
          ),
        );
      },
    );
  }
}
