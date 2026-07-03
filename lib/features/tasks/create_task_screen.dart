import 'package:dio/dio.dart';
import 'package:file_picker/file_picker.dart';
import 'package:fleather/fleather.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:parchment/codecs.dart';

import '../../core/api/api_exception.dart';
import '../../core/format.dart';
import '../../core/router/routes.dart';
import '../../core/theme/app_text.dart';
import '../../data/tasks_repository.dart';
import '../../models/meta.dart';
import '../../models/task.dart';
import '../../providers.dart';
import '../../widgets/app_sheet.dart';
import '../../widgets/app_snack.dart';
import '../../widgets/date_picker_sheet.dart';
import '../../widgets/pickers.dart';
import '../../widgets/rich_message_field.dart';
import '../../widgets/states.dart';

/// `POST /tasks` — create a task.
class CreateTaskScreen extends ConsumerStatefulWidget {
  const CreateTaskScreen({super.key});

  @override
  ConsumerState<CreateTaskScreen> createState() => _CreateTaskScreenState();
}

class _CreateTaskScreenState extends ConsumerState<CreateTaskScreen> {
  final _title = TextEditingController();
  final _description = FleatherController();

  MetaItem? _department;
  MetaItem? _priority;
  DateTime? _due;
  Task? _parent;
  final List<PlatformFile> _files = [];

  bool _saving = false;
  Map<String, String> _fieldErrors = const {};
  String? _error;

  @override
  void dispose() {
    _title.dispose();
    _description.dispose();
    super.dispose();
  }

  void _toast(String msg) => AppSnack.success(context, msg);

  /// Plain-text view of the rich description, for empty/required checks.
  String get _descriptionText =>
      _description.document.toPlainText().trim();

  Future<void> _submit() async {
    if (_department == null) {
      setState(() => _error = 'Pick a department first');
      return;
    }
    if (_title.text.trim().isEmpty || _descriptionText.isEmpty) {
      setState(() => _error = 'Title and description are required');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
      _fieldErrors = const {};
    });
    try {
      final task = await ref.read(tasksRepositoryProvider).create(
        {
          'dept_id': _department!.id,
          'title': _title.text.trim(),
          'description': parchmentHtml.encode(_description.document),
          if (_priority != null) 'priority_id': _priority!.id,
          if (_due != null) 'duedate': Fmt.apiDateTime(_due!),
          if (_parent != null) 'parent_id': _parent!.id,
        },
        files: [
          for (final f in _files)
            if (f.bytes != null)
              MultipartFile.fromBytes(f.bytes!, filename: f.name),
        ],
      );
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

  Future<void> _pickFiles() async {
    final res = await FilePicker.platform.pickFiles(
      allowMultiple: true,
      withData: true, // need bytes to upload on every platform
    );
    if (res == null || !mounted) return;
    setState(() {
      for (final f in res.files) {
        if (f.bytes != null && !_files.any((e) => e.name == f.name)) {
          _files.add(f);
        }
      }
    });
  }

  Future<void> _pickDue() async {
    final now = DateTime.now();
    final date = await pickDate(
      context,
      initial: _due ?? now,
      first: now.subtract(const Duration(days: 1)),
      last: now.add(const Duration(days: 365 * 3)),
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
                AppText.subText(
                  context,
                  _error!,
                  color: Theme.of(context).colorScheme.error,
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
              RichMessageField(
                controller: _description,
                label: 'Description',
                hintText: 'Describe the task…',
                errorText: _fieldErrors['description'],
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  AppText.subText(
                    context,
                    'Attachments',
                    fw: 1,
                  ),
                  const Spacer(),
                  TextButton.icon(
                    onPressed: _pickFiles,
                    icon: const Icon(Icons.attach_file, size: 18),
                    label: const Text('Add files'),
                  ),
                ],
              ),
              if (_files.isEmpty)
                AppText.subText(
                  context,
                  'No files added',
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                )
              else
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final f in _files)
                      Chip(
                        avatar: const Icon(
                          Icons.insert_drive_file_outlined,
                          size: 18,
                        ),
                        label: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 180),
                          child: Text(
                            '${f.name}  ·  ${Fmt.fileSize(f.size)}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        onDeleted: () => setState(() => _files.remove(f)),
                      ),
                  ],
                ),
              const SizedBox(height: 12),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.apartment_outlined),
                title: AppText.subText(context, 'Department'),
                subtitle: AppText.subText(
                  context,
                  _department?.name ?? 'Required',
                  color: _fieldErrors['dept_id'] != null
                      ? Theme.of(context).colorScheme.error
                      : _department != null
                      ? Theme.of(context).colorScheme.onSurface
                      : Theme.of(context).colorScheme.onSurfaceVariant,
                  fw: _department != null ? 1 : null,
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: () async {
                  final m = await pickMeta(
                    context,
                    ref,
                    MetaKind.departments,
                    title: 'Department',
                    selectedId: _department?.id,
                  );
                  if (m != null) setState(() => _department = m);
                },
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.flag_outlined),
                title: AppText.subText(context, 'Priority'),
                subtitle: AppText.subText(context, _priority?.name ?? 'Optional'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () async {
                  final m = await pickMeta(
                    context,
                    ref,
                    MetaKind.taskPriorities,
                    title: 'Priority',
                    selectedId: _priority?.id,
                  );
                  if (m != null) setState(() => _priority = m);
                },
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.event_outlined),
                title: AppText.subText(context, 'Due date'),
                subtitle: AppText.subText(
                  context,
                  _due == null ? 'Optional' : Fmt.dateTime(_due),
                ),
                trailing: _due == null
                    ? const Icon(Icons.chevron_right)
                    : IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () => setState(() => _due = null),
                      ),
                onTap: _pickDue,
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.account_tree_outlined),
                title: AppText.subText(context, 'Parent task'),
                subtitle: AppText.subText(
                  context,
                  _parent == null
                      ? 'Optional'
                      : '#${_parent!.number} · ${_parent!.title}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                trailing: _parent == null
                    ? const Icon(Icons.chevron_right)
                    : IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () => setState(() => _parent = null),
                      ),
                onTap: () async {
                  final t = await showAppSheet<Task>(
                    context: context,
                    builder: (_) => const _ParentTaskSheet(),
                  );
                  if (t != null) setState(() => _parent = t);
                },
              ),
            ],
          ),
        ),
      ),
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          border: Border(
            top: BorderSide(
              color: Theme.of(context).colorScheme.outlineVariant,
            ),
          ),
        ),
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
            child: FilledButton(
              onPressed: _saving ? null : _submit,
              child: const Text('Create task'),
            ),
          ),
        ),
      ),
    );
  }
}

/// Bottom-sheet task search/picker (`GET /tasks?q=`) for choosing a parent task.
class _ParentTaskSheet extends ConsumerStatefulWidget {
  const _ParentTaskSheet();

  @override
  ConsumerState<_ParentTaskSheet> createState() => _ParentTaskSheetState();
}

class _ParentTaskSheetState extends ConsumerState<_ParentTaskSheet> {
  final _ctrl = TextEditingController();
  List<Task> _results = [];
  bool _loading = false;
  Object? _error;
  String _lastQuery = '';

  @override
  void initState() {
    super.initState();
    _search('');
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _search(String q) async {
    _lastQuery = q;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final page = await ref.read(tasksRepositoryProvider).list(
        TaskQuery(view: 'all', q: q.isEmpty ? null : q, limit: 25),
      );
      if (!mounted) return;
      setState(() {
        _results = page.items;
        _loading = false;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AppSheet(
      title: 'Select parent task',
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SheetSearchField(
            controller: _ctrl,
            autofocus: true,
            hintText: 'Search task by number or title',
            onSubmitted: _search,
            onClear: () => _search(''),
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 320,
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                ? ErrorView(
                    error: _error!,
                    compact: true,
                    onRetry: () => _search(_lastQuery),
                  )
                : _results.isEmpty
                ? Center(child: AppText.subText(context, 'No tasks found'))
                : ListView.builder(
                    itemCount: _results.length,
                    itemBuilder: (_, i) {
                      final t = _results[i];
                      return ListTile(
                        title: AppText.subText(
                          context,
                          t.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: AppText.subText(
                          context,
                          '#${t.number} · ${t.statusName}',
                        ),
                        onTap: () => Navigator.pop(context, t),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
