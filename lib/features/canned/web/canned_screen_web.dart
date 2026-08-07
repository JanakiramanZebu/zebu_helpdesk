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
import '../../../widgets/web/list_table_shell.dart';
import '../../../widgets/web/page_header.dart';
import 'canned_detail_panel.dart';
import 'canned_editor_dialog.dart';
import '../../../res/zebu_text_styles.dart';
import '../../../res/zebu_theme.dart';
import '../../../res/zebu_spacing.dart';

// Column layout — header and rows share these so the vertical grid lines
// up pixel-for-pixel. Mirrors the tickets table cell API.
const int _kColTitleFlex = 3;
const int _kColPreviewFlex = 5;
const double _kColScopeWidth = 110;
const double _kColStatusWidth = 110;

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
    final t = ZebuTheme.of(context);
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
              leading: _BackButton(
                onTap: () {
                  if (context.canPop()) {
                    context.pop();
                  } else {
                    context.go(Routes.more);
                  }
                },
              ),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    width: 280,
                    child: ListSearchInput(
                      hintText: 'Search title or body…',
                      onChanged: _onSearchChanged,
                    ),
                  ),
                  const SizedBox(width: ZebuSpacing.s3),
                  _NewButton(onTap: _openCreate),
                ],
              ),
            ),
            Expanded(
              child: ListTableShell(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final horizontalScroll =
                        constraints.maxWidth <= _kTableMinWidth;
                    final tableWidth = horizontalScroll
                        ? _kTableMinWidth
                        : constraints.maxWidth;
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
    final t = ZebuTheme.of(context);
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
              borderRadius: BorderRadius.circular(ZebuRadius.rSm),
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
    final t = ZebuTheme.of(context);
    final bg = _hover ? t.accentHover : t.accent;
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
            borderRadius: BorderRadius.circular(ZebuRadius.rSm),
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
                color: ZebuTheme.textInverse,
              ),
              const SizedBox(width: 6),
              Text(
                'New response',
                style: ZebuTextStyles.body(context).copyWith(
                  color: ZebuTheme.textInverse,
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
    final t = ZebuTheme.of(context);
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
            const _HeaderCell(flex: _kColTitleFlex, label: 'Title'),
            const _HeaderCell(flex: _kColPreviewFlex, label: 'Preview'),
            const _HeaderCell(
              width: _kColScopeWidth,
              label: 'Scope',
              alignRight: true,
            ),
            const _HeaderCell(
              width: _kColStatusWidth,
              label: 'Status',
              alignRight: true,
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
    final t = ZebuTheme.of(context);
    final content = Container(
      padding: const EdgeInsets.symmetric(
        horizontal: ZebuSpacing.s3,
        vertical: ZebuSpacing.s3,
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
        style: ZebuTextStyles.tableHeader(context),
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
    final t = ZebuTheme.of(context);
    final content = Container(
      padding: const EdgeInsets.symmetric(
        horizontal: ZebuSpacing.s3,
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
    final t = ZebuTheme.of(context);
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
          child: IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _BodyCell(
                  flex: _kColTitleFlex,
                  child: Text(
                    c.title.trim().isEmpty ? '(untitled)' : c.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: ZebuTextStyles.body(context).copyWith(
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                _BodyCell(
                  flex: _kColPreviewFlex,
                  child: _TextCell(text: preview),
                ),
                _BodyCell(
                  width: _kColScopeWidth,
                  alignRight: true,
                  child: _Pill(
                    label: c.isGlobal ? 'Global' : 'Dept',
                    tone: c.isGlobal ? ZebuTheme.info : t.textSecondary,
                  ),
                ),
                _BodyCell(
                  width: _kColStatusWidth,
                  last: true,
                  alignRight: true,
                  child: _Pill(
                    label: c.isEnabled ? 'Enabled' : 'Disabled',
                    tone: c.isEnabled ? ZebuTheme.success : t.danger,
                  ),
                ),
              ],
            ),
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
    final t = ZebuTheme.of(context);
    final empty = text.trim().isEmpty;
    return Text(
      empty ? '—' : text,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: ZebuTextStyles.small(context).copyWith(
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
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: tone.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(ZebuRadius.rXs),
      ),
      child: Text(
        label,
        style: ZebuTextStyles.small(context).copyWith(
          color: tone,
          fontWeight: FontWeight.w600,
          fontSize: 12,
        ),
      ),
    );
  }
}
