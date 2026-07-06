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
import '../../../widgets/web/page_header.dart';
import '../../dashboard/web/_tokens.dart';
import 'user_detail_panel.dart';

// Column layout.
const int _kColUserFlex = 4;
const int _kColOrgFlex = 3;
const double _kColPhoneWidth = 160;
const double _kColCreatedWidth = 110;

const double _kColGap = 16;

/// Below this width the table horizontally scrolls.
const double _kTableMinWidth = 900;

/// Web-only users list. Uses the shared [PageHeader] + [ListSearchInput] and
/// mirrors the tickets table treatment (edge-to-edge, tinted header strip,
/// hover / selected row tint).
class UsersListScreenWeb extends ConsumerStatefulWidget {
  const UsersListScreenWeb({super.key});

  @override
  ConsumerState<UsersListScreenWeb> createState() =>
      _UsersListScreenWebState();
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
    final t = WebTokens.of(context);
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
                    width: 320,
                    child: ListSearchInput(
                      hintText: 'Search name, email, phone…',
                      onChanged: _onSearchChanged,
                    ),
                  ),
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
            flex: _kColUserFlex,
            child: Text('User', style: t.tableHeader),
          ),
          const SizedBox(width: _kColGap),
          Expanded(
            flex: _kColOrgFlex,
            child: Text('Organization', style: t.tableHeader),
          ),
          const SizedBox(width: _kColGap),
          SizedBox(
            width: _kColPhoneWidth,
            child: Text('Phone', style: t.tableHeader),
          ),
          const SizedBox(width: _kColGap),
          SizedBox(
            width: _kColCreatedWidth,
            child: Text(
              'Created',
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
    final t = WebTokens.of(context);
    final u = widget.user;
    final trimmed = u.name.trim();
    final initial = trimmed.isNotEmpty ? trimmed[0].toUpperCase() : '?';
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
                flex: _kColUserFlex,
                child: Row(
                  children: [
                    Container(
                      width: 30,
                      height: 30,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: WebTokens.accent.withValues(alpha: 0.10),
                        borderRadius: BorderRadius.circular(WebTokens.rFull),
                      ),
                      child: Text(
                        initial,
                        style: t.cardName.copyWith(
                          color: WebTokens.accent,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    const SizedBox(width: WebTokens.s3),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            trimmed.isEmpty ? '(unnamed)' : trimmed,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: t.bodyBase.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            u.email,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: t.bodySm,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: _kColGap),
              Expanded(
                flex: _kColOrgFlex,
                child: _TextCell(text: orgName),
              ),
              const SizedBox(width: _kColGap),
              SizedBox(
                width: _kColPhoneWidth,
                child: _TextCell(text: phone),
              ),
              const SizedBox(width: _kColGap),
              SizedBox(
                width: _kColCreatedWidth,
                child: Text(
                  Fmt.date(u.created),
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
