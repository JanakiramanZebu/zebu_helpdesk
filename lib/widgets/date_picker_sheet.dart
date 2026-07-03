import 'package:flutter/material.dart';

import '../core/theme/app_text.dart';
import '../core/theme/app_theme.dart';
import 'app_sheet.dart';

/// A clean, elegant replacement for Material's boxy [showDatePicker] dialog.
///
/// Presents a themed bottom sheet with a soft brand-gradient header (day of
/// week + big date), quick-jump chips (Today / Tomorrow / Next week), and a
/// swipeable month grid. Selection is a filled brand circle; "today" gets a
/// subtle ring. Returns the chosen date (date-only, time stripped) or `null`
/// if the user dismisses the sheet.
///
/// Drop-in for the old call:
/// ```dart
/// final date = await pickDate(
///   context,
///   initial: _due,
///   first: firstDate,
///   last: lastDate,
/// );
/// ```
Future<DateTime?> pickDate(
  BuildContext context, {
  DateTime? initial,
  required DateTime first,
  required DateTime last,
}) {
  final firstDay = DateUtils.dateOnly(first);
  final lastDay = DateUtils.dateOnly(last);
  final seed = DateUtils.dateOnly(initial ?? DateTime.now());
  final clamped = seed.isBefore(firstDay)
      ? firstDay
      : (seed.isAfter(lastDay) ? lastDay : seed);

  return showAppSheet<DateTime>(
    context: context,
    builder: (_) => _DatePickerSheet(
      initial: clamped,
      first: firstDay,
      last: lastDay,
    ),
  );
}

class _DatePickerSheet extends StatefulWidget {
  const _DatePickerSheet({
    required this.initial,
    required this.first,
    required this.last,
  });

  final DateTime initial;
  final DateTime first;
  final DateTime last;

  @override
  State<_DatePickerSheet> createState() => _DatePickerSheetState();
}

class _DatePickerSheetState extends State<_DatePickerSheet> {
  late DateTime _selected = widget.initial;
  late final PageController _pages;
  late final int _monthCount;
  late int _pageIndex;

  @override
  void initState() {
    super.initState();
    _monthCount =
        DateUtils.monthDelta(_firstMonth, _lastMonth) + 1;
    _pageIndex = DateUtils.monthDelta(_firstMonth, _selected);
    _pages = PageController(initialPage: _pageIndex);
  }

  DateTime get _firstMonth => DateTime(widget.first.year, widget.first.month);
  DateTime get _lastMonth => DateTime(widget.last.year, widget.last.month);

  DateTime _monthAt(int index) => DateUtils.addMonthsToMonthDate(
    _firstMonth,
    index,
  );

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  bool _inRange(DateTime day) =>
      !day.isBefore(widget.first) && !day.isAfter(widget.last);

  void _select(DateTime day) {
    if (!_inRange(day)) return;
    setState(() => _selected = day);
  }

  void _jumpTo(DateTime day) {
    if (!_inRange(day)) return;
    final target = DateUtils.monthDelta(_firstMonth, day);
    setState(() {
      _selected = day;
      _pageIndex = target;
    });
    _pages.animateToPage(
      target,
      duration: const Duration(milliseconds: 320),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    return AppSheet(
      title: 'Select date',
      scrollable: false,
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Header(date: _selected),
          const SizedBox(height: 10),
          _QuickChips(
            selected: _selected,
            inRange: _inRange,
            onPick: _jumpTo,
          ),
          const SizedBox(height: 10),
          _MonthNav(
            month: _monthAt(_pageIndex),
            canPrev: _pageIndex > 0,
            canNext: _pageIndex < _monthCount - 1,
            onPrev: () => _pages.previousPage(
              duration: const Duration(milliseconds: 260),
              curve: Curves.easeOut,
            ),
            onNext: () => _pages.nextPage(
              duration: const Duration(milliseconds: 260),
              curve: Curves.easeOut,
            ),
          ),
          const SizedBox(height: 4),
          const _WeekdayRow(),
          const SizedBox(height: 2),
          SizedBox(
            height: 232,
            child: PageView.builder(
              controller: _pages,
              itemCount: _monthCount,
              onPageChanged: (i) => setState(() => _pageIndex = i),
              itemBuilder: (_, i) => _MonthGrid(
                month: _monthAt(i),
                selected: _selected,
                inRange: _inRange,
                onTap: _select,
              ),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: AppText.subText(
                    context,
                    'Cancel',
                    fw: 1,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton(
                  onPressed: () => Navigator.pop(context, _selected),
                  child: const Text('Confirm'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Compact header showing the currently selected day of week and full date.
class _Header extends StatelessWidget {
  const _Header({required this.date});
  final DateTime date;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: AppTheme.brand.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(Icons.event_rounded, color: AppTheme.brand, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: AppText.subText(
              context,
              '${_weekdayShort(date.weekday)}, ${date.day} '
              '${_monthShort(date.month)} ${date.year}',
              color: AppTheme.brand,
              fw: 1,
            ),
          ),
        ],
      ),
    );
  }
}

/// Today / Tomorrow / Next week quick-jump chips.
class _QuickChips extends StatelessWidget {
  const _QuickChips({
    required this.selected,
    required this.inRange,
    required this.onPick,
  });

  final DateTime selected;
  final bool Function(DateTime) inRange;
  final ValueChanged<DateTime> onPick;

  @override
  Widget build(BuildContext context) {
    final today = DateUtils.dateOnly(DateTime.now());
    final chips = <({String label, DateTime day})>[
      (label: 'Today', day: today),
      (label: 'Tomorrow', day: today.add(const Duration(days: 1))),
      (label: 'Next week', day: today.add(const Duration(days: 7))),
    ];
    return Row(
      children: [
        for (final c in chips) ...[
          Expanded(
            child: _Chip(
              label: c.label,
              selected: DateUtils.isSameDay(selected, c.day),
              enabled: inRange(c.day),
              onTap: () => onPick(c.day),
            ),
          ),
          if (c != chips.last) const SizedBox(width: 8),
        ],
      ],
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({
    required this.label,
    required this.selected,
    required this.enabled,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final bg = selected
        ? AppTheme.brand.withValues(alpha: 0.12)
        : scheme.onSurface.withValues(alpha: 0.04);
    final fg = !enabled
        ? scheme.onSurfaceVariant.withValues(alpha: 0.4)
        : (selected ? AppTheme.brand : scheme.onSurface);
    return Material(
      color: bg,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: enabled ? onTap : null,
        child: Container(
          height: 34,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: selected
                  ? AppTheme.brand.withValues(alpha: 0.4)
                  : Colors.transparent,
            ),
          ),
          child: AppText.paraText(
            context,
            label,
            fw: selected ? 1 : 0,
            color: fg,
          ),
        ),
      ),
    );
  }
}

/// Month title with left/right chevrons.
class _MonthNav extends StatelessWidget {
  const _MonthNav({
    required this.month,
    required this.canPrev,
    required this.canNext,
    required this.onPrev,
    required this.onNext,
  });

  final DateTime month;
  final bool canPrev;
  final bool canNext;
  final VoidCallback onPrev;
  final VoidCallback onNext;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        AppText.titleText(
          context,
          '${_monthLong(month.month)} ${month.year}',
          fw: 2,
        ),
        const Spacer(),
        _NavButton(icon: Icons.chevron_left_rounded, onTap: canPrev ? onPrev : null),
        const SizedBox(width: 4),
        _NavButton(icon: Icons.chevron_right_rounded, onTap: canNext ? onNext : null),
      ],
    );
  }
}

class _NavButton extends StatelessWidget {
  const _NavButton({required this.icon, required this.onTap});
  final IconData icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final enabled = onTap != null;
    return Material(
      color: scheme.onSurface.withValues(alpha: 0.05),
      shape: const CircleBorder(),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(6),
          child: Icon(
            icon,
            size: 22,
            color: enabled
                ? scheme.onSurface
                : scheme.onSurfaceVariant.withValues(alpha: 0.35),
          ),
        ),
      ),
    );
  }
}

/// Su–Sa weekday header (Sunday-first, matching the app's default calendar).
class _WeekdayRow extends StatelessWidget {
  const _WeekdayRow();

  @override
  Widget build(BuildContext context) {
    const labels = ['S', 'M', 'T', 'W', 'T', 'F', 'S'];
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    return Row(
      children: [
        for (final l in labels)
          Expanded(
            child: Center(
              child: AppText.paraText(context, l, color: muted, fw: 1),
            ),
          ),
      ],
    );
  }
}

/// One month's day grid.
class _MonthGrid extends StatelessWidget {
  const _MonthGrid({
    required this.month,
    required this.selected,
    required this.inRange,
    required this.onTap,
  });

  final DateTime month;
  final DateTime selected;
  final bool Function(DateTime) inRange;
  final ValueChanged<DateTime> onTap;

  @override
  Widget build(BuildContext context) {
    final daysInMonth = DateUtils.getDaysInMonth(month.year, month.month);
    // Leading blanks so the 1st lands under its weekday (Sunday-first).
    final leading = DateTime(month.year, month.month, 1).weekday % 7;
    final today = DateUtils.dateOnly(DateTime.now());

    final cells = <Widget>[
      for (var i = 0; i < leading; i++) const SizedBox.shrink(),
      for (var d = 1; d <= daysInMonth; d++)
        _DayCell(
          day: DateTime(month.year, month.month, d),
          selected: selected,
          today: today,
          enabled: inRange(DateTime(month.year, month.month, d)),
          onTap: onTap,
        ),
    ];

    return GridView.count(
      physics: const NeverScrollableScrollPhysics(),
      crossAxisCount: 7,
      padding: EdgeInsets.zero,
      children: cells,
    );
  }
}

class _DayCell extends StatelessWidget {
  const _DayCell({
    required this.day,
    required this.selected,
    required this.today,
    required this.enabled,
    required this.onTap,
  });

  final DateTime day;
  final DateTime selected;
  final DateTime today;
  final bool enabled;
  final ValueChanged<DateTime> onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isSelected = DateUtils.isSameDay(day, selected);
    final isToday = DateUtils.isSameDay(day, today);

    final Color fg;
    if (!enabled) {
      fg = scheme.onSurfaceVariant.withValues(alpha: 0.3);
    } else if (isSelected) {
      fg = Colors.white;
    } else if (isToday) {
      fg = AppTheme.brand;
    } else {
      fg = scheme.onSurface;
    }

    return Padding(
      padding: const EdgeInsets.all(3),
      child: Material(
        color: isSelected ? AppTheme.brand : Colors.transparent,
        shape: const CircleBorder(),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: enabled ? () => onTap(day) : null,
          child: Container(
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: isToday && !isSelected
                  ? Border.all(color: AppTheme.brand, width: 1.4)
                  : null,
            ),
            child: AppText.subText(
              context,
              '${day.day}',
              color: fg,
              fw: isSelected || isToday ? 1 : 3,
            ),
          ),
        ),
      ),
    );
  }
}

String _weekdayShort(int weekday) => const [
  'Mon',
  'Tue',
  'Wed',
  'Thu',
  'Fri',
  'Sat',
  'Sun',
][weekday - 1];

String _monthShort(int month) => const [
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
][month - 1];

String _monthLong(int month) => const [
  'January',
  'February',
  'March',
  'April',
  'May',
  'June',
  'July',
  'August',
  'September',
  'October',
  'November',
  'December',
][month - 1];
