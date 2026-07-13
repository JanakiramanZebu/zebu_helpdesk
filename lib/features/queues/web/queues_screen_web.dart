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
import '../../../widgets/web/list_search_input.dart';
import '../../../widgets/web/list_table_shell.dart';
import '../../../widgets/web/page_header.dart';
import '../../../widgets/web/segmented_tab_bar.dart';
import '../../dashboard/web/_tokens.dart';
import 'queue_editor_dialog.dart';

const _kFlatRadius = 8.0;

const int _kColNameFlex = 4;
const double _kColTypeWidth = 110;
const double _kColScopeWidth = 130;
const double _kColFiltersWidth = 110;
const double _kColActionsWidth = 60;
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

    // Map the current type filter to a tab key so SegmentedTabBar's
    // selected value is a plain string ('all' / 'ticket' / 'task').
    final selectedTab = _type ?? 'all';
    return ColoredBox(
      color: t.bgPrimary,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          PageHeader(
            title: 'Saved queues',
            subtitle: _queues != null ? '${all.length} total' : null,
            leading: _BackButton(
              onTap: () {
                if (context.canPop()) {
                  context.pop();
                } else {
                  context.go(Routes.more);
                }
              },
            ),
            trailing: LayoutBuilder(
              builder: (context, c) {
                final filterAllowance = 152.0; // new button + gap
                final available =
                    c.hasBoundedWidth ? c.maxWidth - filterAllowance : 320.0;
                final searchWidth = available.clamp(180.0, 320.0);
                return Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _NewButton(onTap: _openCreate),
                    const SizedBox(width: WebTokens.s3),
                    SizedBox(
                      width: searchWidth,
                      child: ListSearchInput(
                        hintText: 'Search queues…',
                        onChanged: _onSearchChanged,
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
          SegmentedTabBar<String>(
            items: const [
              SegmentedTabItem(value: 'all', label: 'All'),
              SegmentedTabItem(value: 'ticket', label: 'Tickets'),
              SegmentedTabItem(value: 'task', label: 'Tasks'),
            ],
            selected: selectedTab,
            onSelect: (k) => _setType(k == 'all' ? null : k),
          ),
          Expanded(child: ListTableShell(child: _buildTable(rows))),
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
        final horizontalScroll = constraints.maxWidth <= _kTableMinWidth;
        final tableWidth =
            horizontalScroll ? _kTableMinWidth : constraints.maxWidth;
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
                  _TableHeader(scrollGutter: horizontalScroll),
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
// Back + New button
// ---------------------------------------------------------------------------

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
    final bg = _hover ? t.accentHover : t.accent;
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

// ---------------------------------------------------------------------------
// Table header — matches the tickets table: edge-to-edge, hairline
// top/bottom borders, and per-column right-border creating the vertical
// grid line that body rows align to pixel-for-pixel.
// ---------------------------------------------------------------------------

class _TableHeader extends StatelessWidget {
  const _TableHeader({this.scrollGutter = false});

  final bool scrollGutter;

  @override
  Widget build(BuildContext context) {
    final t = WebTokens.of(context);
    return Container(
      decoration: BoxDecoration(
        color: t.bgElevated,
        border: Border(
          top: BorderSide(color: t.borderSubtle, width: 1),
          bottom: BorderSide(color: t.borderSubtle, width: 1),
        ),
      ),
      child: IntrinsicHeight(
        child: Row(
          children: [
            const _HeaderCell(flex: _kColNameFlex, label: 'Name'),
            const _HeaderCell(width: _kColTypeWidth, label: 'Type'),
            const _HeaderCell(width: _kColScopeWidth, label: 'Scope'),
            const _HeaderCell(
              width: _kColFiltersWidth,
              label: 'Filters',
              alignRight: true,
            ),
            const _HeaderCell(
              width: _kColActionsWidth,
              label: '',
              last: true,
            ),
            if (scrollGutter) const SizedBox(width: 10),
          ],
        ),
      ),
    );
  }
}

/// Column header cell — mirrors the tickets `_HeaderCell`.
class _HeaderCell extends StatelessWidget {
  const _HeaderCell({
    required this.label,
    this.flex,
    this.width,
    this.last = false,
    this.alignRight = false,
  });
  final String label;
  final int? flex;
  final double? width;
  final bool last;
  final bool alignRight;

  @override
  Widget build(BuildContext context) {
    final t = WebTokens.of(context);
    final content = Container(
      padding: const EdgeInsets.symmetric(
        horizontal: WebTokens.s3,
        vertical: WebTokens.s3,
      ),
      decoration: BoxDecoration(
        border: last
            ? null
            : Border(right: BorderSide(color: t.borderSubtle, width: 1)),
      ),
      alignment: alignRight ? Alignment.centerRight : Alignment.centerLeft,
      child: Text(
        label,
        maxLines: 1,
        softWrap: false,
        overflow: TextOverflow.ellipsis,
        style: t.tableHeader,
        textAlign: alignRight ? TextAlign.right : TextAlign.left,
      ),
    );
    if (flex != null) return Expanded(flex: flex!, child: content);
    if (width != null) return SizedBox(width: width!, child: content);
    return content;
  }
}

/// Body cell — mirrors the tickets `_BodyCell`.
class _BodyCell extends StatelessWidget {
  const _BodyCell({
    required this.child,
    this.flex,
    this.width,
    this.last = false,
    this.alignRight = false,
  });
  final Widget child;
  final int? flex;
  final double? width;
  final bool last;
  final bool alignRight;

  @override
  Widget build(BuildContext context) {
    final t = WebTokens.of(context);
    final content = Container(
      padding: const EdgeInsets.symmetric(
        horizontal: WebTokens.s3,
        vertical: 8,
      ),
      decoration: BoxDecoration(
        border: last
            ? null
            : Border(right: BorderSide(color: t.borderSubtle, width: 1)),
      ),
      alignment: alignRight ? Alignment.centerRight : Alignment.centerLeft,
      child: child,
    );
    if (flex != null) return Expanded(flex: flex!, child: content);
    if (width != null) return SizedBox(width: width!, child: content);
    return content;
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
          child: IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _BodyCell(
                  flex: _kColNameFlex,
                  child: Text(
                    q.fullName.isEmpty ? '(unnamed)' : q.fullName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: t.bodyBase.copyWith(
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                _BodyCell(
                  width: _kColTypeWidth,
                  child: _Pill(
                    label: q.type == 'task' ? 'Task' : 'Ticket',
                    tone: WebTokens.info,
                  ),
                ),
                _BodyCell(
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
                _BodyCell(
                  width: _kColFiltersWidth,
                  alignRight: true,
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
                _BodyCell(
                  width: _kColActionsWidth,
                  last: true,
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
