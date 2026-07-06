import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_widget_from_html_core/flutter_widget_from_html_core.dart';
import 'package:go_router/go_router.dart';

import '../../../core/api/api_exception.dart';
import '../../../core/format.dart';
import '../../../core/router/routes.dart';
import '../../../models/common.dart';
import '../../../models/meta.dart';
import '../../../models/task.dart';
import '../../../providers.dart';
import '../../../widgets/app_toast.dart';
import '../../../widgets/states.dart';
import '../../dashboard/web/_tokens.dart';

/// Web-only task detail, styled to the Zebu Premium spec in `skill.md`.
///
/// Data sources mirror the mobile [TaskDetailScreen] via
/// [tasksRepositoryProvider] — the visual language and layout differ:
///
/// * Two-column layout on ≥1000 px: main content on the left, metadata rail
///   on the right.
/// * Header shows the task number, title, and status/priority/overdue tags
///   inline. No collapsing chrome — this screen already renders inside the
///   web shell so the shell's top bar is the pinned navigator.
/// * Sections replace the mobile TabBar. Conversation is the primary section;
///   Subtasks and Dependencies sit below on the same scroll.
/// * The reply composer is a plain [TextField] for v1 (Fleather rich editor
///   deferred). Notes vs. replies still toggle inline.
///
/// Bulk-only advanced surfaces (tags editor, collaborators editor) are
/// intentionally deferred; the mobile screen keeps them until we port the
/// dialogs. Read-only tag / collaborator display is present in the sidebar.
const _kFlatRadius = 8.0;
const _kSidebarWidth = 320.0;
const _kMinTwoColWidth = 1000.0;

class TaskDetailScreenWeb extends ConsumerStatefulWidget {
  const TaskDetailScreenWeb({super.key, required this.taskId});
  final int taskId;

  @override
  ConsumerState<TaskDetailScreenWeb> createState() =>
      _TaskDetailScreenWebState();
}

class _TaskDetailScreenWebState extends ConsumerState<TaskDetailScreenWeb> {
  Task? _task;
  List<ThreadEntry> _thread = const [];
  List<Task> _subtasks = const [];
  List<TaskDependency> _dependencies = const [];
  Object? _error;
  bool _loading = true;
  bool _acting = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final repo = ref.read(tasksRepositoryProvider);
    try {
      final task = await repo.get(widget.taskId);
      final thread = await repo.thread(widget.taskId, limit: 50);
      final subtasks = await repo.subtasks(widget.taskId);
      final dependencies = await repo.dependencies(widget.taskId);
      if (!mounted) return;
      setState(() {
        _task = task;
        _thread = thread.items;
        _subtasks = subtasks;
        _dependencies = dependencies;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e;
        _loading = false;
      });
    }
  }

  void _apply(Task updated) => setState(() => _task = updated);

  void _toast(String msg, {ToastType type = ToastType.info}) =>
      AppToast.show(context, msg, type: type);

  Future<void> _runAction(
    Future<Task> Function() action, {
    String? success,
  }) async {
    setState(() => _acting = true);
    try {
      final updated = await action();
      _apply(updated);
      if (success != null) _toast(success, type: ToastType.success);
    } on ApiException catch (e) {
      _toast(e.message, type: ToastType.error);
    } finally {
      if (mounted) setState(() => _acting = false);
    }
  }

  Future<void> _onMenu(String value) async {
    final repo = ref.read(tasksRepositoryProvider);
    switch (value) {
      case 'close':
        await _runAction(
          () => repo.close(widget.taskId),
          success: 'Task closed',
        );
        await _load();
      case 'reopen':
        await _runAction(
          () => repo.reopen(widget.taskId),
          success: 'Task reopened',
        );
        await _load();
      case 'assign':
        await _pickMeta(MetaKind.agents, title: 'Assign to', (id) async {
          await _runAction(
            () => repo.assign(widget.taskId, staffId: id),
            success: 'Assigned',
          );
          await _load();
        });
      case 'transfer':
        await _pickMeta(
          MetaKind.departments,
          title: 'Transfer department',
          (id) async {
            await _runAction(
              () => repo.transfer(widget.taskId, id),
              success: 'Transferred',
            );
            await _load();
          },
        );
      case 'progress':
        await _editProgress();
      case 'priority':
        await _pickMeta(
          MetaKind.taskPriorities,
          title: 'Set priority',
          (id) async {
            await _runAction(
              () => repo.edit(widget.taskId, priorityId: id),
              success: 'Priority updated',
            );
            await _load();
          },
        );
    }
  }

  Future<void> _pickMeta(
    String kind,
    Future<void> Function(int id) onPick, {
    String title = 'Select',
  }) async {
    final List<MetaItem> items;
    try {
      items = await ref.read(metaRepositoryProvider).get(kind);
    } on ApiException catch (e) {
      _toast(e.message, type: ToastType.error);
      return;
    }
    if (!mounted) return;
    final chosen = await showDialog<int>(
      context: context,
      builder: (_) => SimpleDialog(
        title: Text(title),
        children: [
          for (final m in items)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(context, m.id),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Text(m.name),
              ),
            ),
        ],
      ),
    );
    if (chosen != null) await onPick(chosen);
  }

  Future<void> _editProgress() async {
    final value = await showDialog<int>(
      context: context,
      builder: (_) => _ProgressDialog(initial: _task?.progress ?? 0),
    );
    if (value == null) return;
    await _runAction(
      () => ref
          .read(tasksRepositoryProvider)
          .edit(widget.taskId, progress: value),
      success: 'Progress updated',
    );
    await _load();
  }

  Future<void> _addSubtask() async {
    final result = await showDialog<({String title, String? description})>(
      context: context,
      builder: (_) => const _SubtaskDialog(),
    );
    if (result == null) return;
    setState(() => _acting = true);
    try {
      await ref.read(tasksRepositoryProvider).createSubtask(widget.taskId, {
        'title': result.title,
        if (result.description != null && result.description!.isNotEmpty)
          'description': result.description,
      });
      _toast('Subtask created', type: ToastType.success);
    } on ApiException catch (e) {
      _toast(e.message, type: ToastType.error);
    } finally {
      if (mounted) setState(() => _acting = false);
    }
    await _load();
  }

  Future<void> _addDependency() async {
    final id = await showDialog<int>(
      context: context,
      builder: (_) => const _DependencyDialog(),
    );
    if (id == null) return;
    setState(() => _acting = true);
    try {
      final deps = await ref
          .read(tasksRepositoryProvider)
          .addDependency(widget.taskId, id);
      if (mounted) setState(() => _dependencies = deps);
    } on ApiException catch (e) {
      _toast(e.message, type: ToastType.error);
    } finally {
      if (mounted) setState(() => _acting = false);
    }
    await _load();
  }

  Future<void> _removeDependency(int depId) async {
    setState(() => _acting = true);
    try {
      final deps = await ref
          .read(tasksRepositoryProvider)
          .removeDependency(widget.taskId, depId);
      if (mounted) setState(() => _dependencies = deps);
    } on ApiException catch (e) {
      _toast(e.message, type: ToastType.error);
    } finally {
      if (mounted) setState(() => _acting = false);
    }
    await _load();
  }

  Future<void> _sendReply({required bool asNote, required String body}) async {
    if (body.trim().isEmpty) return;
    setState(() => _acting = true);
    final repo = ref.read(tasksRepositoryProvider);
    try {
      if (asNote) {
        await repo.note(widget.taskId, body: body);
      } else {
        await repo.reply(widget.taskId, body: body, alert: true);
      }
      _toast(asNote ? 'Note added' : 'Reply sent', type: ToastType.success);
      await _load();
    } on ApiException catch (e) {
      _toast(e.message, type: ToastType.error);
    } finally {
      if (mounted) setState(() => _acting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = WebTokens.of(context);
    return ColoredBox(color: t.bgElevated, child: _buildBody(t));
  }

  Widget _buildBody(WebTokens t) {
    if (_loading) return const LoadingView();
    if (_error != null || _task == null) {
      return ErrorView(error: _error ?? 'Not found', onRetry: _load);
    }
    final task = _task!;
    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= _kMinTwoColWidth;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (_acting) const LinearProgressIndicator(minHeight: 2),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(
                  WebTokens.s8,
                  WebTokens.s8,
                  WebTokens.s8,
                  WebTokens.s8,
                ),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 1360),
                    child: wide
                        ? _wideLayout(task)
                        : _narrowLayout(task),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _wideLayout(Task task) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: _mainColumn(task)),
        const SizedBox(width: WebTokens.s6),
        SizedBox(width: _kSidebarWidth, child: _sidebar(task)),
      ],
    );
  }

  Widget _narrowLayout(Task task) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _mainColumn(task),
        const SizedBox(height: WebTokens.s6),
        _sidebar(task),
      ],
    );
  }

  Widget _mainColumn(Task task) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _HeroHeader(task: task, onMenu: _onMenu),
        const SizedBox(height: WebTokens.s5),
        _ThreadCard(thread: _thread),
        const SizedBox(height: WebTokens.s5),
        _ReplyCard(onSend: _sendReply, disabled: _acting),
        const SizedBox(height: WebTokens.s5),
        _SubtasksCard(
          subtasks: _subtasks,
          onAdd: _addSubtask,
          onOpen: (st) => context.go(Routes.task(st.id)),
        ),
        const SizedBox(height: WebTokens.s5),
        _DependenciesCard(
          dependencies: _dependencies,
          onAdd: _addDependency,
          onRemove: _removeDependency,
        ),
      ],
    );
  }

  Widget _sidebar(Task task) {
    return _MetadataCard(task: task);
  }
}

// ---------------------------------------------------------------------------
// Header — back button, task number, title, status/priority tags, action menu
// ---------------------------------------------------------------------------

class _HeroHeader extends StatelessWidget {
  const _HeroHeader({required this.task, required this.onMenu});
  final Task task;
  final Future<void> Function(String value) onMenu;

  @override
  Widget build(BuildContext context) {
    final t = WebTokens.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _BackButton(),
        const SizedBox(width: WebTokens.s3),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(
                    '#${task.number}',
                    style: t.sectionTitle,
                  ),
                  const SizedBox(width: WebTokens.s2),
                  if (task.blocked) ...[
                    _Tag(label: 'BLOCKED', tone: WebTokens.danger),
                    const SizedBox(width: WebTokens.s2),
                  ],
                  if (task.overdue)
                    _Tag(label: 'OVERDUE', tone: WebTokens.danger),
                ],
              ),
              const SizedBox(height: WebTokens.s2),
              Text(task.title, style: t.hero),
              const SizedBox(height: WebTokens.s3),
              Row(
                children: [
                  _Tag(
                    label: task.statusName.toUpperCase(),
                    tone: task.isOpen ? WebTokens.success : t.textSecondary,
                  ),
                  if (task.priority != null) ...[
                    const SizedBox(width: WebTokens.s2),
                    _Tag(
                      label: task.priority!.name.toUpperCase(),
                      tone: _priorityTone(task.priority!.name),
                    ),
                  ],
                  if (task.progress > 0) ...[
                    const SizedBox(width: WebTokens.s4),
                    Expanded(
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          SizedBox(
                            width: 160,
                            child: ClipRRect(
                              borderRadius:
                                  BorderRadius.circular(_kFlatRadius),
                              child: LinearProgressIndicator(
                                value: (task.progress / 100).clamp(0, 1),
                                minHeight: 6,
                                backgroundColor: t.bgHover,
                                valueColor: const AlwaysStoppedAnimation(
                                  WebTokens.accent,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: WebTokens.s2),
                          Text(
                            '${task.progress}%',
                            style: t.bodySm
                                .copyWith(fontWeight: FontWeight.w600)
                                .withTabularNums(),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
        const SizedBox(width: WebTokens.s4),
        _ActionMenu(task: task, onSelected: onMenu),
      ],
    );
  }

  static Color _priorityTone(String name) {
    final n = name.toLowerCase();
    if (n.contains('emergency') || n.contains('high')) return WebTokens.danger;
    if (n.contains('low')) return WebTokens.success;
    return WebTokens.warning;
  }
}

class _BackButton extends StatefulWidget {
  @override
  State<_BackButton> createState() => _BackButtonState();
}

class _BackButtonState extends State<_BackButton> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final t = WebTokens.of(context);
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: () {
          if (context.canPop()) {
            context.pop();
          } else {
            context.go(Routes.tasks);
          }
        },
        child: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: _hover ? t.bgHover : t.bgElevated,
            border: Border.all(color: t.borderSubtle),
            borderRadius: BorderRadius.circular(_kFlatRadius),
          ),
          child: Icon(Icons.arrow_back, size: 18, color: t.textPrimary),
        ),
      ),
    );
  }
}

class _ActionMenu extends StatelessWidget {
  const _ActionMenu({required this.task, required this.onSelected});
  final Task task;
  final Future<void> Function(String value) onSelected;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      tooltip: 'Actions',
      onSelected: onSelected,
      position: PopupMenuPosition.under,
      itemBuilder: (_) => [
        if (task.isOpen)
          const PopupMenuItem(value: 'close', child: Text('Close task'))
        else
          const PopupMenuItem(value: 'reopen', child: Text('Reopen task')),
        const PopupMenuItem(value: 'assign', child: Text('Assign')),
        const PopupMenuItem(value: 'transfer', child: Text('Transfer dept')),
        const PopupMenuItem(value: 'progress', child: Text('Edit progress')),
        const PopupMenuItem(value: 'priority', child: Text('Set priority')),
      ],
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: WebTokens.s3,
          vertical: 8,
        ),
        decoration: BoxDecoration(
          color: WebTokens.accent,
          borderRadius: BorderRadius.circular(_kFlatRadius),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: const [
            Icon(Icons.bolt_outlined, size: 16, color: Colors.white),
            SizedBox(width: 6),
            Text(
              'Actions',
              style: TextStyle(
                color: Colors.white,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
            SizedBox(width: 4),
            Icon(Icons.expand_more, size: 16, color: Colors.white),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Thread card
// ---------------------------------------------------------------------------

class _ThreadCard extends StatelessWidget {
  const _ThreadCard({required this.thread});
  final List<ThreadEntry> thread;

  @override
  Widget build(BuildContext context) {
    final t = WebTokens.of(context);
    return _SectionCard(
      title: 'CONVERSATION',
      trailing: '${thread.length} entries',
      child: thread.isEmpty
          ? Padding(
              padding: const EdgeInsets.all(WebTokens.s5),
              child: Center(
                child: Text('No messages yet', style: t.bodySm),
              ),
            )
          : Column(
              children: [
                for (int i = 0; i < thread.length; i++) ...[
                  if (i > 0)
                    Divider(height: 1, color: t.borderSubtle),
                  _ThreadEntryRow(entry: thread[i]),
                ],
              ],
            ),
    );
  }
}

class _ThreadEntryRow extends StatelessWidget {
  const _ThreadEntryRow({required this.entry});
  final ThreadEntry entry;

  @override
  Widget build(BuildContext context) {
    final t = WebTokens.of(context);
    final isNote = entry.isNote;
    final isResponse = entry.isResponse;
    final tone = isNote
        ? WebTokens.warning
        : (isResponse ? WebTokens.accent : t.textSecondary);
    final typeLabel = isNote
        ? 'NOTE'
        : (isResponse ? 'REPLY' : 'MESSAGE');
    final html = entry.bodyHtml ?? entry.body ?? '';
    final plain = Fmt.stripHtml(html);

    return Padding(
      padding: const EdgeInsets.all(WebTokens.s4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 36,
            height: 36,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: tone.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(_kFlatRadius),
            ),
            child: Text(
              entry.poster.isNotEmpty
                  ? entry.poster.trim()[0].toUpperCase()
                  : '?',
              style: TextStyle(
                color: tone,
                fontWeight: FontWeight.w700,
                fontSize: 14,
              ),
            ),
          ),
          const SizedBox(width: WebTokens.s3),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      entry.poster,
                      style: t.cardName,
                    ),
                    const SizedBox(width: WebTokens.s2),
                    _Tag(label: typeLabel, tone: tone),
                    const Spacer(),
                    if (entry.created != null)
                      Text(Fmt.ago(entry.created), style: t.tinyLabel),
                  ],
                ),
                if (entry.title != null && entry.title!.isNotEmpty) ...[
                  const SizedBox(height: WebTokens.s2),
                  Text(
                    entry.title!,
                    style: t.bodyBase
                        .copyWith(fontWeight: FontWeight.w600),
                  ),
                ],
                const SizedBox(height: WebTokens.s2),
                if (plain.trim().isEmpty)
                  Text('(no content)', style: t.bodySm)
                else if (html.contains('<'))
                  HtmlWidget(
                    html,
                    textStyle: t.bodyBase.copyWith(height: 1.5),
                  )
                else
                  Text(plain, style: t.bodyBase.copyWith(height: 1.5)),
                if (entry.attachments.isNotEmpty) ...[
                  const SizedBox(height: WebTokens.s3),
                  Wrap(
                    spacing: WebTokens.s2,
                    runSpacing: WebTokens.s2,
                    children: [
                      for (final a in entry.attachments)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: WebTokens.s3,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: t.bgHover,
                            borderRadius: BorderRadius.circular(_kFlatRadius),
                            border: Border.all(color: t.borderSubtle),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.attach_file,
                                size: 14,
                                color: t.textSecondary,
                              ),
                              const SizedBox(width: 6),
                              Text(a.name, style: t.bodySm),
                            ],
                          ),
                        ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Reply composer — plain-text v1 (Fleather rich editor deferred)
// ---------------------------------------------------------------------------

class _ReplyCard extends StatefulWidget {
  const _ReplyCard({required this.onSend, required this.disabled});
  final Future<void> Function({required bool asNote, required String body})
      onSend;
  final bool disabled;

  @override
  State<_ReplyCard> createState() => _ReplyCardState();
}

class _ReplyCardState extends State<_ReplyCard> {
  final _controller = TextEditingController();
  bool _asNote = false;
  bool _sending = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final body = _controller.text.trim();
    if (body.isEmpty || _sending) return;
    setState(() => _sending = true);
    try {
      await widget.onSend(asNote: _asNote, body: body);
      if (mounted) _controller.clear();
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = WebTokens.of(context);
    return _SectionCard(
      title: _asNote ? 'INTERNAL NOTE' : 'REPLY',
      trailing: null,
      child: Padding(
        padding: const EdgeInsets.all(WebTokens.s4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                _ToggleChip(
                  label: 'Reply',
                  active: !_asNote,
                  onTap: () => setState(() => _asNote = false),
                ),
                const SizedBox(width: WebTokens.s2),
                _ToggleChip(
                  label: 'Note',
                  active: _asNote,
                  tone: WebTokens.warning,
                  onTap: () => setState(() => _asNote = true),
                ),
              ],
            ),
            const SizedBox(height: WebTokens.s2),
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  child: TextField(
                    controller: _controller,
                    minLines: 1,
                    maxLines: 6,
                    enabled: !widget.disabled && !_sending,
                    style: t.bodyBase,
                    decoration: InputDecoration(
                      filled: true,
                      fillColor: t.bgElevated,
                      hintText: _asNote
                          ? 'Add an internal note (not visible to requester)…'
                          : 'Write a reply…',
                      hintStyle: t.bodyBase.copyWith(color: t.textSecondary),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(_kFlatRadius),
                        borderSide: BorderSide(color: t.borderSubtle),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(_kFlatRadius),
                        borderSide: BorderSide(
                          color: _asNote ? WebTokens.warning : t.borderSubtle,
                        ),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(_kFlatRadius),
                        borderSide: BorderSide(
                          color: _asNote ? WebTokens.warning : WebTokens.accent,
                          width: 1.4,
                        ),
                      ),
                      contentPadding: const EdgeInsets.all(WebTokens.s3),
                    ),
                  ),
                ),
                const SizedBox(width: WebTokens.s2),
                _PrimaryButton(
                  label: _asNote ? 'Save note' : 'Send reply',
                  icon: _asNote ? Icons.sticky_note_2_outlined : Icons.send,
                  disabled: widget.disabled || _sending,
                  tone: _asNote ? WebTokens.warning : WebTokens.accent,
                  onTap: _submit,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ToggleChip extends StatelessWidget {
  const _ToggleChip({
    required this.label,
    required this.active,
    required this.onTap,
    this.tone,
  });
  final String label;
  final bool active;
  final VoidCallback onTap;
  final Color? tone;

  @override
  Widget build(BuildContext context) {
    final t = WebTokens.of(context);
    final effective = tone ?? WebTokens.accent;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: WebTokens.s3,
            vertical: 6,
          ),
          decoration: BoxDecoration(
            color: active ? effective.withValues(alpha: 0.14) : t.bgElevated,
            border: Border.all(
              color: active ? effective : t.borderSubtle,
              width: 1,
            ),
            borderRadius: BorderRadius.circular(_kFlatRadius),
          ),
          child: Text(
            label,
            style: t.bodySm.copyWith(
              color: active ? effective : t.textSecondary,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }
}

class _PrimaryButton extends StatefulWidget {
  const _PrimaryButton({
    required this.label,
    required this.icon,
    required this.onTap,
    required this.disabled,
    required this.tone,
  });
  final String label;
  final IconData icon;
  final VoidCallback onTap;
  final bool disabled;
  final Color tone;

  @override
  State<_PrimaryButton> createState() => _PrimaryButtonState();
}

class _PrimaryButtonState extends State<_PrimaryButton> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final effective = widget.disabled
        ? widget.tone.withValues(alpha: 0.5)
        : widget.tone;
    return MouseRegion(
      cursor: widget.disabled
          ? SystemMouseCursors.forbidden
          : SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: widget.disabled ? null : widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          padding: const EdgeInsets.symmetric(
            horizontal: WebTokens.s4,
            vertical: 14,
          ),
          decoration: BoxDecoration(
            color: _hover && !widget.disabled
                ? Color.lerp(effective, Colors.black, 0.08)
                : effective,
            borderRadius: BorderRadius.circular(_kFlatRadius),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(widget.icon, size: 16, color: Colors.white),
              const SizedBox(width: 8),
              Text(
                widget.label,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Subtasks card
// ---------------------------------------------------------------------------

class _SubtasksCard extends StatelessWidget {
  const _SubtasksCard({
    required this.subtasks,
    required this.onAdd,
    required this.onOpen,
  });
  final List<Task> subtasks;
  final VoidCallback onAdd;
  final ValueChanged<Task> onOpen;

  @override
  Widget build(BuildContext context) {
    final t = WebTokens.of(context);
    return _SectionCard(
      title: 'SUBTASKS',
      trailing: '${subtasks.length}',
      action: _AddButton(label: 'Add subtask', onTap: onAdd),
      child: subtasks.isEmpty
          ? Padding(
              padding: const EdgeInsets.all(WebTokens.s5),
              child: Center(child: Text('No subtasks', style: t.bodySm)),
            )
          : Column(
              children: [
                for (int i = 0; i < subtasks.length; i++) ...[
                  if (i > 0) Divider(height: 1, color: t.borderSubtle),
                  _SubtaskRow(task: subtasks[i], onTap: () => onOpen(subtasks[i])),
                ],
              ],
            ),
    );
  }
}

class _SubtaskRow extends StatefulWidget {
  const _SubtaskRow({required this.task, required this.onTap});
  final Task task;
  final VoidCallback onTap;

  @override
  State<_SubtaskRow> createState() => _SubtaskRowState();
}

class _SubtaskRowState extends State<_SubtaskRow> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final t = WebTokens.of(context);
    final task = widget.task;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: Container(
          color: _hover ? t.bgHover : Colors.transparent,
          padding: const EdgeInsets.symmetric(
            horizontal: WebTokens.s4,
            vertical: WebTokens.s3,
          ),
          child: Row(
            children: [
              Text(
                '#${task.number}',
                style: t.bodySm
                    .copyWith(fontWeight: FontWeight.w600)
                    .withTabularNums(),
              ),
              const SizedBox(width: WebTokens.s3),
              Expanded(
                child: Text(
                  task.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: t.bodyBase,
                ),
              ),
              const SizedBox(width: WebTokens.s3),
              _Tag(
                label: task.statusName.toUpperCase(),
                tone: task.isOpen ? WebTokens.success : t.textSecondary,
              ),
              if (task.progress > 0) ...[
                const SizedBox(width: WebTokens.s3),
                Text(
                  '${task.progress}%',
                  style: t.bodySm.withTabularNums(),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Dependencies card
// ---------------------------------------------------------------------------

class _DependenciesCard extends StatelessWidget {
  const _DependenciesCard({
    required this.dependencies,
    required this.onAdd,
    required this.onRemove,
  });
  final List<TaskDependency> dependencies;
  final VoidCallback onAdd;
  final ValueChanged<int> onRemove;

  @override
  Widget build(BuildContext context) {
    final t = WebTokens.of(context);
    return _SectionCard(
      title: 'DEPENDENCIES',
      trailing: '${dependencies.length}',
      action: _AddButton(label: 'Add dependency', onTap: onAdd),
      child: dependencies.isEmpty
          ? Padding(
              padding: const EdgeInsets.all(WebTokens.s5),
              child: Center(child: Text('No dependencies', style: t.bodySm)),
            )
          : Column(
              children: [
                for (int i = 0; i < dependencies.length; i++) ...[
                  if (i > 0) Divider(height: 1, color: t.borderSubtle),
                  _DependencyRow(
                    dep: dependencies[i],
                    onRemove: () => onRemove(dependencies[i].id),
                  ),
                ],
              ],
            ),
    );
  }
}

class _DependencyRow extends StatelessWidget {
  const _DependencyRow({required this.dep, required this.onRemove});
  final TaskDependency dep;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final t = WebTokens.of(context);
    final blocker = dep.blocker;
    final blocked = blocker != null && blocker.open;
    final tone = blocked ? WebTokens.danger : WebTokens.success;
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: WebTokens.s4,
        vertical: WebTokens.s3,
      ),
      child: Row(
        children: [
          Icon(
            blocked ? Icons.lock_outline : Icons.check_circle_outline,
            color: tone,
            size: 18,
          ),
          const SizedBox(width: WebTokens.s3),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  blocker == null
                      ? 'Dependency #${dep.id}'
                      : '#${blocker.number} ${blocker.title}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: t.bodyBase.copyWith(fontWeight: FontWeight.w500),
                ),
                const SizedBox(height: 2),
                Text(
                  dep.required ? 'Required' : 'Optional',
                  style: t.tinyLabel,
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Remove',
            icon: Icon(Icons.close, size: 18, color: t.textSecondary),
            onPressed: onRemove,
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Metadata sidebar
// ---------------------------------------------------------------------------

class _MetadataCard extends StatelessWidget {
  const _MetadataCard({required this.task});
  final Task task;

  @override
  Widget build(BuildContext context) {
    final t = WebTokens.of(context);
    final rows = <(String, String?)>[
      ('Status', task.statusName),
      ('Department', task.departmentName),
      ('Assignee', task.assignee),
      ('Priority', task.priority?.name),
      ('Progress', task.progress > 0 ? '${task.progress}%' : null),
      ('Due', Fmt.dateTime(task.duedate)),
      ('Created', Fmt.dateTime(task.created)),
      ('Updated', Fmt.dateTime(task.updated)),
    ];
    return Container(
      decoration: BoxDecoration(
        color: t.bgElevated,
        borderRadius: BorderRadius.circular(_kFlatRadius),
        border: Border.all(color: t.borderSubtle),
      ),
      padding: const EdgeInsets.all(WebTokens.s5),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('DETAILS', style: t.sectionTitle),
          const SizedBox(height: WebTokens.s3),
          for (final (label, value) in rows)
            if (value != null && value.isNotEmpty && value != '—')
              _MetaRow(label: label, value: value),
          if (task.customFields.isNotEmpty) ...[
            const SizedBox(height: WebTokens.s4),
            Divider(height: 1, color: t.borderSubtle),
            const SizedBox(height: WebTokens.s3),
            Text('CUSTOM FIELDS', style: t.sectionTitle),
            const SizedBox(height: WebTokens.s3),
            for (final e in task.customFields.entries)
              _MetaRow(label: e.key, value: e.value),
          ],
        ],
      ),
    );
  }
}

class _MetaRow extends StatelessWidget {
  const _MetaRow({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final t = WebTokens.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: t.tinyLabel,
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: t.bodyBase.copyWith(fontWeight: FontWeight.w500),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Section card wrapper — bordered card with header row (title + optional
// trailing count + optional action button).
// ---------------------------------------------------------------------------

class _SectionCard extends StatelessWidget {
  const _SectionCard({
    required this.title,
    required this.child,
    this.trailing,
    this.action,
  });
  final String title;
  final Widget child;
  final String? trailing;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final t = WebTokens.of(context);
    return Container(
      decoration: BoxDecoration(
        color: t.bgElevated,
        borderRadius: BorderRadius.circular(_kFlatRadius),
        border: Border.all(color: t.borderSubtle),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              WebTokens.s4,
              WebTokens.s3,
              WebTokens.s3,
              WebTokens.s3,
            ),
            child: Row(
              children: [
                Text(title, style: t.sectionTitle),
                if (trailing != null) ...[
                  const SizedBox(width: WebTokens.s2),
                  Text(
                    trailing!,
                    style: t.bodySm.withTabularNums(),
                  ),
                ],
                const Spacer(),
                if (action != null) action!,
              ],
            ),
          ),
          Divider(height: 1, color: t.borderSubtle),
          child,
        ],
      ),
    );
  }
}

class _AddButton extends StatefulWidget {
  const _AddButton({required this.label, required this.onTap});
  final String label;
  final VoidCallback onTap;

  @override
  State<_AddButton> createState() => _AddButtonState();
}

class _AddButtonState extends State<_AddButton> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final t = WebTokens.of(context);
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: _hover ? t.accentMuted : Colors.transparent,
            border: Border.all(color: t.borderSubtle),
            borderRadius: BorderRadius.circular(_kFlatRadius),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.add, size: 14, color: WebTokens.accent),
              const SizedBox(width: 4),
              Text(
                widget.label,
                style: t.bodySm.copyWith(
                  color: WebTokens.accent,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Small pill / tag primitive (mirrors the tickets/tasks web list)
// ---------------------------------------------------------------------------

class _Tag extends StatelessWidget {
  const _Tag({required this.label, required this.tone});
  final String label;

  /// Text color for the tag. Semantic tones come through as colored
  /// uppercase text — the pill has no background or border anywhere in
  /// the app.
  final Color tone;

  @override
  Widget build(BuildContext context) {
    final t = WebTokens.of(context);
    return Text(label, style: t.tinyLabel.copyWith(color: tone));
  }
}

// ---------------------------------------------------------------------------
// Dialogs — kept local so we don't leak private mobile widgets.
// ---------------------------------------------------------------------------

class _ProgressDialog extends StatefulWidget {
  const _ProgressDialog({required this.initial});
  final int initial;

  @override
  State<_ProgressDialog> createState() => _ProgressDialogState();
}

class _ProgressDialogState extends State<_ProgressDialog> {
  late double _value = widget.initial.toDouble().clamp(0, 100);

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Edit progress'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '${_value.round()}%',
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          Slider(
            value: _value,
            min: 0,
            max: 100,
            divisions: 100,
            label: '${_value.round()}%',
            onChanged: (v) => setState(() => _value = v),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, _value.round()),
          child: const Text('Save'),
        ),
      ],
    );
  }
}

class _DependencyDialog extends StatefulWidget {
  const _DependencyDialog();

  @override
  State<_DependencyDialog> createState() => _DependencyDialogState();
}

class _DependencyDialogState extends State<_DependencyDialog> {
  final _controller = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final id = int.tryParse(_controller.text.trim());
    if (id == null) {
      setState(() => _error = 'Enter a numeric task ID');
      return;
    }
    Navigator.pop(context, id);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Add dependency'),
      content: SizedBox(
        width: 320,
        child: TextField(
          controller: _controller,
          keyboardType: TextInputType.number,
          autofocus: true,
          decoration: InputDecoration(
            labelText: 'Blocker task ID',
            hintText: 'e.g. 123',
            errorText: _error,
          ),
          onSubmitted: (_) => _submit(),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _submit, child: const Text('Add')),
      ],
    );
  }
}

class _SubtaskDialog extends StatefulWidget {
  const _SubtaskDialog();

  @override
  State<_SubtaskDialog> createState() => _SubtaskDialogState();
}

class _SubtaskDialogState extends State<_SubtaskDialog> {
  final _title = TextEditingController();
  final _description = TextEditingController();

  @override
  void dispose() {
    _title.dispose();
    _description.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Add subtask'),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _title,
              autofocus: true,
              decoration: const InputDecoration(labelText: 'Title'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _description,
              minLines: 3,
              maxLines: 6,
              decoration: const InputDecoration(
                labelText: 'Description (optional)',
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () {
            final title = _title.text.trim();
            if (title.isEmpty) return;
            Navigator.pop(
              context,
              (title: title, description: _description.text.trim()),
            );
          },
          child: const Text('Create'),
        ),
      ],
    );
  }
}
