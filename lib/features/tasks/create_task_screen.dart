import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/api/api_exception.dart';
import '../../core/format.dart';
import '../../core/router/routes.dart';
import '../../models/meta.dart';
import '../../providers.dart';
import '../../widgets/pickers.dart';

/// `POST /tasks` — create a task.
class CreateTaskScreen extends ConsumerStatefulWidget {
  const CreateTaskScreen({super.key});

  @override
  ConsumerState<CreateTaskScreen> createState() => _CreateTaskScreenState();
}

class _CreateTaskScreenState extends ConsumerState<CreateTaskScreen> {
  final _title = TextEditingController();
  final _description = TextEditingController();

  MetaItem? _department;
  MetaItem? _priority;
  DateTime? _due;

  bool _saving = false;
  Map<String, String> _fieldErrors = const {};
  String? _error;

  @override
  void dispose() {
    _title.dispose();
    _description.dispose();
    super.dispose();
  }

  void _toast(String msg) => ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(msg)));

  Future<void> _submit() async {
    if (_department == null) {
      setState(() => _error = 'Pick a department first');
      return;
    }
    if (_title.text.trim().isEmpty || _description.text.trim().isEmpty) {
      setState(() => _error = 'Title and description are required');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
      _fieldErrors = const {};
    });
    try {
      final task = await ref.read(tasksRepositoryProvider).create({
        'dept_id': _department!.id,
        'title': _title.text.trim(),
        'description': _description.text.trim(),
        if (_priority != null) 'priority_id': _priority!.id,
        if (_due != null) 'duedate': Fmt.apiDateTime(_due!),
      });
      if (!mounted) return;
      _toast('Task #${task.number} created');
      context.pushReplacement(Routes.task(task.id));
    } on ApiException catch (e) {
      setState(() {
        _error = e.fields.isEmpty ? e.message : null;
        _fieldErrors = e.fields;
      });
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _pickDue() async {
    final now = DateTime.now();
    final date = await showDatePicker(
      context: context,
      initialDate: _due ?? now,
      firstDate: now.subtract(const Duration(days: 1)),
      lastDate: now.add(const Duration(days: 365 * 3)),
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_due ?? now),
    );
    setState(() {
      _due = DateTime(
        date.year,
        date.month,
        date.day,
        time?.hour ?? 17,
        time?.minute ?? 0,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('New task')),
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
              TextField(
                controller: _title,
                textInputAction: TextInputAction.next,
                decoration: InputDecoration(
                  labelText: 'Title',
                  errorText: _fieldErrors['title'],
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _description,
                minLines: 4,
                maxLines: 10,
                decoration: InputDecoration(
                  labelText: 'Description',
                  alignLabelWithHint: true,
                  errorText: _fieldErrors['description'],
                ),
              ),
              const SizedBox(height: 12),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.apartment_outlined),
                title: const Text('Department'),
                subtitle: Text(
                  _department?.name ?? 'Required',
                  style: TextStyle(
                    color: _fieldErrors['dept_id'] != null
                        ? Theme.of(context).colorScheme.error
                        : _department != null
                        ? Theme.of(context).colorScheme.onSurface
                        : Theme.of(context).colorScheme.onSurfaceVariant,
                    fontWeight: _department != null
                        ? FontWeight.w600
                        : FontWeight.normal,
                  ),
                ),
                trailing: const Icon(Icons.chevron_right),
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
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.flag_outlined),
                title: const Text('Priority'),
                subtitle: Text(_priority?.name ?? 'Optional'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () async {
                  final m = await pickMeta(
                    context,
                    ref,
                    MetaKind.taskPriorities,
                    title: 'Priority',
                  );
                  if (m != null) setState(() => _priority = m);
                },
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.event_outlined),
                title: const Text('Due date'),
                subtitle: Text(_due == null ? 'Optional' : Fmt.dateTime(_due)),
                trailing: _due == null
                    ? const Icon(Icons.chevron_right)
                    : IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () => setState(() => _due = null),
                      ),
                onTap: _pickDue,
              ),
              const SizedBox(height: 24),
              FilledButton(
                onPressed: _saving ? null : _submit,
                child: const Text('Create task'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
