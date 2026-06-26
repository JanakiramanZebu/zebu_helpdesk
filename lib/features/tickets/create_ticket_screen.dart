import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/api/api_exception.dart';
import '../../core/router/routes.dart';
import '../../models/meta.dart';
import '../../models/user.dart';
import '../../providers.dart';
import '../../widgets/pickers.dart';

/// `POST /tickets` — create a ticket for an existing user.
class CreateTicketScreen extends ConsumerStatefulWidget {
  const CreateTicketScreen({super.key});

  @override
  ConsumerState<CreateTicketScreen> createState() => _CreateTicketScreenState();
}

class _CreateTicketScreenState extends ConsumerState<CreateTicketScreen> {
  final _subject = TextEditingController();
  final _message = TextEditingController();

  AppUser? _user;
  MetaItem? _topic;
  MetaItem? _department;
  MetaItem? _priority;

  bool _saving = false;
  Map<String, String> _fieldErrors = const {};
  String? _error;

  @override
  void dispose() {
    _subject.dispose();
    _message.dispose();
    super.dispose();
  }

  void _toast(String msg) => ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(msg)));

  Future<void> _submit() async {
    if (_user == null) {
      setState(() => _error = 'Pick a requester first');
      return;
    }
    if (_subject.text.trim().isEmpty || _message.text.trim().isEmpty) {
      setState(() => _error = 'Subject and message are required');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
      _fieldErrors = const {};
    });
    try {
      final ticket = await ref.read(ticketsRepositoryProvider).create({
        'user_id': _user!.id,
        'subject': _subject.text.trim(),
        'message': _message.text.trim(),
        if (_topic != null) 'topic_id': _topic!.id,
        if (_department != null) 'dept_id': _department!.id,
        if (_priority != null) 'priority_id': _priority!.id,
      });
      if (!mounted) return;
      _toast('Ticket #${ticket.number} created');
      // Replace this screen with the new ticket's detail.
      context.pushReplacement(Routes.ticket(ticket.id));
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
    return Scaffold(
      appBar: AppBar(title: const Text('New ticket')),
      body: SafeArea(
        child: AbsorbPointer(
          absorbing: _saving,
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              if (_saving) const LinearProgressIndicator(minHeight: 2),
              if (_error != null) ...[
                Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
                const SizedBox(height: 12),
              ],
              _PickerTile(
                icon: Icons.person_outline,
                label: 'Requester',
                value: _user?.name,
                hint: 'Required',
                error: _fieldErrors['user_id'],
                onTap: () async {
                  final u = await pickUser(context, ref);
                  if (u != null) setState(() => _user = u);
                },
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _subject,
                textInputAction: TextInputAction.next,
                decoration: InputDecoration(
                  labelText: 'Subject',
                  errorText: _fieldErrors['subject'],
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _message,
                minLines: 4,
                maxLines: 10,
                decoration: InputDecoration(
                  labelText: 'Message',
                  alignLabelWithHint: true,
                  errorText: _fieldErrors['message'],
                ),
              ),
              const SizedBox(height: 16),
              Text('Optional', style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: 8),
              _PickerTile(
                icon: Icons.topic_outlined,
                label: 'Help topic',
                value: _topic?.name,
                onTap: () async {
                  final m = await pickMeta(
                    context,
                    ref,
                    MetaKind.topics,
                    title: 'Help topic',
                  );
                  if (m != null) setState(() => _topic = m);
                },
              ),
              _PickerTile(
                icon: Icons.apartment_outlined,
                label: 'Department',
                value: _department?.name,
                onTap: () async {
                  final m = await pickMeta(
                    context,
                    ref,
                    MetaKind.departments,
                    title: 'Department',
                  );
                  if (m != null) setState(() => _department = m);
                },
              ),
              _PickerTile(
                icon: Icons.flag_outlined,
                label: 'Priority',
                value: _priority?.name,
                onTap: () async {
                  final m = await pickMeta(
                    context,
                    ref,
                    MetaKind.priorities,
                    title: 'Priority',
                  );
                  if (m != null) setState(() => _priority = m);
                },
              ),
              const SizedBox(height: 24),
              FilledButton(
                onPressed: _saving ? null : _submit,
                child: const Text('Create ticket'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A tappable row that shows a selected value (or a hint) — used for pickers.
class _PickerTile extends StatelessWidget {
  const _PickerTile({
    required this.icon,
    required this.label,
    required this.onTap,
    this.value,
    this.hint,
    this.error,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final String? value;
  final String? hint;
  final String? error;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(icon),
      title: Text(label),
      subtitle: Text(
        value ?? hint ?? 'Not set',
        style: TextStyle(
          color: error != null
              ? theme.colorScheme.error
              : value != null
              ? theme.colorScheme.onSurface
              : theme.colorScheme.onSurfaceVariant,
          fontWeight: value != null ? FontWeight.w600 : FontWeight.normal,
        ),
      ),
      trailing: const Icon(Icons.chevron_right),
      onTap: onTap,
    );
  }
}
