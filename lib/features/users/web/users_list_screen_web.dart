import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/format.dart';
import '../../../core/router/routes.dart';
import '../../../models/user.dart';
import '../../../providers.dart';
import '../../../widgets/paged_list_view.dart';
import '../../../widgets/slide_over_host.dart';
import '../../../widgets/web/list_search_input.dart';
import '../../../widgets/web/list_table_shell.dart';
import '../../../widgets/web/page_header.dart';
import 'user_detail_panel.dart';
import '../../../res/zebu_text_styles.dart';
import '../../../res/zebu_theme.dart';
import '../../../res/zebu_spacing.dart';

// Column layout — header and every row share these so the vertical grid
// lines up pixel-for-pixel. Mirrors the tickets table cell API.
const int _kColUserFlex = 4;
const int _kColOrgFlex = 3;
const double _kColPhoneWidth = 160;
const double _kColCreatedWidth = 120;

/// Below this width the table horizontally scrolls.
const double _kTableMinWidth = 900;

/// Web-only users list. Uses the shared [PageHeader] + [ListSearchInput] and
/// mirrors the tickets table treatment (edge-to-edge, tinted header strip,
/// hover / selected row tint).
class UsersListScreenWeb extends ConsumerStatefulWidget {
  const UsersListScreenWeb({super.key});

  @override
  ConsumerState<UsersListScreenWeb> createState() => _UsersListScreenWebState();
}

class _UsersListScreenWebState extends ConsumerState<UsersListScreenWeb> {
  String _search = '';
  Timer? _debounce;
  int _refreshKey = 0;
  int? _total;
  int? _openUserId;
  bool _fullscreen = false;

  final ScrollController _tableHScroll = ScrollController();

  void _openUser(int id) => setState(() => _openUserId = id);
  void _closeUser() => setState(() {
    _openUserId = null;
    _fullscreen = false;
  });
  void _toggleFullscreen() => setState(() => _fullscreen = !_fullscreen);

  void _onUserChanged() {
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

  @override
  Widget build(BuildContext context) {
    final t = ZebuTheme.of(context);
    final repo = ref.watch(usersRepositoryProvider);

    return SlideOverHost(
      openId: _openUserId,
      onClose: _closeUser,
      fullscreen: _fullscreen,
      panelBuilder: (context, id, close) => UserDetailPanel(
        userId: id,
        onClose: close,
        onChanged: _onUserChanged,
        isFullscreen: _fullscreen,
        onToggleFullscreen: _toggleFullscreen,
      ),
      child: ColoredBox(
        color: t.bgPrimary,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            PageHeader(
              title: 'Users',
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
                  hintText: 'Search name, email, phone…',
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
                                  child: PagedListView<AppUser>(
                                    padding: EdgeInsets.zero,
                                    refreshKey: '$_search|$_refreshKey',
                                    emptyMessage: 'No users',
                                    emptyHint: 'Try a different search.',
                                    emptyIcon: Icons.people_outline,
                                    onTotalChanged: (v) {
                                      if (mounted && v != _total) {
                                        setState(() => _total = v);
                                      }
                                    },
                                    fetch: (page) => repo.list(
                                      q: _search.isEmpty ? null : _search,
                                      page: page,
                                    ),
                                    itemBuilder: (context, u) => _UserRow(
                                      user: u,
                                      selected: _openUserId == u.id,
                                      onTap: () => _openUser(u.id),
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
// Back button — small ghost square that matches the top-bar action treatment.
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
// Table header — matches the tickets table: edge-to-edge, hairline
// top/bottom borders, and per-column right-border creating the vertical
// grid line that body rows align to pixel-for-pixel.
// ---------------------------------------------------------------------------

class _TableHeader extends StatelessWidget {
  const _TableHeader({this.scrollGutter = false});

  /// When true, reserves 10 px of trailing space at the right edge of the
  /// header to line up with the horizontal scrollbar sitting under the body.
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
            const _HeaderCell(flex: _kColUserFlex, label: 'User'),
            const _HeaderCell(flex: _kColOrgFlex, label: 'Organization'),
            const _HeaderCell(width: _kColPhoneWidth, label: 'Phone'),
            const _HeaderCell(
              width: _kColCreatedWidth,
              label: 'Created',
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

/// Column header cell — mirrors the tickets `_HeaderCell` exactly so both
/// tables read as one grid: hairline right border (except on the last
/// cell), `s3` horizontal padding, `tableHeader` typography.
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

/// Body cell — mirrors the tickets `_BodyCell`. Right-border creates the
/// vertical grid line; 8 px vertical padding gives the same table rhythm.
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
// User row
// ---------------------------------------------------------------------------

class _UserRow extends StatefulWidget {
  const _UserRow({
    required this.user,
    required this.onTap,
    this.selected = false,
  });
  final AppUser user;
  final VoidCallback onTap;
  final bool selected;

  @override
  State<_UserRow> createState() => _UserRowState();
}

class _UserRowState extends State<_UserRow> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final t = ZebuTheme.of(context);
    final u = widget.user;
    final trimmed = u.name.trim();
    final orgName = u.org?.name.trim() ?? '';
    final phone = (u.phone ?? '').trim();

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
            border: Border(bottom: BorderSide(color: t.borderSubtle, width: 1)),
          ),
          child: IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Primary column mirrors the tickets `Ticket` column:
                // accent-blue leading identifier (email) + main label
                // (name), inline on a single line so row height matches
                // the tickets table pixel-for-pixel.
                _BodyCell(
                  flex: _kColUserFlex,
                  child: Row(
                    children: [
                      Flexible(
                        child: Text(
                          u.email,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: ZebuTextStyles.small(context).copyWith(
                            fontWeight: FontWeight.w600,
                            color: t.accent,
                          ),
                        ),
                      ),
                      const SizedBox(width: ZebuSpacing.s2),
                      Flexible(
                        child: Text(
                          trimmed.isEmpty ? '(unnamed)' : trimmed,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: ZebuTextStyles.body(
                            context,
                          ).copyWith(fontWeight: FontWeight.w500),
                        ),
                      ),
                    ],
                  ),
                ),
                _BodyCell(
                  flex: _kColOrgFlex,
                  child: _TextCell(text: orgName),
                ),
                _BodyCell(
                  width: _kColPhoneWidth,
                  child: _TextCell(text: phone),
                ),
                _BodyCell(
                  width: _kColCreatedWidth,
                  last: true,
                  alignRight: true,
                  child: Text(
                    Fmt.date(u.created),
                    maxLines: 1,
                    softWrap: false,
                    overflow: TextOverflow.clip,
                    textAlign: TextAlign.right,
                    style: ZebuTextStyles.small(context)
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
