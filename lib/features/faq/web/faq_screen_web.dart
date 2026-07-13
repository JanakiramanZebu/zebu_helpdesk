import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/format.dart';
import '../../../core/router/routes.dart';
import '../../../models/faq.dart';
import '../../../providers.dart';
import '../../../widgets/paged_list_view.dart';
import '../../../widgets/slide_over_host.dart';
import '../../../widgets/web/list_search_input.dart';
import '../../../widgets/web/list_table_shell.dart';
import '../../../widgets/web/page_header.dart';
import '../../dashboard/web/_tokens.dart';
import 'faq_detail_panel.dart';

const int _kColQuestionFlex = 5;
const int _kColCategoryFlex = 2;
const double _kColTypeWidth = 110;
const double _kColUpdatedWidth = 120;
const double _kTableMinWidth = 900;

/// Web-only Knowledgebase list. Flat article list (search-filtered), styled
/// to match [OrgsListScreenWeb]. Opens a slide-over [FaqDetailPanel] on row
/// tap.
class FaqScreenWeb extends ConsumerStatefulWidget {
  const FaqScreenWeb({super.key});

  @override
  ConsumerState<FaqScreenWeb> createState() => _FaqScreenWebState();
}

class _FaqScreenWebState extends ConsumerState<FaqScreenWeb> {
  String _search = '';
  Timer? _debounce;
  int _refreshKey = 0;
  int? _total;
  int? _openId;
  bool _fullscreen = false;

  final ScrollController _tableHScroll = ScrollController();

  void _openFaq(int id) => setState(() => _openId = id);
  void _closeFaq() => setState(() {
        _openId = null;
        _fullscreen = false;
      });
  void _toggleFullscreen() => setState(() => _fullscreen = !_fullscreen);

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

  @override
  Widget build(BuildContext context) {
    final t = WebTokens.of(context);
    final repo = ref.watch(faqRepositoryProvider);

    return SlideOverHost(
      openId: _openId,
      onClose: _closeFaq,
      fullscreen: _fullscreen,
      panelBuilder: (context, id, close) => FaqDetailPanel(
        faqId: id,
        onClose: close,
        isFullscreen: _fullscreen,
        onToggleFullscreen: _toggleFullscreen,
      ),
      child: ColoredBox(
        color: t.bgPrimary,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            PageHeader(
              title: 'Knowledgebase',
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
              trailing: SizedBox(
                width: 320,
                child: ListSearchInput(
                  hintText: 'Search articles…',
                  onChanged: _onSearchChanged,
                ),
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
                                child: PagedListView<Faq>(
                                  padding: EdgeInsets.zero,
                                  refreshKey: '$_search|$_refreshKey',
                                  emptyMessage: 'No articles',
                                  emptyHint: 'Try a different search.',
                                  emptyIcon: Icons.menu_book_outlined,
                                  onTotalChanged: (v) {
                                    if (mounted && v != _total) {
                                      setState(() => _total = v);
                                    }
                                  },
                                  fetch: (page) => repo.search(
                                    q: _search.isEmpty ? null : _search,
                                    page: page,
                                  ),
                                  itemBuilder: (context, f) => _Row(
                                    faq: f,
                                    selected: _openId == f.id,
                                    onTap: () => _openFaq(f.id),
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
            const _HeaderCell(flex: _kColQuestionFlex, label: 'Question'),
            const _HeaderCell(flex: _kColCategoryFlex, label: 'Category'),
            const _HeaderCell(
              width: _kColTypeWidth,
              label: 'Type',
              alignRight: true,
            ),
            const _HeaderCell(
              width: _kColUpdatedWidth,
              label: 'Updated',
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
    required this.faq,
    required this.onTap,
    this.selected = false,
  });
  final Faq faq;
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
    final f = widget.faq;

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
                  flex: _kColQuestionFlex,
                  child: Text(
                    f.question.trim().isEmpty ? '(untitled)' : f.question,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: t.bodyBase.copyWith(
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                _BodyCell(
                  flex: _kColCategoryFlex,
                  child: _TextCell(text: f.category?.name ?? ''),
                ),
                _BodyCell(
                  width: _kColTypeWidth,
                  alignRight: true,
                  child: _Pill(
                    label: f.published ? 'Public' : 'Internal',
                    tone: f.published ? WebTokens.success : t.textSecondary,
                  ),
                ),
                _BodyCell(
                  width: _kColUpdatedWidth,
                  last: true,
                  alignRight: true,
                  child: Text(
                    Fmt.date(f.updated),
                    maxLines: 1,
                    softWrap: false,
                    overflow: TextOverflow.clip,
                    textAlign: TextAlign.right,
                    style: t.bodySm
                        .copyWith(
                          color: t.textPrimary,
                          fontWeight: FontWeight.w500,
                        )
                        .withTabularNums(),
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
