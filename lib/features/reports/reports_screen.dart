import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/reports.dart';
import '../../providers.dart';
import '../../widgets/states.dart';
import 'widgets/activity_chart_card.dart';
import 'widgets/report_range_selector.dart';
import 'widgets/report_summary_card.dart';

class ReportsScreen extends ConsumerStatefulWidget {
  const ReportsScreen({super.key});

  @override
  ConsumerState<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends ConsumerState<ReportsScreen> {
  int _days = 30;
  VolumeReport? _report;
  Object? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final report = await ref
          .read(reportsRepositoryProvider)
          .volume(days: _days);
      if (!mounted) return;
      setState(() {
        _report = report;
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

  void _selectDays(int days) {
    if (days == _days) return;
    setState(() => _days = days);
    _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Reports')),
      body: SafeArea(
        child: RefreshIndicator(onRefresh: _load, child: _buildBody(context)),
      ),
    );
  }

  Widget _buildBody(BuildContext context) {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(12, 14, 12, 24),
      children: [
        ReportRangeSelector(days: _days, onSelected: _selectDays),
        const SizedBox(height: 16),
        ..._content(context),
      ],
    );
  }

  List<Widget> _content(BuildContext context) {
    if (_loading) {
      return const [
        Padding(padding: EdgeInsets.only(top: 80), child: LoadingView()),
      ];
    }
    if (_error != null) {
      return [
        Padding(
          padding: const EdgeInsets.only(top: 80),
          child: ErrorView(error: _error!, onRetry: _load),
        ),
      ];
    }
    final report = _report;
    if (report == null) {
      return [ErrorView(error: 'No data', onRetry: _load)];
    }

    return [
      ReportSummaryCard(report: report),
      const SizedBox(height: 12),
      ActivityChartCard(report: report),
    ];
  }
}
