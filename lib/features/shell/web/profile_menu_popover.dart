import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/api/api_exception.dart';
import '../../../core/assets.dart';
import '../../../core/router/routes.dart';
import '../../../models/me.dart';
import '../../../providers.dart';
import '../../../widgets/app_dialog.dart';
import '../../../widgets/app_toast.dart';
import '../../../widgets/user_avatar.dart';
import '../../../widgets/web/menu_section.dart';
import '../../dashboard/web/_tokens.dart';
import '../../profile/web/profile_screen_web.dart';

const _kMenuWidth = 288.0;

/// Opens a ClickUp-style categorized profile popover anchored under
/// [anchorContext].
///
/// Layout:
///   * Header block — avatar + name + email + a subtle "Available/Away" dot;
///   * Pinned Availability toggle row (no section eyebrow — it's a status
///     switch, treated the same way ClickUp's "Set status" is);
///   * "Account" section — Profile;
///   * "Session" section — Log out (destructive).
///
/// Positioning:
///   * Right-aligned to the anchor's right edge (so it sits under the avatar
///     button in the top bar without spilling off-screen);
///   * Vertically clamped inside the viewport with an 8 px margin so the
///     popover never crosses the bottom edge.
///
/// Dismisses on outside tap or Escape (via the Overlay barrier).
Future<void> showProfileMenu(BuildContext anchorContext) async {
  final box = anchorContext.findRenderObject();
  if (box is! RenderBox || !box.attached) return;
  final overlayState = Overlay.of(anchorContext);
  final overlayBox = overlayState.context.findRenderObject()! as RenderBox;
  final anchorTopLeft = box.localToGlobal(Offset.zero, ancestor: overlayBox);
  final anchorSize = box.size;
  final viewport = overlayBox.size;

  final menuLeft = (anchorTopLeft.dx + anchorSize.width - _kMenuWidth)
      .clamp(8.0, (viewport.width - _kMenuWidth - 8.0).clamp(8.0, viewport.width));
  final menuTop = anchorTopLeft.dy + anchorSize.height + 8;

  final completer = Completer<void>();
  late OverlayEntry entry;

  void dismiss() {
    if (completer.isCompleted) return;
    completer.complete();
    entry.remove();
  }

  entry = OverlayEntry(
    builder: (ctx) {
      final t = WebTokens.of(ctx);
      return Stack(
        children: [
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: dismiss,
              child: const SizedBox.expand(),
            ),
          ),
          Positioned(
            left: menuLeft,
            top: menuTop,
            width: _kMenuWidth,
            child: Container(
              decoration: t.cardElevated(),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(WebTokens.rLg),
                child: Material(
                  color: Colors.transparent,
                  child: _ProfileMenuContent(onDismiss: dismiss),
                ),
              ),
            ),
          ),
        ],
      );
    },
  );

  overlayState.insert(entry);
  return completer.future;
}

class _ProfileMenuContent extends ConsumerStatefulWidget {
  const _ProfileMenuContent({required this.onDismiss});
  final VoidCallback onDismiss;

  @override
  ConsumerState<_ProfileMenuContent> createState() =>
      _ProfileMenuContentState();
}

class _ProfileMenuContentState extends ConsumerState<_ProfileMenuContent> {
  bool _busy = false;

  Future<void> _setAvailability(bool value) async {
    setState(() => _busy = true);
    try {
      await ref.read(meRepositoryProvider).setAvailability(available: value);
      ref.invalidate(meProvider);
    } on ApiException catch (e) {
      _toast(e.message, type: ToastType.error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _toast(String msg, {ToastType type = ToastType.info}) =>
      AppToast.show(context, msg, type: type);

  Future<void> _openProfile() async {
    // Capture the root Navigator's context BEFORE dismissing — `onDismiss`
    // removes the popover's OverlayEntry, which unmounts this widget and
    // invalidates `context`. The root Navigator's context stays valid because
    // it lives above the popover, so we can still open the profile dialog.
    final navigatorContext =
        Navigator.of(context, rootNavigator: true).context;
    widget.onDismiss();
    await showProfileDialog(navigatorContext);
  }

  Future<void> _logout() async {
    // Capture router + auth notifier + root Navigator context BEFORE
    // dismissing. The popover lives in an OverlayEntry that we tear down
    // immediately, so `context.mounted` flips to false during the async
    // gap — capturing here keeps the references valid across the confirm
    // dialog and the logout call.
    final router = GoRouter.of(context);
    final auth = ref.read(authControllerProvider.notifier);
    final navigatorContext =
        Navigator.of(context, rootNavigator: true).context;

    // Dismiss the popover first so the confirm dialog appears on the
    // clean page bg (matches how `_openProfile` sequences it). Then show
    // the same confirmation prompt the More-screen Sign out uses so the
    // two entry points feel consistent.
    widget.onDismiss();
    final ok = await showAppConfirmDialog(
      navigatorContext,
      title: 'Sign out?',
      message: 'You will need to sign in again to continue.',
      confirmLabel: 'Sign out',
      destructive: true,
    );
    if (ok != true) return;
    await auth.logout();
    router.go(Routes.login);
  }

  @override
  Widget build(BuildContext context) {
    final me = ref.watch(meProvider);
    return me.maybeWhen(
      data: (m) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Header(me: m),
          _SectionDivider(),
          _AvailabilityRow(
            value: m.available,
            onChanged: _busy ? null : _setAvailability,
          ),
          _SectionDivider(),
          MenuSection(
            title: 'Account',
            showDivider: false,
            children: [
              MenuRow(
                svg: Assets.profileEdit,
                label: 'Profile',
                onTap: _openProfile,
              ),
            ],
          ),
          _SectionDivider(),
          MenuSection(
            title: 'Session',
            showDivider: false,
            children: [
              MenuRow(
                icon: Icons.logout_rounded,
                label: 'Log out',
                destructive: true,
                onTap: _logout,
              ),
            ],
          ),
          const SizedBox(height: 6),
        ],
      ),
      orElse: () => const Padding(
        padding: EdgeInsets.all(24),
        child: Center(
          child: SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      ),
    );
  }
}

/// Header block. Includes a small status dot next to the name so the current
/// availability is legible before the user even reads the toggle below.
class _Header extends StatelessWidget {
  const _Header({required this.me});
  final Me me;

  @override
  Widget build(BuildContext context) {
    final t = WebTokens.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
      child: Row(
        children: [
          UserAvatar(name: me.name, radius: 20),
          const SizedBox(width: WebTokens.s3),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        me.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: t.cardNameLg,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color:
                            me.available ? WebTokens.success : t.textSecondary,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  me.email,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: t.bodySm,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _AvailabilityRow extends StatefulWidget {
  const _AvailabilityRow({required this.value, required this.onChanged});
  final bool value;
  final ValueChanged<bool>? onChanged;

  @override
  State<_AvailabilityRow> createState() => _AvailabilityRowState();
}

class _AvailabilityRowState extends State<_AvailabilityRow> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final t = WebTokens.of(context);
    final disabled = widget.onChanged == null;
    return MouseRegion(
      cursor: disabled ? SystemMouseCursors.basic : SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: disabled ? null : () => widget.onChanged!(!widget.value),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 100),
          height: 36,
          margin: const EdgeInsets.symmetric(horizontal: 6),
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            color: (_hover && !disabled) ? t.bgHover : Colors.transparent,
            borderRadius: BorderRadius.circular(WebTokens.rSm),
          ),
          child: Row(
            children: [
              Icon(
                widget.value
                    ? Icons.radio_button_checked
                    : Icons.do_not_disturb_on_outlined,
                size: 16,
                color: widget.value ? WebTokens.success : t.textSecondary,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  widget.value ? 'Available' : 'Away',
                  style: t.bodyBase.copyWith(fontWeight: FontWeight.w500),
                ),
              ),
              // Compact Switch: sized down so it fits the 36 px row cleanly.
              Transform.scale(
                scale: 0.7,
                child: Switch(
                  value: widget.value,
                  activeThumbColor: t.accent,
                  onChanged: widget.onChanged,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Thin hairline used to separate the three menu regions. Kept as a helper
/// so the vertical rhythm (6px above / 6px below) is defined in one place.
class _SectionDivider extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final t = WebTokens.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Container(height: 1, color: t.borderSubtle),
    );
  }
}
