import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/routes.dart';
import '../../../models/reports.dart';
import '../../../providers.dart';
import '../../../widgets/states.dart';
import '../../dashboard/web/_tokens.dart';
import '../widgets/activity_chart_card.dart';
import '../widgets/report_summary_card.dart';

/// Web-only reports view. Mirrors the [OrgsListScreenWeb] header language
/// (back button + hero title) but the body is not a table — it's the same
/// summary / chart cards the dashboard uses, plus a range selector on the
/// right side of the header row that wraps to a second row on narrow
/// widths.
class ReportsScreenWeb extends ConsumerStatefulWidget {
  const ReportsScreenWeb({super.key});

  @override
  ConsumerState<ReportsScreenWeb> createState() => _ReportsScreenWebState();
}

class _ReportsScreenWebState extends ConsumerState<ReportsScreenWeb> {
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
      final report =
          await ref.read(reportsRepositoryProvider).volume(days: _days);
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
    final t = WebTokens.of(context);
    return ColoredBox(
      color: t.bgPrimary,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              WebTokens.s6,
              WebTokens.s5,
              WebTokens.s6,
              WebTokens.s4,
            ),
            child: LayoutBuilder(
              builder: (context, rowConstraints) {
                final titleRow = Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
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
                    Flexible(
                      child: Text(
                        'Reports',
                        style: t.hero,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const Spacer(),
                  ],
                );

                final rangeSelector = SizedBox(
                  width: 220,
                  child: _RangePicker(
                    days: _days,
                    onSelected: _selectDays,
                  ),
                );

                const narrowBreak = 640.0;
                if (rowConstraints.maxWidth < narrowBreak) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      titleRow,
                      const SizedBox(height: WebTokens.s3),
                      rangeSelector,
                    ],
                  );
                }

                return Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Expanded(child: titleRow),
                    const SizedBox(width: WebTokens.s3),
                    rangeSelector,
                  ],
                );
              },
            ),
          ),
          DecoratedBox(
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(color: t.borderSubtle, width: 1),
              ),
            ),
            child: const SizedBox(width: double.infinity, height: 0),
          ),
          Expanded(child: _buildBody()),
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (_loading && _report == null) {
      return const LoadingView();
    }
    if (_error != null && _report == null) {
      return ErrorView(error: _error!, onRetry: _load);
    }
    final report = _report;
    if (report == null) {
      return ErrorView(error: 'No data', onRetry: _load);
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(
          WebTokens.s6,
          WebTokens.s5,
          WebTokens.s6,
          WebTokens.s8,
        ),
        children: [
          ReportSummaryCard(report: report),
          const SizedBox(height: WebTokens.s4),
          ActivityChartCard(report: report),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Back button — same shape as the other CONTENT web screens.
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
// Range picker — themed dropdown that swaps between 7 / 30 / 90 days.
// ---------------------------------------------------------------------------

class _RangePicker extends StatelessWidget {
  const _RangePicker({required this.days, required this.onSelected});
  final int days;
  final ValueChanged<int> onSelected;

  static const _options = [7, 30, 90];

  @override
  Widget build(BuildContext context) {
    final t = WebTokens.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: WebTokens.s3),
      decoration: BoxDecoration(
        color: t.bgElevated,
        border: Border.all(color: t.borderSubtle, width: 1),
        borderRadius: BorderRadius.circular(4),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<int>(
          value: days,
          isExpanded: true,
          isDense: true,
          borderRadius: BorderRadius.circular(4),
          icon: Icon(
            Icons.keyboard_arrow_down_rounded,
            color: t.textSecondary,
          ),
          style: t.bodyBase.copyWith(
            color: t.textPrimary,
            fontWeight: FontWeight.w600,
          ),
          items: [
            for (final d in _options)
              DropdownMenuItem(value: d, child: Text('Last $d days')),
          ],
          onChanged: (v) {
            if (v != null) onSelected(v);
          },
        ),
      ),
    );
  }
}
