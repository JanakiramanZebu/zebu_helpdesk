import 'dart:async';

import 'package:flutter/material.dart';

import '../features/dashboard/web/_tokens.dart';

/// Semantic category for [AppToast]. Drives the accent color, icon, and
/// default title used by the toast card.
enum ToastType { success, error, info, warning }

/// A global toast/notification API — call [AppToast.show], [AppToast.success],
/// [AppToast.error], [AppToast.info], or [AppToast.warning] from anywhere with
/// a live [BuildContext]. Renders as an [OverlayEntry] pinned to the top-right
/// of the screen, so it does not depend on a [Scaffold] or [ScaffoldMessenger]
/// and works uniformly across every route.
///
/// Toasts stack vertically, auto-dismiss after 4 seconds, and can be closed
/// manually via the trailing × button.
class AppToast {
  AppToast._();

  static final List<_ToastController> _stack = <_ToastController>[];

  static void success(BuildContext context, String message, {String? title}) =>
      show(context, message, type: ToastType.success, title: title);

  static void error(BuildContext context, String message, {String? title}) =>
      show(context, message, type: ToastType.error, title: title);

  static void info(BuildContext context, String message, {String? title}) =>
      show(context, message, type: ToastType.info, title: title);

  static void warning(BuildContext context, String message, {String? title}) =>
      show(context, message, type: ToastType.warning, title: title);

  /// Show a toast. [type] defaults to [ToastType.info]. Pass [title] to
  /// override the default heading (e.g. "Success", "Error").
  static void show(
    BuildContext context,
    String message, {
    ToastType type = ToastType.info,
    String? title,
    Duration duration = const Duration(seconds: 4),
  }) {
    final overlay = Overlay.maybeOf(context, rootOverlay: true);
    if (overlay == null) return;

    late _ToastController controller;
    final entry = OverlayEntry(
      builder: (ctx) => _ToastStack(controller: controller),
    );
    controller = _ToastController(
      entry: entry,
      type: type,
      title: title ?? _defaultTitle(type),
      message: message,
      duration: duration,
      onDismissed: () {
        _stack.remove(controller);
        entry.remove();
      },
    );
    _stack.add(controller);
    overlay.insert(entry);
    controller.start();
  }

  static String _defaultTitle(ToastType type) => switch (type) {
    ToastType.success => 'Success',
    ToastType.error => 'Error',
    ToastType.warning => 'Warning',
    ToastType.info => 'Info',
  };
}

class _ToastController extends ChangeNotifier {
  _ToastController({
    required this.entry,
    required this.type,
    required this.title,
    required this.message,
    required this.duration,
    required this.onDismissed,
  });

  final OverlayEntry entry;
  final ToastType type;
  final String title;
  final String message;
  final Duration duration;
  final VoidCallback onDismissed;

  bool visible = false;
  Timer? _autoDismiss;

  void start() {
    // Trigger the enter animation on the next frame.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      visible = true;
      notifyListeners();
    });
    _autoDismiss = Timer(duration, dismiss);
  }

  void dismiss() {
    _autoDismiss?.cancel();
    _autoDismiss = null;
    if (!visible) {
      onDismissed();
      return;
    }
    visible = false;
    notifyListeners();
  }

  @override
  void dispose() {
    _autoDismiss?.cancel();
    super.dispose();
  }
}

class _ToastStack extends StatefulWidget {
  const _ToastStack({required this.controller});

  final _ToastController controller;

  @override
  State<_ToastStack> createState() => _ToastStackState();
}

class _ToastStackState extends State<_ToastStack> {
  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onChange);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onChange);
    super.dispose();
  }

  void _onChange() => setState(() {});

  int get _indexInStack {
    final i = AppToast._stack.indexOf(widget.controller);
    return i < 0 ? 0 : i;
  }

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    // Stack downward from just below the top edge — 16 px gap between toasts.
    final topOffset = mq.padding.top + 16 + (_indexInStack * 84.0);
    return Positioned(
      top: topOffset,
      right: 16,
      child: SafeArea(
        bottom: false,
        left: false,
        child: _ToastCard(controller: widget.controller),
      ),
    );
  }
}

class _ToastCard extends StatelessWidget {
  const _ToastCard({required this.controller});

  final _ToastController controller;

  @override
  Widget build(BuildContext context) {
    final t = WebTokens.of(context);
    final accent = _accentColor(controller.type, t);
    final visible = controller.visible;

    return AnimatedSlide(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
      offset: visible ? Offset.zero : const Offset(0.15, 0),
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 220),
        opacity: visible ? 1 : 0,
        onEnd: () {
          if (!visible) controller.onDismissed();
        },
        child: Material(
          color: Colors.transparent,
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              minWidth: 280,
              maxWidth: 380,
            ),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: t.bgElevated,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: t.borderSubtle, width: 1),
                boxShadow: WebTokens.shadowLg,
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: IntrinsicHeight(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Container(width: 3, color: accent),
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              _ToastIcon(type: controller.type, color: accent),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.start,
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      controller.title,
                                      style: t.cardNameLg.copyWith(
                                        color: accent,
                                        height: 1.2,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      controller.message,
                                      style: t.bodySm.copyWith(
                                        color: t.textPrimary,
                                        height: 1.35,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 8),
                              _CloseButton(
                                color: t.textSecondary,
                                onTap: controller.dismiss,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Color _accentColor(ToastType type, WebTokens t) => switch (type) {
    ToastType.success => WebTokens.success,
    ToastType.error => t.danger,
    ToastType.warning => WebTokens.warning,
    ToastType.info => t.accent,
  };
}

class _CloseButton extends StatelessWidget {
  const _CloseButton({required this.color, required this.onTap});

  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(2),
          child: Icon(Icons.close, size: 14, color: color),
        ),
      ),
    );
  }
}

class _ToastIcon extends StatelessWidget {
  const _ToastIcon({required this.type, required this.color});

  final ToastType type;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final icon = switch (type) {
      ToastType.success => Icons.check,
      ToastType.error => Icons.close,
      ToastType.warning => Icons.priority_high,
      ToastType.info => Icons.info_outline,
    };
    return Container(
      width: 22,
      height: 22,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      alignment: Alignment.center,
      child: Icon(icon, size: 14, color: Colors.white),
    );
  }
}
