import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/api/api_exception.dart';
import '../../../core/router/routes.dart';
import '../../../models/saved_queue.dart';
import '../../../providers.dart';
import '../../../widgets/app_dialog.dart';
import '../../../widgets/app_toast.dart';
import '../../../widgets/states.dart';
import '../../dashboard/web/_tokens.dart';
import 'queue_editor_dialog.dart';

const _kFlatRadius = 8.0;

const int _kColNameFlex = 4;
const double _kColTypeWidth = 110;
const double _kColScopeWidth = 130;
const double _kColFiltersWidth = 110;
const double _kColActionsWidth = 60;
const double _kColGap = 16;
const double _kTableMinWidth = 900;

/// Web-only saved-queues list. No slide-over — rows navigate to the
/// tickets/tasks list (like the mobile screen).
class QueuesScreenWeb extends ConsumerStatefulWidget {
  const QueuesScreenWeb({super.key});

  @override
  ConsumerState<QueuesScreenWeb> createState() => _QueuesScreenWebState();
}

class _QueuesScreenWebState extends ConsumerState<QueuesScreenWeb> {
  String _search = '';
  Timer? _debounce;
  String? _type; // null = all, 'ticket', 'task'
  List<SavedQueue>? _queues;
  Object? _error;
  bool _loading = false;

  final ScrollController _tableHScroll = ScrollController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _tableHScroll.dispose();
    super.dispose();
  }

  void _toast(String msg, {ToastType type = ToastType.info}) =>
      AppToast.show(context, msg, type: type);

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final queues =
          await ref.read(queuesRepositoryProvider).list(type: _type);
      if (!mounted) return;
      setState(() {
        _queues = queues;
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

  void _onSearchChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () {
      final next = value.trim();
      if (next != _search && mounted) {
        setState(() => _search = next);
      }
    });
  }

  void _setType(String? type) {
    if (type == _type) return;
    setState(() => _type = type);
    _load();
  }

  void _onTap(SavedQueue queue) {
    if (queue.type == 'ticket') {
      context.push(Routes.tickets);
    } else {
      _toast('Task queues open in the tasks list.');
    }
  }

  Future<void> _openCreate() async {
    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => const QueueEditorDialog(),
    );
    if (saved == true && mounted) _load();
  }

  Future<void> _openEdit(SavedQueue queue) async {
    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => QueueEditorDialog(existing: queue),
    );
    if (saved == true && mounted) _load();
  }

  Future<void> _confirmDelete(SavedQueue queue) async {
    final ok = await showAppConfirmDialog(
      context,
      title: 'Delete queue?',
      message: 'Delete "${queue.fullName}"? This cannot be undone.',
      confirmLabel: 'Delete',
      destructive: true,
    );
    if (ok != true) return;
    try {
      await ref.read(queuesRepositoryProvider).delete(queue.id);
      _toast('Deleted', type: ToastType.success);
      _load();
    } on ApiException catch (e) {
      _toast(e.message, type: ToastType.error);
    }
  }

  List<SavedQueue> _filtered(List<SavedQueue> src) {
    if (_search.isEmpty) return src;
    final q = _search.toLowerCase();
    return src.where((s) => s.fullName.toLowerCase().contains(q)).toList();
  }

  @override
  Widget build(BuildContext context) {
    final t = WebTokens.of(context);
    final all = _queues ?? const [];
    final rows = _filtered(all);

    return ColoredBox(
      color: t.bgPrimary,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              WebTokens.s6,
              WebTokens.s5,
              WebTokens.s6,
              WebTokens.s4,
            ),
            child: LayoutBuilder(
              builder: (context, rowConstraints) {
                // Title-side content only (no action button, no filter
                // chips). Wrapped in Expanded on wide layouts so filter
                // chips + New button + search sit as a right-aligned group
                // flush against each other.
                final titleSide = Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    _BackButton(
                      onTap: () {
                        if (context.canPop()) {
                          context.pop();
                        } else {
                          context.go(Routes.more);
                        }
                      },
                    ),
                    const SizedBox(width: WebTokens.s3),
                    Flexible(
                      child: Text(
                        'Saved queues',
                        style: t.hero,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (_queues != null) ...[
                      const SizedBox(width: WebTokens.s3),
                      Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Text(
                          '${all.length} total',
                          style: t.bodySm.withTabularNums(),
                        ),
                      ),
                    ],
                  ],
                );

                final filterChips = Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _FilterChip(
                      label: 'All',
                      selected: _type == null,
                      onTap: () => _setType(null),
                    ),
                    const SizedBox(width: WebTokens.s2),
                    _FilterChip(
                      label: 'Tickets',
                      selected: _type == 'ticket',
                      onTap: () => _setType('ticket'),
                    ),
                    const SizedBox(width: WebTokens.s2),
                    _FilterChip(
                      label: 'Tasks',
                      selected: _type == 'task',
                      onTap: () => _setType('task'),
                    ),
                  ],
                );

                const narrowBreak = 820.0;
                if (rowConstraints.maxWidth < narrowBreak) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          Expanded(child: titleSide),
                          _NewButton(onTap: _openCreate),
                        ],
                      ),
                      const SizedBox(height: WebTokens.s3),
                      Row(
                        children: [
                          filterChips,
                          const Spacer(),
                          SizedBox(
                            width: 240,
                            child: _SearchInput(onChanged: _onSearchChanged),
                          ),
                        ],
                      ),
                    ],
                  );
                }

                final searchWidth =
                    (rowConstraints.maxWidth * 0.28).clamp(180.0, 320.0);
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Expanded(child: titleSide),
                    filterChips,
                    const SizedBox(width: WebTokens.s3),
                    _NewButton(onTap: _openCreate),
                    const SizedBox(width: WebTokens.s3),
                    SizedBox(
                      width: searchWidth,
                      child: _SearchInput(onChanged: _onSearchChanged),
                    ),
                  ],
                );
              },
            ),
          ),
          DecoratedBox(
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(color: t.borderSubtle, width: 1),
              ),
            ),
            child: const SizedBox(width: double.infinity, height: 0),
          ),
          Expanded(child: _buildTable(rows)),
        ],
      ),
    );
  }

  Widget _buildTable(List<SavedQueue> rows) {
    if (_loading && _queues == null) return const LoadingView();
    if (_error != null && _queues == null) {
      return ErrorView(error: _error!, onRetry: _load);
    }
    if (rows.isEmpty) {
      return const EmptyView(
        icon: Icons.bookmark_border,
        message: 'No saved queues',
      );
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        final tableWidth = constraints.maxWidth > _kTableMinWidth
            ? constraints.maxWidth
            : _kTableMinWidth;
        return Scrollbar(
          controller: _tableHScroll,
          scrollbarOrientation: ScrollbarOrientation.bottom,
          child: SingleChildScrollView(
            controller: _tableHScroll,
            scrollDirection: Axis.horizontal,
            child: SizedBox(
              width: tableWidth,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const _TableHeader(),
                  Expanded(
                    child: ListView.builder(
                      padding: EdgeInsets.zero,
                      itemCount: rows.length,
                      itemBuilder: (context, i) => _Row(
                        queue: rows[i],
                        onTap: () => _onTap(rows[i]),
                        onEdit: () => _openEdit(rows[i]),
                        onDelete: () => _confirmDelete(rows[i]),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Search + Back + New button + Filter chip
// ---------------------------------------------------------------------------

class _SearchInput extends StatefulWidget {
  const _SearchInput({required this.onChanged});
  final ValueChanged<String> onChanged;

  @override
  State<_SearchInput> createState() => _SearchInputState();
}

class _SearchInputState extends State<_SearchInput> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = WebTokens.of(context);
    final border = OutlineInputBorder(
      borderRadius: BorderRadius.circular(_kFlatRadius),
      borderSide: BorderSide(color: t.borderSubtle, width: 1),
    );
    return TextField(
      controller: _controller,
      onChanged: (v) {
        widget.onChanged(v);
        setState(() {});
      },
      style: t.bodyBase.copyWith(fontWeight: FontWeight.w500),
      decoration: InputDecoration(
        filled: true,
        fillColor: t.bgElevated,
        hoverColor: Colors.transparent,
        focusColor: Colors.transparent,
        border: border,
        enabledBorder: border,
        focusedBorder: border,
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: WebTokens.s4,
          vertical: 12,
        ),
        prefixIcon: Icon(Icons.search, size: 18, color: t.textSecondary),
        prefixIconConstraints:
            const BoxConstraints(minWidth: 40, minHeight: 20),
        hintText: 'Search queues…',
        hintStyle: t.bodyBase.copyWith(
          color: t.textSecondary,
          letterSpacing: -0.1,
        ),
      ),
    );
  }
}

class _BackButton extends StatefulWidget {
  const _BackButton({required this.onTap});
  final VoidCallback onTap;

  @override
  State<_BackButton> createState() => _BackButtonState();
}

class _BackButtonState extends State<_BackButton> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final t = WebTokens.of(context);
    return Tooltip(
      message: 'Back',
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: GestureDetector(
          onTap: widget.onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 100),
            width: 40,
            height: 40,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: _hover ? t.bgHover : t.bgElevated,
              borderRadius: BorderRadius.circular(WebTokens.rSm),
              border: Border.all(color: t.borderSubtle, width: 1),
            ),
            child: Icon(
              Icons.arrow_back_rounded,
              size: 18,
              color: t.textPrimary,
            ),
          ),
        ),
      ),
    );
  }
}

class _NewButton extends StatefulWidget {
  const _NewButton({required this.onTap});
  final VoidCallback onTap;

  @override
  State<_NewButton> createState() => _NewButtonState();
}

class _NewButtonState extends State<_NewButton> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final t = WebTokens.of(context);
    final bg = _hover ? WebTokens.accentHover : WebTokens.accent;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 100),
          height: 36,
          padding: const EdgeInsets.symmetric(horizontal: WebTokens.s4),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(_kFlatRadius),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.add,
                size: 16,
                color: WebTokens.textInverse,
              ),
              const SizedBox(width: WebTokens.s2),
              Text(
                'New queue',
                style: t.bodyBase.copyWith(
                  color: WebTokens.textInverse,
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

class _FilterChip extends StatefulWidget {
  const _FilterChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  State<_FilterChip> createState() => _FilterChipState();
}

class _FilterChipState extends State<_FilterChip> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final t = WebTokens.of(context);
    final bg = widget.selected
        ? WebTokens.accent
        : (_hover ? t.bgHover : t.bgTertiary);
    final fg = widget.selected ? WebTokens.textInverse : t.textSecondary;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 100),
          height: 32,
          padding: const EdgeInsets.symmetric(horizontal: WebTokens.s3),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(_kFlatRadius),
          ),
          child: Text(
            widget.label,
            style: t.bodySm.copyWith(
              color: fg,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Table
// ---------------------------------------------------------------------------

class _TableHeader extends StatelessWidget {
  const _TableHeader();

  @override
  Widget build(BuildContext context) {
    final t = WebTokens.of(context);
    return Container(
      color: t.bgElevated,
      padding: const EdgeInsets.symmetric(
        horizontal: WebTokens.s8,
        vertical: WebTokens.s3,
      ),
      child: Row(
        children: [
          Expanded(
            flex: _kColNameFlex,
            child: Text('Name', style: t.tableHeader),
          ),
          const SizedBox(width: _kColGap),
          SizedBox(
            width: _kColTypeWidth,
            child: Text('Type', style: t.tableHeader),
          ),
          const SizedBox(width: _kColGap),
          SizedBox(
            width: _kColScopeWidth,
            child: Text('Scope', style: t.tableHeader),
          ),
          const SizedBox(width: _kColGap),
          SizedBox(
            width: _kColFiltersWidth,
            child: Text(
              'Filters',
              style: t.tableHeader,
              textAlign: TextAlign.right,
            ),
          ),
          const SizedBox(width: _kColGap),
          const SizedBox(width: _kColActionsWidth),
        ],
      ),
    );
  }
}

class _Row extends StatefulWidget {
  const _Row({
    required this.queue,
    required this.onTap,
    required this.onEdit,
    required this.onDelete,
  });
  final SavedQueue queue;
  final VoidCallback onTap;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  State<_Row> createState() => _RowState();
}

class _RowState extends State<_Row> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final t = WebTokens.of(context);
    final q = widget.queue;
    final scopes = <String>[
      if (q.public) 'Public',
      if (q.personal) 'Personal',
    ];
    final scopeLabel = scopes.isEmpty ? 'System' : scopes.join(' · ');

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 80),
          decoration: BoxDecoration(
            color: _hover ? t.bgHover : t.bgElevated,
            border: Border(
              bottom: BorderSide(color: t.borderSubtle, width: 1),
            ),
          ),
          padding: const EdgeInsets.symmetric(
            horizontal: WebTokens.s8,
            vertical: WebTokens.s4,
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                flex: _kColNameFlex,
                child: Row(
                  children: [
                    Container(
                      width: 28,
                      height: 28,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: WebTokens.accent.withValues(alpha: 0.10),
                        borderRadius: BorderRadius.circular(WebTokens.rXs),
                      ),
                      child: Icon(
                        q.type == 'task'
                            ? Icons.task_alt
                            : Icons.confirmation_number_outlined,
                        size: 16,
                        color: WebTokens.accent,
                      ),
                    ),
                    const SizedBox(width: WebTokens.s3),
                    Expanded(
                      child: Text(
                        q.fullName.isEmpty ? '(unnamed)' : q.fullName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: t.bodyBase.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: _kColGap),
              SizedBox(
                width: _kColTypeWidth,
                child: _Pill(
                  label: q.type == 'task' ? 'Task' : 'Ticket',
                  tone: WebTokens.info,
                ),
              ),
              const SizedBox(width: _kColGap),
              SizedBox(
                width: _kColScopeWidth,
                child: Text(
                  scopeLabel,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: t.bodySm.copyWith(
                    color: t.textPrimary,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              const SizedBox(width: _kColGap),
              SizedBox(
                width: _kColFiltersWidth,
                child: Text(
                  '${q.criteria.length}',
                  textAlign: TextAlign.right,
                  style: t.bodySm
                      .copyWith(
                        color: t.textPrimary,
                        fontWeight: FontWeight.w500,
                      )
                      .withTabularNums(),
                ),
              ),
              const SizedBox(width: _kColGap),
              SizedBox(
                width: _kColActionsWidth,
                child: q.editable
                    ? PopupMenuButton<String>(
                        tooltip: 'Actions',
                        onSelected: (v) {
                          if (v == 'edit') widget.onEdit();
                          if (v == 'delete') widget.onDelete();
                        },
                        icon: Icon(
                          Icons.more_horiz,
                          size: 18,
                          color: t.textSecondary,
                        ),
                        itemBuilder: (_) => const [
                          PopupMenuItem(
                            value: 'edit',
                            child: Text('Rename'),
                          ),
                          PopupMenuItem(
                            value: 'delete',
                            child: Text('Delete'),
                          ),
                        ],
                      )
                    : const SizedBox.shrink(),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({required this.label, required this.tone});
  final String label;
  final Color tone;

  @override
  Widget build(BuildContext context) {
    final t = WebTokens.of(context);
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: tone.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(WebTokens.rXs),
        ),
        child: Text(
          label,
          style: t.bodySm.copyWith(
            color: tone,
            fontWeight: FontWeight.w600,
            fontSize: 12,
          ),
        ),
      ),
    );
  }
}
