import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/update/update_sheet.dart';
import '../router/app_router.dart';
import 'update_service.dart';

/// Watches for a newer native build and raises [UpdateSheet] over the app.
///
/// Mounted once, around the whole app. It renders nothing itself — [child] is
/// passed straight through — so it can sit in the `MaterialApp.builder` chain
/// without affecting layout.
///
/// Re-checks whenever the app returns to the foreground, so publishing a new
/// build in Strapi reaches staff who leave the app resident for days without
/// waiting for a cold start.
class UpdateGate extends ConsumerStatefulWidget {
  const UpdateGate({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<UpdateGate> createState() => _UpdateGateState();
}

class _UpdateGateState extends ConsumerState<UpdateGate>
    with WidgetsBindingObserver {
  /// True while a sheet is up, so a resume event can't stack a second one.
  bool _showing = false;

  /// Optional prompts are shown once per app session — dismissing with "Later"
  /// should stay dismissed until the next launch, not reappear on every
  /// resume. Forced updates ignore this and re-prompt every time.
  bool _dismissed = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) => _check());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) return;
    // Drop the cached result so the CMS is consulted again.
    ref.invalidate(updateCheckProvider);
    _check();
  }

  Future<void> _check() async {
    if (_showing) return;

    final info = await ref.read(updateCheckProvider.future);
    if (info == null || !mounted || _showing) return;
    if (_dismissed && !info.force) return;

    // Present on the root navigator: the sheet must outrank the current tab,
    // any pushed detail route, and the login screen.
    final navContext = rootNavigatorKey.currentContext;
    if (navContext == null || !navContext.mounted) return;

    _showing = true;
    try {
      await showUpdateSheet(navContext, info);
      // Returning here means it was dismissed, which only optional updates
      // allow — a forced sheet has no dismiss path.
      _dismissed = true;
    } finally {
      _showing = false;
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
