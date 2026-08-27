import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api_exception.dart';
import '../../core/assets.dart';
import '../../core/format.dart';
import '../../core/theme/app_text.dart';
import '../../core/timezones.dart';
import '../../core/validators.dart';
import '../../models/me.dart';
import '../../providers.dart';
import '../../widgets/app_snack.dart';
import '../../widgets/app_sheet.dart';
import '../../widgets/pickers.dart';
import '../../widgets/states.dart';
import '../../widgets/svg_icon.dart';
import '../../widgets/user_avatar.dart';

/// The authenticated agent's own profile & settings.
///
/// Mirrors the web profile dialog (`profile/web/profile_screen_web.dart`):
/// an identity card carrying the agent's contact details (email, phone,
/// mobile, timezone) followed by an "Account" card of settings rows. Same
/// data source (`meProvider` / `meRepositoryProvider`) — only the shell is
/// mobile-native: a routed screen with bottom sheets where the web uses a
/// modal dialog with nested dialogs.
class ProfileScreen extends ConsumerStatefulWidget {
  const ProfileScreen({super.key});

  @override
  ConsumerState<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends ConsumerState<ProfileScreen> {
  bool _busy = false;

  Future<void> _setAvailability(bool value) async {
    setState(() => _busy = true);
    try {
      await ref.read(meRepositoryProvider).setAvailability(available: value);
      ref.invalidate(meProvider);
    } on ApiException catch (e) {
      if (mounted) AppSnack.error(context, e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _editProfile(Me me) async {
    final saved = await showAppSheet<bool>(
      context: context,
      builder: (_) => _EditProfileSheet(profile: me.profile, email: me.email),
    );
    if (saved == true) {
      ref.invalidate(meProvider);
      if (mounted) AppSnack.success(context, 'Profile updated');
    }
  }

  Future<void> _changePassword() async {
    final changed = await showAppSheet<bool>(
      context: context,
      builder: (_) => const _ChangePasswordSheet(),
    );
    if (changed == true && mounted) {
      AppSnack.success(context, 'Password changed');
    }
  }

  @override
  Widget build(BuildContext context) {
    final me = ref.watch(meProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Profile')),
      body: SafeArea(
        child: me.when(
          loading: () => const LoadingView(),
          error: (e, _) =>
              ErrorView(error: e, onRetry: () => ref.invalidate(meProvider)),
          data: (m) => _content(m),
        ),
      ),
    );
  }

  Widget _content(Me m) {
    return ListView(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).padding.bottom + 24,
      ),
      children: [
        if (_busy) const LinearProgressIndicator(minHeight: 2),
        const SizedBox(height: 12),
        _IdentityCard(me: m),
        _Section(
          title: 'Account',
          children: [
            SwitchListTile(
              secondary: SvgIcon(
                Assets.profileAvailable,
                size: 22,
                color: m.available
                    ? const Color(0xFF00B14F)
                    : Theme.of(context).colorScheme.onSurfaceVariant,
              ),
              title: const Text('Available'),
              subtitle: const Text('Accept new ticket assignments'),
              value: m.available,
              onChanged: _busy ? null : _setAvailability,
            ),
            ListTile(
              leading: const SvgIcon(Assets.profileEdit, size: 22),
              title: const Text('Edit profile'),
              trailing: const Icon(Icons.chevron_right),
              onTap: _busy ? null : () => _editProfile(m),
            ),
            ListTile(
              leading: const SvgIcon(Assets.profilePassword, size: 22),
              title: const Text('Change password'),
              trailing: const Icon(Icons.chevron_right),
              onTap: _busy ? null : _changePassword,
            ),
          ],
        ),
      ],
    );
  }
}

// --- Identity card ----------------------------------------------------------

/// Avatar + name + username, the department/role caption, and the read-only
/// contact rows. Matches the web identity card: a detail only shows when the
/// profile actually carries it, so an agent with no phone on file sees no
/// empty row.
class _IdentityCard extends StatelessWidget {
  const _IdentityCard({required this.me});
  final Me me;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final dept = me.primaryDepartment;
    // osTicket echoes numbers back through its US formatter — see [Fmt.phone].
    final phone = Fmt.phone(me.profile.phone);
    final mobile = Fmt.phone(me.profile.mobile);
    final timezone = me.profile.timezone ?? '';
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                UserAvatar(name: me.name, radius: 28),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      AppText.titleText(
                        context,
                        me.name,
                        fw: 2,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      AppText.subText(
                        context,
                        '@${me.username}',
                        color: scheme.onSurfaceVariant,
                      ),
                    ],
                  ),
                ),
              ],
            ),
            if (dept != null) ...[
              const SizedBox(height: 12),
              AppText.captionText(
                context,
                dept.roleName != null && dept.roleName!.isNotEmpty
                    ? '${dept.name.toUpperCase()} · ${dept.roleName!.toUpperCase()}'
                    : dept.name.toUpperCase(),
                color: scheme.onSurfaceVariant,
                fw: 2,
              ),
            ],
            const SizedBox(height: 14),
            const Divider(height: 1),
            const SizedBox(height: 10),
            _InfoRow(icon: Icons.mail_outline, label: 'Email', value: me.email),
            if (phone.isNotEmpty)
              _InfoRow(
                icon: Icons.phone_outlined,
                label: 'Phone',
                value: phone,
              ),
            if (mobile.isNotEmpty)
              _InfoRow(
                icon: Icons.smartphone_outlined,
                label: 'Mobile',
                value: mobile,
              ),
            if (timezone.isNotEmpty)
              _InfoRow(
                icon: Icons.public,
                label: 'Timezone',
                value: timezone,
              ),
          ],
        ),
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
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Icon(icon, size: 18, color: scheme.onSurfaceVariant),
          const SizedBox(width: 10),
          SizedBox(
            width: 76,
            child: AppText.paraText(
              context,
              label,
              color: scheme.onSurfaceVariant,
            ),
          ),
          Expanded(
            child: AppText.paraText(
              context,
              value,
              fw: 0,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

/// Caption-caps heading over a card of rows — the same section treatment the
/// Menu tab uses, standing in for the web's bordered "Account" card.
class _Section extends StatelessWidget {
  const _Section({required this.title, required this.children});
  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 8),
          child: AppText.captionText(
            context,
            title.toUpperCase(),
            color: scheme.onSurfaceVariant,
            fw: 2,
          ),
        ),
        Card(
          margin: const EdgeInsets.symmetric(horizontal: 12),
          child: Column(
            children: [
              for (var i = 0; i < children.length; i++) ...[
                if (i != 0) const Divider(height: 1, indent: 60),
                children[i],
              ],
            ],
          ),
        ),
      ],
    );
  }
}

// --- Shared sheet pieces ----------------------------------------------------

/// Tinted, bordered banner for a form-level error — the sheet equivalent of the
/// web dialogs' error banner (a bare red line was easy to miss).
class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message});
  final String message;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: scheme.error.withValues(alpha: 0.10),
        border: Border.all(color: scheme.error.withValues(alpha: 0.4)),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Icon(Icons.error_outline, size: 18, color: scheme.error),
          const SizedBox(width: 10),
          Expanded(
            child: AppText.subText(context, message, color: scheme.error),
          ),
        ],
      ),
    );
  }
}

/// Cancel + primary action pair closing every profile sheet, matching the
/// web dialogs' footer.
class _SheetFooter extends StatelessWidget {
  const _SheetFooter({
    required this.primaryLabel,
    required this.onSubmit,
    required this.saving,
  });

  final String primaryLabel;
  final VoidCallback? onSubmit;
  final bool saving;

  @override
  Widget build(BuildContext context) {
    // Both buttons are [Expanded]: the app theme gives filled/outlined buttons
    // `Size.fromHeight(50)`, i.e. an *infinite* minimum width, so they may only
    // sit in a width-bounded parent — a bare Row child would be handed
    // unbounded width and blow up layout.
    return Row(
      children: [
        Expanded(
          child: OutlinedButton(
            onPressed: saving ? null : () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: FilledButton(
            onPressed: onSubmit,
            child: saving
                ? const SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.4,
                      color: Colors.white,
                    ),
                  )
                : Text(primaryLabel),
          ),
        ),
      ],
    );
  }
}

// --- Edit profile sheet -----------------------------------------------------

class _EditProfileSheet extends ConsumerStatefulWidget {
  const _EditProfileSheet({required this.profile, required this.email});
  final MeProfile profile;
  final String email;

  @override
  ConsumerState<_EditProfileSheet> createState() => _EditProfileSheetState();
}

class _EditProfileSheetState extends ConsumerState<_EditProfileSheet> {
  late final _firstname = TextEditingController(
    text: widget.profile.firstname ?? '',
  );
  late final _lastname = TextEditingController(
    text: widget.profile.lastname ?? '',
  );
  late final _email = TextEditingController(text: widget.email);
  // Seeded in the same Indian form the identity card shows, so editing a
  // number doesn't re-save the US shape osTicket handed back.
  late final _phone = TextEditingController(text: Fmt.phone(widget.profile.phone));
  late final _mobile = TextEditingController(
    text: Fmt.phone(widget.profile.mobile),
  );
  // Picked from [kTimezones], never typed — see the note on that list. Empty is
  // the web's "System Default" option.
  late String _timezone = widget.profile.timezone ?? kSystemDefaultTimezone;
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
    _signature.dispose();
    super.dispose();
  }

  /// Drops a field's error the moment its value changes, so a rejected number
  /// stops being flagged while it is being corrected.
  void _clearError(String field) {
    if (!_fieldErrors.containsKey(field)) return;
    setState(() => _fieldErrors = {..._fieldErrors}..remove(field));
  }

  /// The web renders this as a `<select>` over `DateTimeZone::listIdentifiers()`
  /// with a blank "System Default" row; the searchable sheet is the same list,
  /// and the same blank option, in the shape the app uses everywhere else.
  Future<void> _pickTimezone() async {
    final picked = await pickChoice(
      context,
      title: 'Timezone',
      choices: {
        kSystemDefaultTimezone: 'System default',
        for (final zone in kTimezones) zone: zone,
      },
      selectedValue: _timezone,
    );
    if (picked != null) setState(() => _timezone = picked);
  }

  Future<void> _save() async {
    final firstname = _firstname.text.trim();
    final lastname = _lastname.text.trim();
    final email = _email.text.trim();
    // Normalised before both the check and the request: a pasted number
    // carries a non-breaking space, which osTicket's own strip does not
    // remove, so sending it raw earns a server-side rejection of a number
    // that looks perfectly fine on screen.
    final phone = Validators.normalizePhone(_phone.text);
    final mobile = Validators.normalizePhone(_mobile.text);
    // `Validator::is_phone()` on each number that was actually typed — the rule
    // behind the web's "Valid phone number is required". Everything else on
    // this form (name required, email valid/unique) stays server-checked and
    // comes back as a field error, exactly as before.
    final errors = <String, String>{
      if (Validators.phone(phone) != null) 'phone': Validators.phone(phone)!,
      if (Validators.phone(mobile) != null)
        'mobile': Validators.phone(mobile)!,
    };
    if (errors.isNotEmpty) {
      setState(() {
        _error = null;
        _fieldErrors = errors;
      });
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
      _fieldErrors = const {};
    });
    try {
      await ref.read(meRepositoryProvider).updateMe({
        'firstname': firstname,
        'lastname': lastname,
        'email': email,
        'phone': phone,
        'mobile': mobile,
        'timezone': _timezone,
        'signature': _signature.text,
      });
      if (mounted) Navigator.pop(context, true);
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
    return AppSheet(
      title: 'Edit profile',
      // The save is in flight: the fields stay put until it lands, exactly as
      // the web dialog does.
      child: AbsorbPointer(
        absorbing: _saving,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (_error != null) ...[
              _ErrorBanner(message: _error!),
              const SizedBox(height: 12),
            ],
            TextField(
              controller: _firstname,
              decoration: InputDecoration(
                labelText: 'First name',
                errorText: _fieldErrors['firstname'],
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _lastname,
              decoration: InputDecoration(
                labelText: 'Last name',
                errorText: _fieldErrors['lastname'],
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _email,
              keyboardType: TextInputType.emailAddress,
              decoration: InputDecoration(
                labelText: 'Email',
                errorText: _fieldErrors['email'],
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _phone,
              keyboardType: TextInputType.phone,
              onChanged: (_) => _clearError('phone'),
              decoration: InputDecoration(
                labelText: 'Phone',
                errorText: _fieldErrors['phone'],
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _mobile,
              keyboardType: TextInputType.phone,
              onChanged: (_) => _clearError('mobile'),
              decoration: InputDecoration(
                labelText: 'Mobile',
                // osTicket accepts any 7-16 digit number once its punctuation
                // is stripped, so say that rather than let an agent guess at a
                // format that was never required.
                // helperText: '7–16 digits. Spaces, +, -, ( ) and . are fine.',
                errorText: _fieldErrors['mobile'],
              ),
            ),
            const SizedBox(height: 12),
            InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: _pickTimezone,
              child: InputDecorator(
                decoration: InputDecoration(
                  labelText: 'Timezone',
                  errorText: _fieldErrors['timezone'],
                  suffixIcon: const Icon(Icons.arrow_drop_down),
                ),
                child: AppText.subText(
                  context,
                  _timezone.isEmpty ? 'Asia/Kolkata' : _timezone,
                  color: _timezone.isEmpty
                      ? Theme.of(context).colorScheme.onSurfaceVariant
                      : Theme.of(context).colorScheme.onSurface,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _signature,
              minLines: 3,
              maxLines: 6,
              decoration: InputDecoration(
                labelText: 'Signature',
                alignLabelWithHint: true,
                errorText: _fieldErrors['signature'],
              ),
            ),
            const SizedBox(height: 16),
            _SheetFooter(
              primaryLabel: 'Save',
              saving: _saving,
              onSubmit: _saving ? null : _save,
            ),
          ],
        ),
      ),
    );
  }
}

// --- Change password sheet --------------------------------------------------

class _ChangePasswordSheet extends ConsumerStatefulWidget {
  const _ChangePasswordSheet();

  @override
  ConsumerState<_ChangePasswordSheet> createState() =>
      _ChangePasswordSheetState();
}

class _ChangePasswordSheetState extends ConsumerState<_ChangePasswordSheet> {
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
      if (mounted) Navigator.pop(context, true);
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
    return AppSheet(
      title: 'Change password',
      child: AbsorbPointer(
        absorbing: _saving,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (_error != null) ...[
              _ErrorBanner(message: _error!),
              const SizedBox(height: 12),
            ],
            TextField(
              controller: _current,
              obscureText: true,
              decoration: InputDecoration(
                labelText: 'Current password',
                errorText:
                    _fieldErrors['current_password'] ??
                    _fieldErrors['password'],
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _next,
              obscureText: true,
              decoration: InputDecoration(
                labelText: 'New password',
                errorText: _fieldErrors['new_password'],
              ),
            ),
            const SizedBox(height: 16),
            _SheetFooter(
              primaryLabel: 'Update password',
              saving: _saving,
              onSubmit: _saving ? null : _save,
            ),
          ],
        ),
      ),
    );
  }
}
