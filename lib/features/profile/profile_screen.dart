import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api_exception.dart';
import '../../models/me.dart';
import '../../providers.dart';
import '../../widgets/states.dart';
import '../../widgets/user_avatar.dart';

/// The authenticated agent's own profile & settings.
class ProfileScreen extends ConsumerStatefulWidget {
  const ProfileScreen({super.key});

  @override
  ConsumerState<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends ConsumerState<ProfileScreen> {
  bool _busy = false;

  void _toast(String msg) => ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(msg)));

  Future<void> _setAvailability(bool value) async {
    setState(() => _busy = true);
    try {
      await ref.read(meRepositoryProvider).setAvailability(available: value);
      ref.invalidate(meProvider);
    } on ApiException catch (e) {
      _toast(e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _rerollAvatar() async {
    setState(() => _busy = true);
    try {
      await ref.read(meRepositoryProvider).rerollAvatar();
      ref.invalidate(meProvider);
      if (mounted) _toast('Avatar regenerated');
    } on ApiException catch (e) {
      _toast(e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _editProfile(Me me) async {
    final saved = await showModalBottomSheet<bool>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _EditProfileSheet(profile: me.profile, email: me.email),
    );
    if (saved == true) {
      ref.invalidate(meProvider);
      if (mounted) _toast('Profile updated');
    }
  }

  Future<void> _changePassword() async {
    final changed = await showModalBottomSheet<bool>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => const _ChangePasswordSheet(),
    );
    if (changed == true && mounted) _toast('Password changed');
  }

  @override
  Widget build(BuildContext context) {
    final me = ref.watch(meProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Profile')),
      body: me.when(
        loading: () => const LoadingView(),
        error: (e, _) =>
            ErrorView(error: e, onRetry: () => ref.invalidate(meProvider)),
        data: (m) => _content(m),
      ),
    );
  }

  Widget _content(Me m) {
    final theme = Theme.of(context);
    final dept = m.primaryDepartment;
    return ListView(
      children: [
        if (_busy) const LinearProgressIndicator(minHeight: 2),
        const SizedBox(height: 16),
        Center(
          child: Column(
            children: [
              UserAvatar(name: m.name, radius: 44),
              const SizedBox(height: 12),
              Text(
                m.name,
                style:
                    theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 2),
              Text('@${m.username}', style: theme.textTheme.bodyMedium),
              const SizedBox(height: 2),
              Text(m.email, style: theme.textTheme.bodySmall),
              if (dept != null) ...[
                const SizedBox(height: 4),
                Text(
                  dept.roleName != null && dept.roleName!.isNotEmpty
                      ? '${dept.name} · ${dept.roleName}'
                      : dept.name,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 20),
        SwitchListTile(
          secondary: const Icon(Icons.circle, size: 14),
          title: const Text('Available'),
          subtitle: const Text('Accept new ticket assignments'),
          value: m.available,
          onChanged: _busy ? null : _setAvailability,
        ),
        const Divider(height: 8),
        ListTile(
          leading: const Icon(Icons.edit_outlined),
          title: const Text('Edit profile'),
          trailing: const Icon(Icons.chevron_right),
          onTap: _busy ? null : () => _editProfile(m),
        ),
        ListTile(
          leading: const Icon(Icons.lock_outline),
          title: const Text('Change password'),
          trailing: const Icon(Icons.chevron_right),
          onTap: _busy ? null : _changePassword,
        ),
        ListTile(
          leading: const Icon(Icons.refresh),
          title: const Text('Regenerate avatar'),
          trailing: const Icon(Icons.chevron_right),
          onTap: _busy ? null : _rerollAvatar,
        ),
        const SizedBox(height: 24),
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
  late final _firstname =
      TextEditingController(text: widget.profile.firstname ?? '');
  late final _lastname =
      TextEditingController(text: widget.profile.lastname ?? '');
  late final _email = TextEditingController(text: widget.email);
  late final _phone = TextEditingController(text: widget.profile.phone ?? '');
  late final _mobile = TextEditingController(text: widget.profile.mobile ?? '');
  late final _timezone =
      TextEditingController(text: widget.profile.timezone ?? '');
  late final _signature =
      TextEditingController(text: widget.profile.signature ?? '');

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
    final mq = MediaQuery.of(context);
    final insets = mq.viewInsets.bottom + mq.padding.bottom;
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 0, 16, 16 + insets),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Edit profile',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 12),
            if (_error != null) ...[
              Text(_error!,
                  style:
                      TextStyle(color: Theme.of(context).colorScheme.error)),
              const SizedBox(height: 8),
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
              decoration: InputDecoration(
                labelText: 'Phone',
                errorText: _fieldErrors['phone'],
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _mobile,
              keyboardType: TextInputType.phone,
              decoration: InputDecoration(
                labelText: 'Mobile',
                errorText: _fieldErrors['mobile'],
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _timezone,
              decoration: InputDecoration(
                labelText: 'Timezone',
                hintText: 'e.g. Asia/Kolkata',
                errorText: _fieldErrors['timezone'],
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _signature,
              minLines: 2,
              maxLines: 5,
              decoration: InputDecoration(
                labelText: 'Signature',
                alignLabelWithHint: true,
                errorText: _fieldErrors['signature'],
              ),
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: _saving ? null : _save,
              child: _saving
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(
                          strokeWidth: 2.4, color: Colors.white))
                  : const Text('Save'),
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
      await ref.read(meRepositoryProvider).changePassword(
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
    final mq = MediaQuery.of(context);
    final insets = mq.viewInsets.bottom + mq.padding.bottom;
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 0, 16, 16 + insets),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Change password',
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 12),
          if (_error != null) ...[
            Text(_error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error)),
            const SizedBox(height: 8),
          ],
          TextField(
            controller: _current,
            obscureText: true,
            decoration: InputDecoration(
              labelText: 'Current password',
              errorText:
                  _fieldErrors['current_password'] ?? _fieldErrors['password'],
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
          FilledButton(
            onPressed: _saving ? null : _save,
            child: _saving
                ? const SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(
                        strokeWidth: 2.4, color: Colors.white))
                : const Text('Update password'),
          ),
        ],
      ),
    );
  }
}
