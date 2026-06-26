import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/api/api_exception.dart';
import '../../core/assets.dart';
import '../../core/router/routes.dart';
import '../../data/tickets_repository.dart';
import '../../providers.dart';
import '../../widgets/app_search_field.dart';
import '../../widgets/paged_list_view.dart';
import '../../widgets/segmented_tabs.dart';
import '../../widgets/svg_icon.dart';
import 'widgets/ticket_card.dart';

/// App filter pills (the `view` param on GET /tickets).
const _views = <({String key, String label})>[
  (key: 'open', label: 'Open'),
  (key: 'mine', label: 'Mine'),
  (key: 'unassigned', label: 'Unassigned'),
  (key: 'overdue', label: 'Overdue'),
  (key: 'answered', label: 'Answered'),
  (key: 'closed', label: 'Closed'),
];

class TicketsListScreen extends ConsumerStatefulWidget {
  const TicketsListScreen({super.key});

  @override
  ConsumerState<TicketsListScreen> createState() => _TicketsListScreenState();
}

class _TicketsListScreenState extends ConsumerState<TicketsListScreen> {
  String _view = 'open';
  String _search = '';
  final _searchCtrl = TextEditingController();
  int? _total;
  int _refresh = 0;
  bool _exporting = false;

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  void _toast(String msg) => ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(msg)));

  Future<void> _createTicket() async {
    await context.push(Routes.ticketNew);
    if (mounted) setState(() => _refresh++); // reflect any new ticket
  }

  Future<void> _exportCsv(TicketQuery query) async {
    setState(() => _exporting = true);
    try {
      final bytes = await ref.read(ticketsRepositoryProvider).exportCsv(query);
      final file = File('${Directory.systemTemp.path}/tickets-$_view.csv');
      await file.writeAsBytes(bytes);
      final rows = '\n'.allMatches(String.fromCharCodes(bytes)).length;
      if (!mounted) return;
      _toast('Exported ${rows > 0 ? rows - 1 : 0} tickets');
      await launchUrl(Uri.file(file.path));
    } on ApiException catch (e) {
      _toast(e.message);
    } catch (_) {
      _toast('Saved CSV but could not open it automatically');
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final repo = ref.watch(ticketsRepositoryProvider);
    final query = TicketQuery(
      view: _view,
      q: _search.isEmpty ? null : _search,
      sort: 'created',
      order: 'desc',
    );

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Tickets'),
            if (_total != null)
              Text('$_total total',
                  style: Theme.of(context).textTheme.bodySmall),
          ],
        ),
        actions: [
          IconButton(
            icon: const SvgIcon(Assets.bell, size: 22),
            onPressed: () => context.push(Routes.notifications),
          ),
          IconButton(
            tooltip: 'Export CSV',
            icon: _exporting
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2.4))
                : const Icon(Icons.download_outlined),
            onPressed: _exporting ? null : () => _exportCsv(query),
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(96),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                child: AppSearchField(
                  controller: _searchCtrl,
                  hintText: 'Search tickets or #number',
                  onSubmitted: (v) => setState(() => _search = v.trim()),
                  onClear: () => setState(() => _search = ''),
                ),
              ),
              SegmentedTabs(
                items: _views,
                selectedKey: _view,
                onSelected: (k) => setState(() => _view = k),
              ),
            ],
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _createTicket,
        tooltip: 'New ticket',
        child: const Icon(Icons.add),
      ),
      body: PagedListView(
        fabClearance: true,
        refreshKey: '$_view|$_search|$_refresh',
        onTotalChanged: (t) {
          if (mounted && t != _total) setState(() => _total = t);
        },
        emptyMessage: 'No tickets',
        emptyHint: 'Try a different filter or search.',
        fetch: (page) => repo.list(query.copyWith(page: page)),
        itemBuilder: (context, t) => TicketCard(
          ticket: t,
          onTap: () => context.push(Routes.ticket(t.id)),
        ),
      ),
    );
  }
}
