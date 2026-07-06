import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/format.dart';
import '../../../core/router/routes.dart';
import '../../../models/canned.dart';
import '../../../providers.dart';
import '../../../widgets/paged_list_view.dart';
import '../../../widgets/slide_over_host.dart';
import '../../../widgets/web/list_search_input.dart';
import '../../../widgets/web/page_header.dart';
import '../../dashboard/web/_tokens.dart';
import 'canned_detail_panel.dart';
import 'canned_editor_dialog.dart';

// Column layout — header and rows share these so the grid lines up
// pixel-for-pixel. Title / preview flex; scope / status are fixed.
const int _kColTitleFlex = 3;
const int _kColPreviewFlex = 5;
const double _kColScopeWidth = 110;
const double _kColStatusWidth = 110;
const double _kColGap = 16;

/// Below this, the table horizontally scrolls under a shared controller.
const double _kTableMinWidth = 900;

/// Web-only canned-responses list, styled to match [OrgsListScreenWeb] and
/// [UsersListScreenWeb]: hero header, right-aligned search input, and an
/// edge-to-edge table (header strip + one row per response) with hover /
/// select tints. Opens a slide-over [CannedDetailPanel] on row tap.
class CannedScreenWeb extends ConsumerStatefulWidget {
  const CannedScreenWeb({super.key});

  @override
  ConsumerState<CannedScreenWeb> createState() => _CannedScreenWebState();
}

class _CannedScreenWebState extends ConsumerState<CannedScreenWeb> {
  String _search = '';
  Timer? _debounce;
  int _refreshKey = 0;
  int? _total;
  int? _openId;
  bool _fullscreen = false;

  final ScrollController _tableHScroll = ScrollController();

  void _openResponse(int id) => setState(() => _openId = id);
  void _closeResponse() => setState(() {
        _openId = null;
        _fullscreen = false;
      });
  void _toggleFullscreen() => setState(() => _fullscreen = !_fullscreen);

  void _onChanged() {
    if (mounted) setState(() => _refreshKey++);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _tableHScroll.dispose();
    super.dispose();
  }

  void _onSearchChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () {
      final next = value.trim();
      if (next != _search && mounted) {
        setState(() {
          _search = next;
          _refreshKey++;
        });
      }
    });
  }

  Future<void> _openCreate() async {
    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => const CannedEditorDialog(),
    );
    if (saved == true && mounted) {
      setState(() => _refreshKey++);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = WebTokens.of(context);
    final repo = ref.watch(cannedRepositoryProvider);

    return SlideOverHost(
      openId: _openId,
      onClose: _closeResponse,
      fullscreen: _fullscreen,
      panelBuilder: (context, id, close) => CannedDetailPanel(
        cannedId: id,
        onClose: close,
        onChanged: _onChanged,
        isFullscreen: _fullscreen,
        onToggleFullscreen: _toggleFullscreen,
      ),
      child: ColoredBox(
        color: t.bgPrimary,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            PageHeader(
              title: 'Canned responses',
              subtitle: _total != null ? '$_total total' : null,
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
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
                  SizedBox(
                    width: 280,
                    child: ListSearchInput(
                      hintText: 'Search title or body…',
                      onChanged: _onSearchChanged,
                    ),
                  ),
                  const SizedBox(width: WebTokens.s3),
                  _NewButton(onTap: _openCreate),
                ],
              ),
            ),
            Expanded(
              child: LayoutBuilder(
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
                              child: ColoredBox(
                                color: t.bgElevated,
                                child: PagedListView<CannedResponse>(
                                  padding: EdgeInsets.zero,
                                  refreshKey: '$_search|$_refreshKey',
                                  emptyMessage: 'No canned responses',
                                  emptyHint: 'Create one to get started.',
                                  emptyIcon: Icons.quickreply_outlined,
                                  onTotalChanged: (v) {
                                    if (mounted && v != _total) {
                                      setState(() => _total = v);
                                    }
                                  },
                                  fetch: (page) async {
                                    final res = await repo.list(page: page);
                                    if (_search.isEmpty) return res;
                                    final q = _search.toLowerCase();
                                    final filtered = res.items
                                        .where((c) =>
                                            c.title.toLowerCase().contains(q) ||
                                            Fmt.stripHtml(c.body)
                                                .toLowerCase()
                                                .contains(q))
                                        .toList();
                                    return res.copyWithItems(filtered);
                                  },
                                  itemBuilder: (context, c) => _Row(
                                    canned: c,
                                    selected: _openId == c.id,
                                    onTap: () => _openResponse(c.id),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Back button — small ghost square matching top-bar action treatment.
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

// ---------------------------------------------------------------------------
// "New response" button — accent-tinted pill.
// ---------------------------------------------------------------------------

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
          height: 40,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(WebTokens.rSm),
            boxShadow: _hover
                ? const [
                    BoxShadow(
                      color: Color(0x330037B7),
                      blurRadius: 12,
                      offset: Offset(0, 3),
                    ),
                  ]
                : null,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.add_rounded,
                size: 18,
                color: WebTokens.textInverse,
              ),
              const SizedBox(width: 6),
              Text(
                'New response',
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
// Table header
// ---------------------------------------------------------------------------

class _TableHeader extends StatelessWidget {
  const _TableHeader();

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
      padding: const EdgeInsets.symmetric(
        horizontal: WebTokens.s8,
        vertical: WebTokens.s3,
      ),
      child: Row(
        children: [
          Expanded(
            flex: _kColTitleFlex,
            child: Text('Title', style: t.tableHeader),
          ),
          const SizedBox(width: _kColGap),
          Expanded(
            flex: _kColPreviewFlex,
            child: Text('Preview', style: t.tableHeader),
          ),
          const SizedBox(width: _kColGap),
          SizedBox(
            width: _kColScopeWidth,
            child: Text(
              'Scope',
              style: t.tableHeader,
              textAlign: TextAlign.right,
            ),
          ),
          const SizedBox(width: _kColGap),
          SizedBox(
            width: _kColStatusWidth,
            child: Text(
              'Status',
              style: t.tableHeader,
              textAlign: TextAlign.right,
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Row
// ---------------------------------------------------------------------------

class _Row extends StatefulWidget {
  const _Row({
    required this.canned,
    required this.onTap,
    this.selected = false,
  });
  final CannedResponse canned;
  final VoidCallback onTap;
  final bool selected;

  @override
  State<_Row> createState() => _RowState();
}

class _RowState extends State<_Row> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final t = WebTokens.of(context);
    final c = widget.canned;
    final preview = Fmt.stripHtml(c.body).trim();

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
            color: widget.selected
                ? t.accentMuted
                : (_hover ? t.bgHover : t.bgElevated),
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
                flex: _kColTitleFlex,
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
                        Icons.quickreply_outlined,
                        size: 16,
                        color: WebTokens.accent,
                      ),
                    ),
                    const SizedBox(width: WebTokens.s3),
                    Expanded(
                      child: Text(
                        c.title.trim().isEmpty ? '(untitled)' : c.title,
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
              Expanded(
                flex: _kColPreviewFlex,
                child: _TextCell(text: preview),
              ),
              const SizedBox(width: _kColGap),
              SizedBox(
                width: _kColScopeWidth,
                child: Align(
                  alignment: Alignment.centerRight,
                  child: _Pill(
                    label: c.isGlobal ? 'Global' : 'Dept',
                    tone: c.isGlobal ? WebTokens.info : t.textSecondary,
                  ),
                ),
              ),
              const SizedBox(width: _kColGap),
              SizedBox(
                width: _kColStatusWidth,
                child: Align(
                  alignment: Alignment.centerRight,
                  child: _Pill(
                    label: c.isEnabled ? 'Enabled' : 'Disabled',
                    tone: c.isEnabled ? WebTokens.success : WebTokens.danger,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TextCell extends StatelessWidget {
  const _TextCell({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final t = WebTokens.of(context);
    final empty = text.trim().isEmpty;
    return Text(
      empty ? '—' : text,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: t.bodySm.copyWith(
        color: empty ? t.textSecondary : t.textPrimary,
        fontWeight: empty ? FontWeight.w400 : FontWeight.w500,
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
    return Container(
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
    );
  }
}
