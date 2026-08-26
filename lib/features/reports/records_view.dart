import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api_exception.dart';
import '../../core/export/csv.dart';
import '../../core/export/table_export.dart';
import '../../core/format.dart';
import '../../core/theme/app_text.dart';
import '../../core/theme/app_theme.dart';
import '../../models/meta.dart';
import '../../models/reports.dart';
import '../../providers.dart';
import '../../widgets/app_snack.dart';
import '../../widgets/date_picker_sheet.dart';
import '../../widgets/multi_select_sheet.dart';
import '../../widgets/skeleton.dart';
import '../../widgets/states.dart';
import 'report_spec.dart';
import 'widgets/report_pieces.dart';

/// Record exports — the mobile port of `scp/reports.php`.
///
/// Same shape as that page: a record-type tab strip carrying each type's
/// visible count, the filters that type supports, a column grid with All /
/// None, and a download.
///
/// Everything variable is served rather than hard-coded. `GET /reports/exports`
/// gives the four types and their counts; `GET /reports/exports/{type}/fields`
/// gives that type's filter set and its full column catalog, custom form
/// fields included — so an install that adds a ticket field gets it here with
/// no app change.
///
/// The file itself never travels through the JSON client: the export is minted
/// as an HMAC-signed link and fetched from `GET /reports/download`. That link
/// lives 300 seconds, so it is fetched immediately and never stored — and it is
/// written out verbatim, BOM and quoting included, because the server's CSV is
/// the deliverable. The web offers no other format and neither does this.
class RecordsExportView extends ConsumerStatefulWidget {
  const RecordsExportView({super.key});

  @override
  ConsumerState<RecordsExportView> createState() => _RecordsExportViewState();
}

class _RecordsExportViewState extends ConsumerState<RecordsExportView> {
  ReportType _type = ReportType.tickets;

  // --- Catalog --------------------------------------------------------------

  /// `GET /reports/exports`, keyed by type. Counts are unfiltered, exactly as
  /// on the web, so this is fetched once rather than on every filter change.
  final Map<ReportType, int> _counts = {};
  bool _catalogLoading = true;
  Object? _catalogError;

  /// `GET /reports/exports/{type}/fields`, loaded lazily per type and kept.
  final Map<ReportType, ReportFieldSet> _fields = {};
  final Set<ReportType> _fieldsLoading = {};
  Object? _fieldsError;

  /// Selected column keys, per type. Seeded from the server's `default` flags
  /// the first time a type's catalog arrives.
  final Map<ReportType, Set<String>> _picked = {};

  // --- Filters --------------------------------------------------------------

  DateTime? _from;
  DateTime? _to;

  /// Ticket statuses: real status ids mixed with the two state shortcuts
  /// ([anyOpenStatusId] / [anyClosedStatusId]). Empty means every status.
  Set<int> _ticketStatuses = {};

  /// Tasks take one of three values, not a list.
  TaskStatusMode _taskStatus = TaskStatusMode.all;

  Set<int> _depts = {};
  Set<int> _topics = {};
  Set<int> _agents = {};

  /// `/meta` lists backing the filter sheets.
  List<MetaItem> _statusItems = const [];
  List<MetaItem> _deptItems = const [];
  List<MetaItem> _topicItems = const [];
  List<MetaItem> _agentItems = const [];

  bool _exporting = false;

  ReportFieldSet? get _current => _fields[_type];
  Set<String> get _selected => _picked[_type] ??= {};

  @override
  void initState() {
    super.initState();
    _loadMeta();
    _loadCatalog();
  }

  // --- Loading --------------------------------------------------------------

  Future<void> _loadMeta() async {
    final meta = ref.read(metaRepositoryProvider);
    try {
      final results = await Future.wait([
        meta.statuses(),
        meta.departments(),
        meta.topics(),
        meta.agents(),
      ]);
      if (!mounted) return;
      setState(() {
        _statusItems = results[0];
        _deptItems = results[1];
        _topicItems = results[2];
        _agentItems = results[3];
      });
    } on ApiException {
      // Filter lists unavailable; an unfiltered export still works.
    }
  }

  Future<void> _loadCatalog() async {
    setState(() {
      _catalogLoading = true;
      _catalogError = null;
    });
    try {
      final types = await ref.read(reportsRepositoryProvider).exportTypes();
      if (!mounted) return;
      setState(() {
        for (final t in types) {
          final key = ReportType.fromKey(t.key);
          if (key != null) _counts[key] = t.count;
        }
        _catalogLoading = false;
      });
      await _loadFields(_type);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _catalogError = e;
        _catalogLoading = false;
      });
    }
  }

  Future<void> _loadFields(ReportType type) async {
    if (_fields.containsKey(type) || _fieldsLoading.contains(type)) return;
    setState(() {
      _fieldsLoading.add(type);
      _fieldsError = null;
    });
    try {
      final set = await ref
          .read(reportsRepositoryProvider)
          .exportFields(type.key);
      if (!mounted) return;
      setState(() {
        _fields[type] = set;
        _picked[type] ??= {...set.defaultColumnKeys};
        _fieldsLoading.remove(type);
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _fieldsLoading.remove(type);
        _fieldsError = e;
      });
    }
  }

  void _selectType(ReportType t) {
    setState(() => _type = t);
    _loadFields(t);
  }

  // --- Export ---------------------------------------------------------------

  /// Filter values in the shape each `link` endpoint wants, skipping anything
  /// the type does not advertise a control for.
  List<String>? _statusPayload(ReportFieldSet fields) {
    if (!fields.filters.contains(ReportFilter.status)) return null;
    if (_type == ReportType.tasks) return taskStatusPayload(_taskStatus);
    final tokens = ticketStatusPayload(_ticketStatuses);
    return tokens.isEmpty ? null : tokens;
  }

  List<int>? _ids(ReportFieldSet fields, String filter, Set<int> selection) {
    if (!fields.filters.contains(filter) || selection.isEmpty) return null;
    return selection.toList()..sort();
  }

  Future<void> _runExport() async {
    final fields = _current;
    if (fields == null) return;
    if (_selected.isEmpty) {
      AppSnack.info(context, 'Pick at least one column');
      return;
    }
    setState(() => _exporting = true);
    try {
      final repo = ref.read(reportsRepositoryProvider);
      // Catalog order, not selection order — the export follows the order the
      // keys are sent in, and the catalog order is what the picker shows.
      final columns = [
        for (final c in fields.columns)
          if (_selected.contains(c.key)) c.key,
      ];
      final link = await repo.exportLink(
        _type.key,
        columns: columns,
        start: _from == null ? null : Fmt.apiDate(_from!),
        end: _to == null ? null : Fmt.apiDate(_to!),
        status: _statusPayload(fields),
        deptIds: _ids(fields, ReportFilter.department, _depts),
        topicIds: _ids(fields, ReportFilter.topic, _topics),
        staffIds: _ids(fields, ReportFilter.agent, _agents),
      );
      final bytes = await repo.download(link);

      // Read the server's own CSV back only to count its rows: on the web an
      // empty export is a file you can see is empty, here it would be a viewer
      // opening on nothing.
      final table = parseCsv(_decodeCsv(bytes));
      final rows = table.length > 1 ? table.length - 1 : 0;
      if (!mounted) return;
      if (rows == 0) {
        AppSnack.info(
          context,
          'No ${_type.label.toLowerCase()} matched these filters',
        );
        return;
      }

      // Written verbatim, BOM and quoting included, under the server's own
      // filename — byte for byte what the web would have downloaded.
      await openDownloadedFile(bytes: bytes, filename: link.filename);
      if (mounted) {
        AppSnack.success(
          context,
          'Exported $rows ${_type.label.toLowerCase()} as CSV',
        );
      }
    } on ApiException catch (e) {
      if (mounted) AppSnack.error(context, e.message);
    } on ExportOpenException {
      if (mounted) {
        AppSnack.info(context, 'Saved file but could not open it automatically');
      }
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  /// The download carries a UTF-8 BOM, which would otherwise become part of the
  /// first header cell.
  static String _decodeCsv(Uint8List bytes) {
    final text = utf8.decode(bytes, allowMalformed: true);
    if (text.isNotEmpty && text.codeUnitAt(0) == 0xFEFF) {
      return text.substring(1);
    }
    return text;
  }

  // --- Filter actions -------------------------------------------------------

  Future<void> _pickFrom() async {
    final d = await pickDate(
      context,
      initial: _from,
      first: DateTime(2000),
      last: _to ?? DateTime.now(),
    );
    if (d != null) setState(() => _from = d);
  }

  Future<void> _pickTo() async {
    final d = await pickDate(
      context,
      initial: _to,
      first: _from ?? DateTime(2000),
      last: DateTime.now(),
    );
    if (d != null) setState(() => _to = d);
  }

  Future<void> _pickMulti(
    String title,
    List<MetaItem> items,
    Set<int> current,
    ValueChanged<Set<int>> onApply,
  ) async {
    if (items.isEmpty) {
      AppSnack.info(context, 'No ${title.toLowerCase()} available');
      return;
    }
    final picked = await pickMultiMeta(
      context,
      title: title,
      items: items,
      selected: current,
    );
    if (picked != null && mounted) setState(() => onApply(picked));
  }

  bool get _hasFilters =>
      _from != null ||
      _to != null ||
      _ticketStatuses.isNotEmpty ||
      _taskStatus != TaskStatusMode.all ||
      _depts.isNotEmpty ||
      _topics.isNotEmpty ||
      _agents.isNotEmpty;

  void _resetFilters() => setState(() {
    _from = null;
    _to = null;
    _ticketStatuses = {};
    _taskStatus = TaskStatusMode.all;
    _depts = {};
    _topics = {};
    _agents = {};
  });

  // --- UI -------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    // Without the catalog there are no tabs, no counts and no column sets, so
    // a failure here — a revoked `reports.export` being the likely one — takes
    // the whole tab rather than hiding behind a banner.
    if (_catalogError != null) {
      return ErrorView(error: _catalogError!, onRetry: _loadCatalog);
    }

    final fields = _current;
    final loadingFields = _fieldsLoading.contains(_type);

    return Column(
      children: [
        _TypeTabs(
          value: _type,
          counts: _counts,
          loading: _catalogLoading,
          onChanged: _selectType,
        ),
        Divider(height: 1, color: scheme.outlineVariant.withValues(alpha: 0.6)),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
            children: [
              AppText.paraText(
                context,
                'Configure filters and pick which columns to include in the '
                '${_type.label} export.',
                color: scheme.onSurfaceVariant,
              ),
              const SizedBox(height: 12),
              ReportAccessBanner(
                loading: _catalogLoading,
                count: _counts[_type],
                label: _type.label.toLowerCase(),
              ),
              if (_fieldsError != null) ...[
                const SizedBox(height: 10),
                ReportNotice(
                  _fieldsError is ApiException
                      ? (_fieldsError as ApiException).message
                      : 'Could not load the columns for this report.',
                ),
                const SizedBox(height: 6),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: () => _loadFields(_type),
                    child: const Text('Retry'),
                  ),
                ),
              ],
              const SizedBox(height: 14),
              ReportSectionCard(
                title: 'Filters',
                trailing: _hasFilters
                    ? TextButton(
                        onPressed: _resetFilters,
                        style: TextButton.styleFrom(
                          visualDensity: VisualDensity.compact,
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                        ),
                        child: const Text('Clear'),
                      )
                    : null,
                children: _filterRows(fields),
              ),
              const SizedBox(height: 14),
              ReportColumnsCard(
                loading: loadingFields || fields == null,
                columns: fields?.columns ?? const [],
                selected: _selected,
                onToggle: (key, on) => setState(() {
                  if (on) {
                    _selected.add(key);
                  } else {
                    _selected.remove(key);
                  }
                }),
                onAll: () => setState(
                  () => _selected
                    ..clear()
                    ..addAll((fields?.columns ?? const []).map((c) => c.key)),
                ),
                onNone: () => setState(_selected.clear),
              ),
              const SizedBox(height: 20),
              ReportDownloadButton(
                busy: _exporting,
                enabled: fields != null && _selected.isNotEmpty,
                disabledHint: fields == null
                    ? 'Loading this report…'
                    : 'Pick at least one column to export.',
                onPressed: _runExport,
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// The filter rows this type supports, as the server advertises them — the
  /// screen renders `filters`, it does not decide it.
  List<Widget> _filterRows(ReportFieldSet? fields) {
    if (fields == null) {
      return const [
        Padding(
          padding: EdgeInsets.symmetric(horizontal: 8, vertical: 14),
          child: SkeletonBox(width: 180, height: 14),
        ),
        Padding(
          padding: EdgeInsets.symmetric(horizontal: 8, vertical: 14),
          child: SkeletonBox(width: 150, height: 14),
        ),
        Padding(
          padding: EdgeInsets.symmetric(horizontal: 8, vertical: 14),
          child: SkeletonBox(width: 170, height: 14),
        ),
      ];
    }
    final scheme = Theme.of(context).colorScheme;
    return [
      if (fields.filters.contains(ReportFilter.dateRange)) ...[
        ReportFilterRow(
          icon: Icons.event_outlined,
          label: 'Start date',
          value: _from == null ? 'Any' : Fmt.date(_from),
          onTap: _pickFrom,
          onClear: _from == null ? null : () => setState(() => _from = null),
        ),
        ReportFilterRow(
          icon: Icons.event_available_outlined,
          label: 'End date',
          value: _to == null ? 'Any' : Fmt.date(_to),
          onTap: _pickTo,
          onClear: _to == null ? null : () => setState(() => _to = null),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
          child: AppText.captionText(
            context,
            'Filters by created date, end date included. Leave blank for all '
            'records.',
            color: scheme.onSurfaceVariant,
          ),
        ),
      ],
      if (fields.filters.contains(ReportFilter.status))
        if (_type == ReportType.tasks)
          ReportChipsRow<TaskStatusMode>(
            icon: Icons.check_circle_outline,
            label: 'Status',
            options: [
              for (final m in TaskStatusMode.values) (m, m.label),
            ],
            value: _taskStatus,
            onChanged: (m) => setState(() => _taskStatus = m),
          )
        else
          // Tickets get the live page's full status list, both "any open" and
          // "any closed" shortcuts included, because the export endpoint ORs
          // status ids and `state:` tokens together.
          ReportFilterRow(
            icon: Icons.check_circle_outline,
            label: 'Status',
            value: selectionSummary(
              _ticketStatuses,
              ticketStatusOptions(_statusItems),
            ),
            onTap: () => _pickMulti(
              'Statuses',
              ticketStatusOptions(_statusItems),
              _ticketStatuses,
              (v) => _ticketStatuses = v,
            ),
            onClear: _ticketStatuses.isEmpty
                ? null
                : () => setState(() => _ticketStatuses = {}),
          ),
      if (fields.filters.contains(ReportFilter.department))
        ReportFilterRow(
          icon: Icons.apartment_rounded,
          label: 'Department',
          value: selectionSummary(_depts, _deptItems),
          onTap: () =>
              _pickMulti('Departments', _deptItems, _depts, (v) => _depts = v),
          onClear: _depts.isEmpty ? null : () => setState(() => _depts = {}),
        ),
      if (fields.filters.contains(ReportFilter.topic))
        ReportFilterRow(
          icon: Icons.topic_outlined,
          label: 'Help Topic',
          value: selectionSummary(_topics, _topicItems),
          onTap: () => _pickMulti(
            'Help Topics',
            _topicItems,
            _topics,
            (v) => _topics = v,
          ),
          onClear: _topics.isEmpty ? null : () => setState(() => _topics = {}),
        ),
      if (fields.filters.contains(ReportFilter.agent))
        ReportFilterRow(
          icon: Icons.person_outline,
          label: 'Agent',
          value: selectionSummary(_agents, _agentItems),
          onTap: () =>
              _pickMulti('Agents', _agentItems, _agents, (v) => _agents = v),
          onClear: _agents.isEmpty ? null : () => setState(() => _agents = {}),
        ),
    ];
  }
}

/// Record-type tab strip carrying each type's count, like the web's
/// "Tickets (84) · Tasks (247) · Users (3,554) · Organizations (5)".
class _TypeTabs extends StatelessWidget {
  const _TypeTabs({
    required this.value,
    required this.counts,
    required this.loading,
    required this.onChanged,
  });

  final ReportType value;
  final Map<ReportType, int> counts;
  final bool loading;
  final ValueChanged<ReportType> onChanged;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 52,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        children: [
          for (final t in ReportType.values) ...[
            _Tab(
              label: t.label,
              count: counts[t],
              loading: loading,
              selected: t == value,
              onTap: () => onChanged(t),
            ),
            const SizedBox(width: 8),
          ],
        ],
      ),
    );
  }
}

class _Tab extends StatelessWidget {
  const _Tab({
    required this.label,
    required this.count,
    required this.loading,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final int? count;
  final bool loading;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: selected
              ? AppTheme.brand.withValues(alpha: 0.12)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: selected ? AppTheme.brand : scheme.outlineVariant,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            AppText.custmText(
              context,
              label,
              fs: 13,
              fw: selected ? 2 : 0,
              color: selected ? AppTheme.brand : scheme.onSurface,
            ),
            const SizedBox(width: 6),
            if (loading && count == null)
              const SkeletonBox(width: 22, height: 11)
            else
              AppText.paraText(
                context,
                '(${Fmt.count(count ?? 0)})',
                color: selected ? AppTheme.brand : scheme.onSurfaceVariant,
              ),
          ],
        ),
      ),
    );
  }
}
