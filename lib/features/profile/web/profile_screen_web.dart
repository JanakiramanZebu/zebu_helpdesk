import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_exception.dart';
import '../../../models/me.dart';
import '../../../providers.dart';
import '../../../widgets/app_toast.dart';
import '../../../widgets/states.dart';
import '../../../widgets/user_avatar.dart';
import '../../../res/zebu_text_styles.dart';
import '../../../res/zebu_theme.dart';
import '../../../res/zebu_spacing.dart';

const _kFlatRadius = 8.0;

/// Opens the web profile as a centered modal dialog. Preferred entry point
/// on web — the profile is not a routed screen anymore; every call site
/// (sidebar avatar, More card, top-bar popover) funnels through this so
/// there's a single presentation.
Future<void> showProfileDialog(BuildContext context) {
  return showDialog<void>(
    context: context,
    barrierDismissible: true,
    builder: (_) => const ProfileScreenWeb(),
  );
}

/// Web-only profile view rendered as a centered modal [Dialog]. Same data
/// source as the mobile [ProfileScreen] (`meProvider`,
/// `meRepositoryProvider`) — only the shell is swapped for the Zebu
/// Premium web spec: identity card, availability toggle row, action rows,
/// and edit/password flows rendered as nested centered dialogs instead of
/// mobile bottom sheets. Always invoked via [showProfileDialog].
class ProfileScreenWeb extends ConsumerStatefulWidget {
  const ProfileScreenWeb({super.key});

  @override
  ConsumerState<ProfileScreenWeb> createState() => _ProfileScreenWebState();
}

class _ProfileScreenWebState extends ConsumerState<ProfileScreenWeb> {
  bool _busy = false;

  void _toast(String msg, {ToastType type = ToastType.info}) =>
      AppToast.show(context, msg, type: type);

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

  Future<void> _rerollAvatar() async {
    setState(() => _busy = true);
    try {
      await ref.read(meRepositoryProvider).rerollAvatar();
      ref.invalidate(meProvider);
      if (mounted) _toast('Avatar regenerated', type: ToastType.success);
    } on ApiException catch (e) {
      _toast(e.message, type: ToastType.error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _editProfile(Me me) async {
    final saved = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _EditProfileDialog(profile: me.profile, email: me.email),
    );
    if (saved == true) {
      ref.invalidate(meProvider);
      if (mounted) _toast('Profile updated', type: ToastType.success);
    }
  }

  Future<void> _changePassword() async {
    final changed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const _ChangePasswordDialog(),
    );
    if (changed == true && mounted)
      _toast('Password changed', type: ToastType.success);
  }

  @override
  Widget build(BuildContext context) {
    final t = ZebuTheme.of(context);
    final me = ref.watch(meProvider);
    return Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      insetPadding: const EdgeInsets.all(40),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 960, maxHeight: 780),
        child: Container(
          clipBehavior: Clip.hardEdge,
          decoration: BoxDecoration(
            color: t.bgElevated,
            border: Border.all(color: t.borderSubtle, width: 1),
            borderRadius: BorderRadius.circular(ZebuRadius.rMd),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _DialogHeader(
                title: 'Profile',
                onClose: () => Navigator.of(context).pop(),
              ),
              if (_busy) const LinearProgressIndicator(minHeight: 2),
              Flexible(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(
                    ZebuSpacing.s5,
                    ZebuSpacing.s4,
                    ZebuSpacing.s5,
                    ZebuSpacing.s5,
                  ),
                  child: me.when(
                    loading: () =>
                        const SizedBox(height: 240, child: LoadingView()),
                    error: (e, _) => SizedBox(
                      height: 240,
                      child: ErrorView(
                        error: e,
                        onRetry: () => ref.invalidate(meProvider),
                      ),
                    ),
                    data: (m) => _content(m),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _content(Me m) {
    return SingleChildScrollView(
      child: LayoutBuilder(
        builder: (context, cons) {
          final identity = _IdentityCard(me: m, dept: m.primaryDepartment);
          final account = _AccountSection(
            me: m,
            busy: _busy,
            onAvailability: _setAvailability,
            onEditProfile: () => _editProfile(m),
            onChangePassword: _changePassword,
            onRegenerateAvatar: _rerollAvatar,
          );
          // Below ~880 px the two columns get cramped — stack them so both
          // cards still get a full-width identity/account strip.
          if (cons.maxWidth < 880) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                identity,
                const SizedBox(height: ZebuSpacing.s4),
                account,
              ],
            );
          }
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(flex: 2, child: identity),
              const SizedBox(width: ZebuSpacing.s4),
              Expanded(flex: 3, child: account),
            ],
          );
        },
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Account section — section label + bordered card of settings rows
// ---------------------------------------------------------------------------

class _AccountSection extends StatelessWidget {
  const _AccountSection({
    required this.me,
    required this.busy,
    required this.onAvailability,
    required this.onEditProfile,
    required this.onChangePassword,
    required this.onRegenerateAvatar,
  });

  final Me me;
  final bool busy;
  final ValueChanged<bool> onAvailability;
  final VoidCallback onEditProfile;
  final VoidCallback onChangePassword;
  final VoidCallback onRegenerateAvatar;

  @override
  Widget build(BuildContext context) {
    final t = ZebuTheme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.only(
            left: ZebuSpacing.s1,
            bottom: ZebuSpacing.s2,
          ),
          child: const _SectionTitle('Account'),
        ),
        Container(
          clipBehavior: Clip.hardEdge,
          decoration: BoxDecoration(
            color: t.bgElevated,
            border: Border.all(color: t.borderSubtle, width: 1),
            borderRadius: BorderRadius.circular(_kFlatRadius),
          ),
          child: Column(
            children: [
              _AvailabilityRow(
                value: me.available,
                onChanged: busy ? null : onAvailability,
              ),
              _ActionRow(
                icon: Icons.edit_outlined,
                label: 'Edit profile',
                onTap: busy ? null : onEditProfile,
              ),
              _ActionRow(
                icon: Icons.lock_outline,
                label: 'Change password',
                onTap: busy ? null : onChangePassword,
              ),
              _ActionRow(
                icon: Icons.refresh,
                label: 'Regenerate avatar',
                onTap: busy ? null : onRegenerateAvatar,
                last: true,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Identity card — avatar + name + username/email + department
// ---------------------------------------------------------------------------

class _IdentityCard extends StatelessWidget {
  const _IdentityCard({required this.me, required this.dept});
  final Me me;
  final NamedDeptRole? dept;

  @override
  Widget build(BuildContext context) {
    final t = ZebuTheme.of(context);
    final phone = me.profile.phone ?? '';
    final mobile = me.profile.mobile ?? '';
    final timezone = me.profile.timezone ?? '';
    return Container(
      padding: const EdgeInsets.all(ZebuSpacing.s5),
      decoration: BoxDecoration(
        color: t.bgElevated,
        border: Border.all(color: t.borderSubtle, width: 1),
        borderRadius: BorderRadius.circular(_kFlatRadius),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              UserAvatar(name: me.name, radius: 28),
              const SizedBox(width: ZebuSpacing.s3),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      me.name,
                      style: ZebuTextStyles.pageTitle(context),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '@${me.username}',
                      style: ZebuTextStyles.small(
                        context,
                      ).copyWith(fontWeight: FontWeight.w500),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (dept != null) ...[
            const SizedBox(height: ZebuSpacing.s3),
            Align(
              alignment: Alignment.centerLeft,
              child: _Tag(
                label: dept!.roleName != null && dept!.roleName!.isNotEmpty
                    ? '${dept!.name.toUpperCase()} · ${dept!.roleName!.toUpperCase()}'
                    : dept!.name.toUpperCase(),
              ),
            ),
          ],
          const SizedBox(height: ZebuSpacing.s4),
          Divider(color: t.borderSubtle, height: 1),
          const SizedBox(height: ZebuSpacing.s3),
          _InfoRow(icon: Icons.mail_outline, label: 'Email', value: me.email),
          if (phone.isNotEmpty)
            _InfoRow(icon: Icons.phone_outlined, label: 'Phone', value: phone),
          if (mobile.isNotEmpty)
            _InfoRow(
              icon: Icons.smartphone_outlined,
              label: 'Mobile',
              value: mobile,
            ),
          if (timezone.isNotEmpty)
            _InfoRow(icon: Icons.public, label: 'Timezone', value: timezone),
        ],
      ),
    );
  }
}

/// Read-only key/value row inside the identity card.
class _InfoRow extends StatelessWidget {
  const _InfoRow({
    required this.icon,
    required this.label,
    required this.value,
  });
  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final t = ZebuTheme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Icon(icon, size: 16, color: t.textSecondary),
          const SizedBox(width: ZebuSpacing.s2),
          SizedBox(
            width: 72,
            child: Text(label, style: ZebuTextStyles.small(context)),
          ),
          Expanded(
            child: Text(
              value,
              style: ZebuTextStyles.small(
                context,
              ).copyWith(color: t.textPrimary, fontWeight: FontWeight.w500),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

class _Tag extends StatelessWidget {
  const _Tag({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    final t = ZebuTheme.of(context);
    return Text(
      label,
      style: ZebuTextStyles.label(context).copyWith(color: t.textSecondary),
    );
  }
}

// ---------------------------------------------------------------------------
// Availability toggle row (inside the Account card)
// ---------------------------------------------------------------------------

class _AvailabilityRow extends StatelessWidget {
  const _AvailabilityRow({required this.value, required this.onChanged});
  final bool value;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    final t = ZebuTheme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: ZebuSpacing.s4,
        vertical: ZebuSpacing.s3,
      ),
      decoration: BoxDecoration(
        color: t.bgElevated,
        border: Border(bottom: BorderSide(color: t.borderSubtle, width: 1)),
      ),
      child: Row(
        children: [
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(
              color: value ? ZebuTheme.success : t.textSecondary,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: ZebuSpacing.s3),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Available',
                  style: ZebuTextStyles.body(
                    context,
                  ).copyWith(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 2),
                Text(
                  'Accept new ticket assignments',
                  style: ZebuTextStyles.small(context),
                ),
              ],
            ),
          ),
          Switch(
            value: value,
            activeThumbColor: t.accent,
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Clickable action row (Edit profile / Change password / Regenerate avatar)
// ---------------------------------------------------------------------------

class _ActionRow extends StatefulWidget {
  const _ActionRow({
    required this.icon,
    required this.label,
    required this.onTap,
    this.last = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final bool last;

  @override
  State<_ActionRow> createState() => _ActionRowState();
}

class _ActionRowState extends State<_ActionRow> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final t = ZebuTheme.of(context);
    final disabled = widget.onTap == null;
    return MouseRegion(
      cursor: disabled ? SystemMouseCursors.basic : SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 100),
          padding: const EdgeInsets.symmetric(
            horizontal: ZebuSpacing.s4,
            vertical: ZebuSpacing.s3,
          ),
          decoration: BoxDecoration(
            color: (_hover && !disabled) ? t.bgHover : t.bgElevated,
            border: widget.last
                ? null
                : Border(bottom: BorderSide(color: t.borderSubtle, width: 1)),
          ),
          child: Row(
            children: [
              Icon(widget.icon, size: 18, color: t.textSecondary),
              const SizedBox(width: ZebuSpacing.s3),
              Expanded(
                child: Text(
                  widget.label,
                  style: ZebuTextStyles.body(
                    context,
                  ).copyWith(fontWeight: FontWeight.w500),
                ),
              ),
              Icon(Icons.chevron_right, size: 18, color: t.textSecondary),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Section title
// ---------------------------------------------------------------------------

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.label);
  final String label;

  @override
  Widget build(BuildContext context) {
    return Text(label.toUpperCase(), style: ZebuTextStyles.eyebrow(context));
  }
}

// ---------------------------------------------------------------------------
// Shared button + icon primitives
// ---------------------------------------------------------------------------

class _IconBtn extends StatefulWidget {
  const _IconBtn({required this.icon, required this.onTap, this.tooltip});
  final IconData icon;
  final VoidCallback onTap;
  final String? tooltip;

  @override
  State<_IconBtn> createState() => _IconBtnState();
}

class _IconBtnState extends State<_IconBtn> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final t = ZebuTheme.of(context);
    final child = MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 100),
          width: 32,
          height: 32,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: _hover ? t.bgHover : t.bgTertiary,
            borderRadius: BorderRadius.circular(ZebuRadius.rSm),
          ),
          child: Icon(widget.icon, size: 16, color: t.textSecondary),
        ),
      ),
    );
    return widget.tooltip == null
        ? child
        : Tooltip(message: widget.tooltip!, child: child);
  }
}

class _SecondaryButton extends StatefulWidget {
  const _SecondaryButton({required this.label, required this.onTap});
  final String label;
  final VoidCallback onTap;

  @override
  State<_SecondaryButton> createState() => _SecondaryButtonState();
}

class _SecondaryButtonState extends State<_SecondaryButton> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final t = ZebuTheme.of(context);
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: ZebuSpacing.s4,
            vertical: 10,
          ),
          decoration: BoxDecoration(
            color: _hover ? t.bgHover : t.bgElevated,
            border: Border.all(color: t.borderDefault, width: 1),
            borderRadius: BorderRadius.circular(_kFlatRadius),
          ),
          child: Text(
            widget.label,
            style: ZebuTextStyles.small(
              context,
            ).copyWith(color: t.textPrimary, fontWeight: FontWeight.w600),
          ),
        ),
      ),
    );
  }
}

class _PrimaryButton extends StatefulWidget {
  const _PrimaryButton({required this.label, required this.onTap});
  final String label;
  final VoidCallback? onTap;

  @override
  State<_PrimaryButton> createState() => _PrimaryButtonState();
}

class _PrimaryButtonState extends State<_PrimaryButton> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    // Filled primary button keeps the Mynt brand blue in both modes.
    final disabled = widget.onTap == null;
    final effective = disabled
        ? ZebuTheme.accentLight.withValues(alpha: 0.4)
        : ZebuTheme.accentLight;
    return MouseRegion(
      cursor: disabled
          ? SystemMouseCursors.forbidden
          : SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 100),
          padding: const EdgeInsets.symmetric(
            horizontal: ZebuSpacing.s4,
            vertical: 10,
          ),
          decoration: BoxDecoration(
            color: _hover && !disabled
                ? Color.lerp(effective, Colors.black, 0.08)
                : effective,
            borderRadius: BorderRadius.circular(_kFlatRadius),
          ),
          child: Text(
            widget.label,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Labeled form field + text input primitives (shared by both dialogs)
// ---------------------------------------------------------------------------

class _LabeledField extends StatelessWidget {
  const _LabeledField({required this.label, required this.child, this.error});

  final String label;
  final Widget child;
  final String? error;

  @override
  Widget build(BuildContext context) {
    final t = ZebuTheme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: ZebuTextStyles.small(
            context,
          ).copyWith(color: t.textPrimary, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 6),
        child,
        if (error != null) ...[
          const SizedBox(height: 4),
          Text(
            error!,
            style: ZebuTextStyles.small(context).copyWith(color: t.danger),
          ),
        ],
      ],
    );
  }
}

class _TextInput extends StatelessWidget {
  const _TextInput({
    required this.controller,
    this.hint,
    this.minLines,
    this.maxLines = 1,
    this.obscureText = false,
    this.keyboardType,
    this.hasError = false,
  });

  final TextEditingController controller;
  final String? hint;
  final int? minLines;
  final int maxLines;
  final bool obscureText;
  final TextInputType? keyboardType;
  final bool hasError;

  @override
  Widget build(BuildContext context) {
    final t = ZebuTheme.of(context);
    final border = OutlineInputBorder(
      borderRadius: BorderRadius.circular(_kFlatRadius),
      borderSide: BorderSide(
        color: hasError ? t.danger : t.borderSubtle,
        width: 1,
      ),
    );
    final focusedBorder = OutlineInputBorder(
      borderRadius: BorderRadius.circular(_kFlatRadius),
      borderSide: BorderSide(color: hasError ? t.danger : t.accent, width: 1.4),
    );
    return TextField(
      controller: controller,
      minLines: minLines,
      maxLines: obscureText ? 1 : maxLines,
      obscureText: obscureText,
      keyboardType: keyboardType,
      style: ZebuTextStyles.body(context),
      decoration: InputDecoration(
        filled: true,
        fillColor: t.bgElevated,
        hoverColor: Colors.transparent,
        border: border,
        enabledBorder: border,
        focusedBorder: focusedBorder,
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: ZebuSpacing.s3,
          vertical: 12,
        ),
        hintText: hint,
        hintStyle: ZebuTextStyles.body(
          context,
        ).copyWith(color: t.textSecondary),
      ),
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message});
  final String message;

  @override
  Widget build(BuildContext context) {
    final t = ZebuTheme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: ZebuSpacing.s3,
        vertical: ZebuSpacing.s2,
      ),
      decoration: BoxDecoration(
        color: t.dangerLight,
        border: Border.all(color: t.danger, width: 1),
        borderRadius: BorderRadius.circular(_kFlatRadius),
      ),
      child: Row(
        children: [
          Icon(Icons.error_outline, size: 16, color: t.danger),
          const SizedBox(width: ZebuSpacing.s2),
          Expanded(
            child: Text(
              message,
              style: ZebuTextStyles.small(context).copyWith(color: t.danger),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Edit profile dialog
// ---------------------------------------------------------------------------

class _EditProfileDialog extends ConsumerStatefulWidget {
  const _EditProfileDialog({required this.profile, required this.email});
  final MeProfile profile;
  final String email;

  @override
  ConsumerState<_EditProfileDialog> createState() => _EditProfileDialogState();
}

class _EditProfileDialogState extends ConsumerState<_EditProfileDialog> {
  late final _firstname = TextEditingController(
    text: widget.profile.firstname ?? '',
  );
  late final _lastname = TextEditingController(
    text: widget.profile.lastname ?? '',
  );
  late final _email = TextEditingController(text: widget.email);
  late final _phone = TextEditingController(text: widget.profile.phone ?? '');
  late final _mobile = TextEditingController(text: widget.profile.mobile ?? '');
  late final _timezone = TextEditingController(
    text: widget.profile.timezone ?? '',
  );
  late final _signature = TextEditingController(
    text: widget.profile.signature ?? '',
  );

  bool _saving = false;
  Map<String, String> _fieldErrors = const {};
  String? _error;

  @override
  void dispose() {
    _firstname.dispose();
    _lastname.dispose();
    _email.dispose();
    _phone.dispose();
    _mobile.dispose();
    _timezone.dispose();
    _signature.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() {
      _saving = true;
      _error = null;
      _fieldErrors = const {};
    });
    try {
      await ref.read(meRepositoryProvider).updateMe({
        'firstname': _firstname.text.trim(),
        'lastname': _lastname.text.trim(),
        'email': _email.text.trim(),
        'phone': _phone.text.trim(),
        'mobile': _mobile.text.trim(),
        'timezone': _timezone.text.trim(),
        'signature': _signature.text,
      });
      if (mounted) Navigator.of(context).pop(true);
    } on ApiException catch (e) {
      setState(() {
        _error = e.fields.isEmpty ? e.message : null;
        _fieldErrors = e.fields;
      });
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = ZebuTheme.of(context);
    return Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      insetPadding: const EdgeInsets.all(40),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 640),
        child: Container(
          clipBehavior: Clip.hardEdge,
          decoration: BoxDecoration(
            color: t.bgElevated,
            border: Border.all(color: t.borderSubtle, width: 1),
            borderRadius: BorderRadius.circular(ZebuRadius.rMd),
          ),
          child: AbsorbPointer(
            absorbing: _saving,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _DialogHeader(
                  title: 'Edit profile',
                  onClose: () => Navigator.of(context).pop(false),
                ),
                if (_saving) const LinearProgressIndicator(minHeight: 2),
                Flexible(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(
                      ZebuSpacing.s5,
                      ZebuSpacing.s4,
                      ZebuSpacing.s5,
                      ZebuSpacing.s5,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (_error != null) ...[
                          _ErrorBanner(message: _error!),
                          const SizedBox(height: ZebuSpacing.s4),
                        ],
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: _LabeledField(
                                label: 'First name',
                                error: _fieldErrors['firstname'],
                                child: _TextInput(
                                  controller: _firstname,
                                  hasError: _fieldErrors['firstname'] != null,
                                ),
                              ),
                            ),
                            const SizedBox(width: ZebuSpacing.s3),
                            Expanded(
                              child: _LabeledField(
                                label: 'Last name',
                                error: _fieldErrors['lastname'],
                                child: _TextInput(
                                  controller: _lastname,
                                  hasError: _fieldErrors['lastname'] != null,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: ZebuSpacing.s3),
                        _LabeledField(
                          label: 'Email',
                          error: _fieldErrors['email'],
                          child: _TextInput(
                            controller: _email,
                            keyboardType: TextInputType.emailAddress,
                            hasError: _fieldErrors['email'] != null,
                          ),
                        ),
                        const SizedBox(height: ZebuSpacing.s3),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: _LabeledField(
                                label: 'Phone',
                                error: _fieldErrors['phone'],
                                child: _TextInput(
                                  controller: _phone,
                                  keyboardType: TextInputType.phone,
                                  hasError: _fieldErrors['phone'] != null,
                                ),
                              ),
                            ),
                            const SizedBox(width: ZebuSpacing.s3),
                            Expanded(
                              child: _LabeledField(
                                label: 'Mobile',
                                error: _fieldErrors['mobile'],
                                child: _TextInput(
                                  controller: _mobile,
                                  keyboardType: TextInputType.phone,
                                  hasError: _fieldErrors['mobile'] != null,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: ZebuSpacing.s3),
                        _LabeledField(
                          label: 'Timezone',
                          error: _fieldErrors['timezone'],
                          child: _TextInput(
                            controller: _timezone,
                            hint: 'e.g. Asia/Kolkata',
                            hasError: _fieldErrors['timezone'] != null,
                          ),
                        ),
                        const SizedBox(height: ZebuSpacing.s3),
                        _LabeledField(
                          label: 'Signature',
                          error: _fieldErrors['signature'],
                          child: _TextInput(
                            controller: _signature,
                            minLines: 3,
                            maxLines: 6,
                            hasError: _fieldErrors['signature'] != null,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                _DialogFooter(
                  onCancel: () => Navigator.of(context).pop(false),
                  primaryLabel: _saving ? 'Saving…' : 'Save',
                  onSubmit: _saving ? null : _save,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Change password dialog
// ---------------------------------------------------------------------------

class _ChangePasswordDialog extends ConsumerStatefulWidget {
  const _ChangePasswordDialog();

  @override
  ConsumerState<_ChangePasswordDialog> createState() =>
      _ChangePasswordDialogState();
}

class _ChangePasswordDialogState extends ConsumerState<_ChangePasswordDialog> {
  final _current = TextEditingController();
  final _next = TextEditingController();

  bool _saving = false;
  Map<String, String> _fieldErrors = const {};
  String? _error;

  @override
  void dispose() {
    _current.dispose();
    _next.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_current.text.isEmpty || _next.text.isEmpty) {
      setState(() => _error = 'Both fields are required');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
      _fieldErrors = const {};
    });
    try {
      await ref
          .read(meRepositoryProvider)
          .changePassword(
            currentPassword: _current.text,
            newPassword: _next.text,
          );
      if (mounted) Navigator.of(context).pop(true);
    } on ApiException catch (e) {
      setState(() {
        _error = e.fields.isEmpty ? e.message : null;
        _fieldErrors = e.fields;
      });
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = ZebuTheme.of(context);
    return Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      insetPadding: const EdgeInsets.all(40),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: Container(
          clipBehavior: Clip.hardEdge,
          decoration: BoxDecoration(
            color: t.bgElevated,
            border: Border.all(color: t.borderSubtle, width: 1),
            borderRadius: BorderRadius.circular(ZebuRadius.rMd),
          ),
          child: AbsorbPointer(
            absorbing: _saving,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _DialogHeader(
                  title: 'Change password',
                  onClose: () => Navigator.of(context).pop(false),
                ),
                if (_saving) const LinearProgressIndicator(minHeight: 2),
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    ZebuSpacing.s5,
                    ZebuSpacing.s4,
                    ZebuSpacing.s5,
                    ZebuSpacing.s5,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (_error != null) ...[
                        _ErrorBanner(message: _error!),
                        const SizedBox(height: ZebuSpacing.s4),
                      ],
                      _LabeledField(
                        label: 'Current password',
                        error:
                            _fieldErrors['current_password'] ??
                            _fieldErrors['password'],
                        child: _TextInput(
                          controller: _current,
                          obscureText: true,
                          hasError:
                              (_fieldErrors['current_password'] ??
                                  _fieldErrors['password']) !=
                              null,
                        ),
                      ),
                      const SizedBox(height: ZebuSpacing.s3),
                      _LabeledField(
                        label: 'New password',
                        error: _fieldErrors['new_password'],
                        child: _TextInput(
                          controller: _next,
                          obscureText: true,
                          hasError: _fieldErrors['new_password'] != null,
                        ),
                      ),
                    ],
                  ),
                ),
                _DialogFooter(
                  onCancel: () => Navigator.of(context).pop(false),
                  primaryLabel: _saving ? 'Updating…' : 'Update password',
                  onSubmit: _saving ? null : _save,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Shared dialog chrome (header + footer)
// ---------------------------------------------------------------------------

class _DialogHeader extends StatelessWidget {
  const _DialogHeader({required this.title, required this.onClose});
  final String title;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final t = ZebuTheme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: ZebuSpacing.s5,
        vertical: ZebuSpacing.s4,
      ),
      decoration: BoxDecoration(
        color: t.bgElevated,
        border: Border(bottom: BorderSide(color: t.borderSubtle, width: 1)),
      ),
      child: Row(
        children: [
          Text(title, style: ZebuTextStyles.hero(context)),
          const Spacer(),
          _IconBtn(icon: Icons.close, tooltip: 'Close', onTap: onClose),
        ],
      ),
    );
  }
}

class _DialogFooter extends StatelessWidget {
  const _DialogFooter({
    required this.onCancel,
    required this.primaryLabel,
    required this.onSubmit,
  });

  final VoidCallback onCancel;
  final String primaryLabel;
  final VoidCallback? onSubmit;

  @override
  Widget build(BuildContext context) {
    final t = ZebuTheme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: ZebuSpacing.s5,
        vertical: ZebuSpacing.s3,
      ),
      decoration: BoxDecoration(
        color: t.bgElevated,
        border: Border(top: BorderSide(color: t.borderSubtle, width: 1)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          _SecondaryButton(label: 'Cancel', onTap: onCancel),
          const SizedBox(width: ZebuSpacing.s2),
          _PrimaryButton(label: primaryLabel, onTap: onSubmit),
        ],
      ),
    );
  }
}
