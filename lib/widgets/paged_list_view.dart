import 'package:flutter/material.dart';

import '../core/api/paginated.dart';
import 'states.dart';

/// A reusable infinite-scroll + pull-to-refresh list backed by a paginated
/// fetcher. Change [refreshKey] (e.g. when filters change) to reset and reload.
class PagedListView<T> extends StatefulWidget {
  const PagedListView({
    super.key,
    required this.fetch,
    required this.itemBuilder,
    this.emptyMessage = 'Nothing here yet',
    this.emptyHint,
    this.emptyIcon = Icons.inbox_outlined,
    this.refreshKey,
    this.padding = const EdgeInsets.symmetric(vertical: 6),
    this.header,
    this.onTotalChanged,
    this.fabClearance = false,
  });

  final Future<Paginated<T>> Function(int page) fetch;
  final Widget Function(BuildContext context, T item) itemBuilder;
  final String emptyMessage;
  final String? emptyHint;
  final IconData emptyIcon;

  /// Reset the list whenever this value changes.
  final Object? refreshKey;
  final EdgeInsets padding;

  /// Optional non-scrolling header rendered above the list.
  final Widget? header;
  final ValueChanged<int>? onTotalChanged;

  /// Add extra bottom padding so a [FloatingActionButton] doesn't cover the
  /// last item.
  final bool fabClearance;

  @override
  State<PagedListView<T>> createState() => _PagedListViewState<T>();
}

class _PagedListViewState<T> extends State<PagedListView<T>> {
  final _scroll = ScrollController();
  final List<T> _items = [];
  int _page = 1;
  bool _loading = false;
  bool _hasMore = true;
  Object? _error;
  bool _initial = true;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
    _load(reset: true);
  }

  @override
  void didUpdateWidget(covariant PagedListView<T> old) {
    super.didUpdateWidget(old);
    if (old.refreshKey != widget.refreshKey) {
      _load(reset: true);
    }
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scroll.position.pixels >=
        _scroll.position.maxScrollExtent - 320) {
      _load();
    }
  }

  Future<void> _load({bool reset = false}) async {
    if (_loading) return;
    if (!reset && !_hasMore) return;
    setState(() {
      _loading = true;
      if (reset) {
        _initial = true;
        _error = null;
        _page = 1;
        _hasMore = true;
        _items.clear();
      }
    });
    try {
      final result = await widget.fetch(_page);
      if (!mounted) return;
      setState(() {
        _items.addAll(result.items);
        _hasMore = result.hasMore && result.items.isNotEmpty;
        _page += 1;
        _initial = false;
      });
      widget.onTotalChanged?.call(result.total);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> refresh() => _load(reset: true);

  @override
  Widget build(BuildContext context) {
    if (_initial && _loading) return const LoadingView();
    if (_error != null && _items.isEmpty) {
      return ErrorView(error: _error!, onRetry: () => _load(reset: true));
    }

    // Respect the system bottom inset (gesture bar / home indicator) and add
    // FAB clearance where requested so content never hides behind chrome.
    final bottomInset = MediaQuery.of(context).padding.bottom;
    final listPadding = widget.padding.add(
      EdgeInsets.only(bottom: bottomInset + (widget.fabClearance ? 80 : 0)),
    );

    final body = (_items.isEmpty)
        ? ListView(
            children: [
              if (widget.header != null) widget.header!,
              SizedBox(
                height: 360,
                child: EmptyView(
                  icon: widget.emptyIcon,
                  message: widget.emptyMessage,
                  hint: widget.emptyHint,
                ),
              ),
            ],
          )
        : ListView.builder(
            controller: _scroll,
            padding: listPadding,
            itemCount: _items.length +
                (widget.header != null ? 1 : 0) +
                (_hasMore ? 1 : 0),
            itemBuilder: (context, index) {
              var i = index;
              if (widget.header != null) {
                if (i == 0) return widget.header!;
                i -= 1;
              }
              if (i >= _items.length) {
                return const Padding(
                  padding: EdgeInsets.all(16),
                  child: Center(
                    child: SizedBox(
                      height: 22,
                      width: 22,
                      child: CircularProgressIndicator(strokeWidth: 2.2),
                    ),
                  ),
                );
              }
              return widget.itemBuilder(context, _items[i]);
            },
          );

    return RefreshIndicator(onRefresh: refresh, child: body);
  }
}
