import 'dart:async';

import 'package:flutter/material.dart';

import '../../res/zebu_text_styles.dart';
import '../../res/zebu_theme.dart';
import 'anchored_popover.dart';
import 'zebu_text_action.dart';

/// The date picker for a property row: a popover anchored under the tapped
/// value, on the same card as [showZebuPropertyMenu] — radius 10, hairline,
/// soft shadow, right-aligned to the trigger.
///
/// It replaces `showDatePicker` **and** the `showTimePicker` that every call
/// site fired straight after it. Two centered Material modals, stacked on top
/// of a dialog that is itself a modal, to set one optional field — while every
/// other row in the same grid edits in a small popover under its own value.
/// Date and time live on one surface here, so the row behaves like its
/// neighbours and commits once.
///
/// Keeping Flutter's picker and theming it was the alternative. It fixes the
/// palette but not the shape: the hero header, the centered modal and the
/// second modal for time are structural.

/// Outcome of [showZebuDatePicker].
///
/// A `null` future means dismissed — barrier tap or Esc — and must leave the
/// field exactly as it was. [cleared] is an explicit "no date", which is a
/// different answer from "never mind" and the reason this is not just a
/// `Future<DateTime?>`.
class ZebuDateResult {
  const ZebuDateResult.value(DateTime this.date) : cleared = false;
  const ZebuDateResult.cleared() : date = null, cleared = true;

  final DateTime? date;
  final bool cleared;
}

Future<ZebuDateResult?> showZebuDatePicker(
  BuildContext anchorContext, {
  required DateTime firstDate,
  required DateTime lastDate,
  DateTime? initial,

  /// Adds the time row under the grid. Off gives a date-only picker that
  /// commits the moment a day is tapped, the way a menu row does.
  bool withTime = true,

  /// Omitted when the field is already empty — there is nothing to clear, and
  /// an inert link is worse than no link.
  String? clearLabel,
  double width = 272,
}) {
  final overlay = zebuOverlayBox(anchorContext);
  if (overlay == null) return Future<ZebuDateResult?>.value();
  final anchor = zebuAnchorRect(anchorContext, overlay);
  if (anchor == null) return Future<ZebuDateResult?>.value();

  return Navigator.of(anchorContext, rootNavigator: true).push<ZebuDateResult>(
    ZebuAnchoredRoute<ZebuDateResult>(
      anchor: anchor,
      overlaySize: overlay.size,
      width: width,
      // Six week rows is the worst case; the flip only needs to be about right.
      estimatedHeight: withTime ? 392 : 330,
      builder: (_) => _DatePickerPanel(
        firstDate: firstDate,
        lastDate: lastDate,
        initial: initial,
        withTime: withTime,
        clearLabel: clearLabel,
      ),
    ),
  );
}

const _kMonths = [
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
];

/// Sunday-first, matching the column order the mock's calendar uses.
const _kWeekdays = ['S', 'M', 'T', 'W', 'T', 'F', 'S'];

DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

/// Comparable month index, so month bounds are one integer compare instead of
/// end-of-month arithmetic.
int _ym(DateTime d) => d.year * 12 + d.month;

class _DatePickerPanel extends StatefulWidget {
  const _DatePickerPanel({
    required this.firstDate,
    required this.lastDate,
    required this.initial,
    required this.withTime,
    required this.clearLabel,
  });

  final DateTime firstDate;
  final DateTime lastDate;
  final DateTime? initial;
  final bool withTime;
  final String? clearLabel;

  @override
  State<_DatePickerPanel> createState() => _DatePickerPanelState();
}

class _DatePickerPanelState extends State<_DatePickerPanel> {
  late DateTime _month;
  DateTime? _day;

  /// Minutes since midnight, 0–1439. The whole time control is this one
  /// number: every button moves it and wraps modulo the day, so there is no
  /// state from which an invalid time can be shown or returned. The text
  /// boxes this replaced clamped on blur, which let `99` sit in the minute
  /// field looking accepted until you clicked away.
  late int _mins;

  bool _yearOpen = false;

  @override
  void initState() {
    super.initState();
    final seed = widget.initial ?? DateTime.now();
    _month = DateTime(seed.year, seed.month);
    _day = widget.initial == null ? null : _dateOnly(seed);
    _mins = seed.hour * 60 + seed.minute;
  }

  bool get _canPrev => _ym(_month) > _ym(widget.firstDate);
  bool get _canNext => _ym(_month) < _ym(widget.lastDate);

  bool _enabled(DateTime d) =>
      !d.isBefore(_dateOnly(widget.firstDate)) &&
      !d.isAfter(_dateOnly(widget.lastDate));

  int get _hour24 => _mins ~/ 60;
  int get _minute => _mins % 60;
  bool get _pm => _hour24 >= 12;

  /// 12-hour face: midnight and noon both read as 12, not 0.
  int get _hour12 => _hour24 % 12 == 0 ? 12 : _hour24 % 12;

  /// Every time button routes through here. `%` in Dart keeps the sign of the
  /// divisor, so stepping below midnight wraps to 23:59 rather than going
  /// negative — no clamping and no special cases at the ends of the day.
  void _bump(int deltaMinutes) =>
      setState(() => _mins = (_mins + deltaMinutes) % 1440);

  void _commit(DateTime day) {
    final out = widget.withTime
        ? DateTime(day.year, day.month, day.day, _hour24, _minute)
        : DateTime(day.year, day.month, day.day);
    Navigator.of(context).pop(ZebuDateResult.value(out));
  }

  void _onDayTap(DateTime day) {
    // Date-only commits straight away, like a menu row. With a time row there
    // is a second thing to set, so the tap only selects and Apply commits.
    if (!widget.withTime) {
      _commit(day);
      return;
    }
    setState(() => _day = day);
  }

  @override
  Widget build(BuildContext context) {
    final t = ZebuTheme.of(context);
    return Material(
      color: Colors.transparent,
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: zebuPopoverPanel(t),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: zebuPopoverEdge(t)),
          boxShadow: kZebuPopoverShadow,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Only the grid and time scroll, so Apply and Clear stay reachable
            // when the route caps the panel on a short window. The `Flexible`
            // is alone in this Column — nothing else here is flex, so it takes
            // the remainder rather than splitting it.
            Flexible(
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _header(t),
                    const SizedBox(height: 8),
                    if (_yearOpen) _years(t) else ...[_weekdays(t), _grid()],
                    if (widget.withTime) ...[
                      const SizedBox(height: 8),
                      Divider(
                        height: 1,
                        thickness: 1,
                        color: zebuPopoverEdge(t),
                      ),
                      const SizedBox(height: 8),
                      _timeRow(t),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: 6),
            Divider(height: 1, thickness: 1, color: zebuPopoverEdge(t)),
            const SizedBox(height: 6),
            _footer(t),
          ],
        ),
      ),
    );
  }

  Widget _header(ZebuTheme t) => Row(
    children: [
      // The month label is the year control. Three years of range is 36 taps
      // on the chevrons otherwise.
      _HeaderButton(
        label: '${_kMonths[_month.month - 1]} ${_month.year}',
        open: _yearOpen,
        onTap: () => setState(() => _yearOpen = !_yearOpen),
      ),
      const Spacer(),
      _NavIcon(
        icon: Icons.chevron_left_rounded,
        enabled: _canPrev && !_yearOpen,
        onTap: () =>
            setState(() => _month = DateTime(_month.year, _month.month - 1)),
      ),
      _NavIcon(
        icon: Icons.chevron_right_rounded,
        enabled: _canNext && !_yearOpen,
        onTap: () =>
            setState(() => _month = DateTime(_month.year, _month.month + 1)),
      ),
    ],
  );

  Widget _weekdays(ZebuTheme t) => Row(
    children: [
      for (final d in _kWeekdays)
        Expanded(
          child: SizedBox(
            height: 24,
            child: Center(
              child: Text(
                d,
                style: ZebuTextStyles.small(
                  context,
                  fontWeight: ZebuFonts.semiBold,
                  color: zebuPopoverInkMuted(t),
                ).copyWith(fontSize: 11),
              ),
            ),
          ),
        ),
    ],
  );

  Widget _grid() {
    final daysInMonth = DateTime(_month.year, _month.month + 1, 0).day;
    // `DateTime.weekday` is 1=Mon..7=Sun; `% 7` maps Sunday to column 0.
    final lead = DateTime(_month.year, _month.month, 1).weekday % 7;
    final today = _dateOnly(DateTime.now());

    final cells = <Widget>[
      for (var i = 0; i < lead; i++)
        const Expanded(child: SizedBox(height: 32)),
    ];
    for (var d = 1; d <= daysInMonth; d++) {
      final date = DateTime(_month.year, _month.month, d);
      cells.add(
        Expanded(
          child: _DayCell(
            day: d,
            selected: _day != null && _day == date,
            today: date == today,
            enabled: _enabled(date),
            onTap: () => _onDayTap(date),
          ),
        ),
      );
    }
    while (cells.length % 7 != 0) {
      cells.add(const Expanded(child: SizedBox(height: 32)));
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < cells.length; i += 7)
          Row(children: cells.sublist(i, i + 7)),
      ],
    );
  }

  Widget _years(ZebuTheme t) {
    final years = [
      for (var y = widget.firstDate.year; y <= widget.lastDate.year; y++) y,
    ];
    return ConstrainedBox(
      // Matches the grid's tallest case, so opening the year list does not
      // resize the popover under the pointer.
      constraints: const BoxConstraints(maxHeight: 216),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final y in years)
              _YearRow(
                year: y,
                selected: y == _month.year,
                onTap: () => setState(() {
                  _month = DateTime(y, _month.month);
                  _yearOpen = false;
                }),
              ),
          ],
        ),
      ),
    );
  }

  Widget _timeRow(ZebuTheme t) => Row(
    children: [
      Text(
        'Time',
        style: ZebuTextStyles.small(
          context,
          color: zebuPopoverInkMuted(t),
        ).copyWith(fontSize: 12),
      ),
      const Spacer(),
      _Stepper(
        label: '$_hour12',
        onUp: () => _bump(60),
        onDown: () => _bump(-60),
      ),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 3),
        child: Text(
          ':',
          style: ZebuTextStyles.small(
            context,
            fontWeight: ZebuFonts.semiBold,
            color: zebuPopoverInk(t),
          ).copyWith(fontSize: 13),
        ),
      ),
      // Minutes carry into the hour rather than wrapping in place: 59 ▲ is
      // the next hour, not the same hour's :00. Stepping the single
      // minutes-of-day counter gets that for free.
      _Stepper(
        label: _minute.toString().padLeft(2, '0'),
        onUp: () => _bump(1),
        onDown: () => _bump(-1),
      ),
      const SizedBox(width: 6),
      // Twelve hours either way — the toggle is the same counter, so AM/PM
      // can never disagree with the hour shown beside it.
      _AmPmToggle(pm: _pm, onChanged: (_) => _bump(720)),
    ],
  );

  // `Expanded` on the left and no `Spacer`. Both default to `flex: 1`, so a
  // `Flexible` clear link beside a `Spacer` would split the free space and
  // leave the link squeezed into half a row it does not need. Expanded takes
  // the whole remainder, which both pins Apply to the right edge and gives a
  // long clear label somewhere to ellipsize into.
  Widget _footer(ZebuTheme t) => Row(
    children: [
      Expanded(
        child: widget.clearLabel == null
            ? const SizedBox.shrink()
            : Align(
                alignment: Alignment.centerLeft,
                child: ZebuTextAction(
                  label: widget.clearLabel!,
                  // Clearing is the one destructive thing on this panel, and
                  // the tone is what says so — red label at rest, tinted pill
                  // only under the pointer, never a filled button.
                  tone: ZebuActionTone.danger,
                  onTap: () =>
                      Navigator.of(context).pop(const ZebuDateResult.cleared()),
                ),
              ),
      ),
      ZebuTextAction(
        label: 'Apply',
        // Nothing to apply until a day is picked. Greying it says so without
        // an error, since the popover can simply be dismissed instead.
        onTap: _day == null ? null : () => _commit(_day!),
      ),
    ],
  );
}

/// Month + year, and the control that opens the year list.
class _HeaderButton extends StatefulWidget {
  const _HeaderButton({
    required this.label,
    required this.open,
    required this.onTap,
  });

  final String label;
  final bool open;
  final VoidCallback onTap;

  @override
  State<_HeaderButton> createState() => _HeaderButtonState();
}

class _HeaderButtonState extends State<_HeaderButton> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final t = ZebuTheme.of(context);
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 80),
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
          decoration: BoxDecoration(
            // Idle is the hover tone at zero alpha, never `Colors.transparent`
            // — that is transparent *black*, and a fill lerping from it washes
            // through grey on the way in.
            color: _hover
                ? zebuPopoverHoverBg(t)
                : zebuPopoverHoverBg(t).withValues(alpha: 0),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                widget.label,
                style: ZebuTextStyles.small(
                  context,
                  fontWeight: ZebuFonts.semiBold,
                  color: zebuPopoverInk(t),
                ).copyWith(fontSize: 13),
              ),
              const SizedBox(width: 2),
              Icon(
                widget.open
                    ? Icons.arrow_drop_up_rounded
                    : Icons.arrow_drop_down_rounded,
                size: 18,
                color: zebuPopoverInkMuted(t),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NavIcon extends StatefulWidget {
  const _NavIcon({
    required this.icon,
    required this.enabled,
    required this.onTap,
  });

  final IconData icon;
  final bool enabled;
  final VoidCallback onTap;

  @override
  State<_NavIcon> createState() => _NavIconState();
}

class _NavIconState extends State<_NavIcon> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final t = ZebuTheme.of(context);
    final ink = widget.enabled
        ? zebuPopoverInk(t)
        : zebuPopoverInkMuted(t).withValues(alpha: 0.4);
    return MouseRegion(
      cursor: widget.enabled
          ? SystemMouseCursors.click
          : SystemMouseCursors.basic,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.enabled ? widget.onTap : null,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 80),
          width: 26,
          height: 26,
          decoration: BoxDecoration(
            color: _hover && widget.enabled
                ? zebuPopoverHoverBg(t)
                : zebuPopoverHoverBg(t).withValues(alpha: 0),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Icon(widget.icon, size: 18, color: ink),
        ),
      ),
    );
  }
}

class _DayCell extends StatefulWidget {
  const _DayCell({
    required this.day,
    required this.selected,
    required this.today,
    required this.enabled,
    required this.onTap,
  });

  final int day;
  final bool selected;
  final bool today;
  final bool enabled;
  final VoidCallback onTap;

  @override
  State<_DayCell> createState() => _DayCellState();
}

class _DayCellState extends State<_DayCell> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final t = ZebuTheme.of(context);

    final Color bg;
    final Color ink;
    if (widget.selected) {
      bg = t.accent;
      ink = Colors.white;
    } else if (!widget.enabled) {
      bg = zebuPopoverHoverBg(t).withValues(alpha: 0);
      ink = zebuPopoverInkMuted(t).withValues(alpha: 0.38);
    } else {
      bg = _hover
          ? zebuPopoverHoverBg(t)
          : zebuPopoverHoverBg(t).withValues(alpha: 0);
      // Today keeps the accent ink even unselected, so the ring is not the
      // only thing marking it.
      ink = widget.today ? t.accent : zebuPopoverInk(t);
    }

    return MouseRegion(
      cursor: widget.enabled
          ? SystemMouseCursors.click
          : SystemMouseCursors.basic,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.enabled ? widget.onTap : null,
        child: SizedBox(
          height: 32,
          child: Center(
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 80),
              width: 28,
              height: 28,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: bg,
                shape: BoxShape.circle,
                border: widget.today && !widget.selected
                    ? Border.all(color: t.accent.withValues(alpha: 0.5))
                    : null,
              ),
              child: Text(
                '${widget.day}',
                style: ZebuTextStyles.small(
                  context,
                  fontWeight: widget.selected || widget.today
                      ? ZebuFonts.semiBold
                      : ZebuFonts.regular,
                  color: ink,
                ).copyWith(fontSize: 12.5, height: 1),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _YearRow extends StatefulWidget {
  const _YearRow({
    required this.year,
    required this.selected,
    required this.onTap,
  });

  final int year;
  final bool selected;
  final VoidCallback onTap;

  @override
  State<_YearRow> createState() => _YearRowState();
}

class _YearRowState extends State<_YearRow> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final t = ZebuTheme.of(context);
    final bg = widget.selected
        ? zebuPopoverSelectedBg(t)
        : (_hover
              ? zebuPopoverHoverBg(t)
              : zebuPopoverHoverBg(t).withValues(alpha: 0));

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 80),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(7),
          ),
          child: Text(
            '${widget.year}',
            style: ZebuTextStyles.small(
              context,
              fontWeight: widget.selected
                  ? ZebuFonts.semiBold
                  : ZebuFonts.regular,
              color: widget.selected ? t.accent : zebuPopoverInk(t),
            ).copyWith(fontSize: 13),
          ),
        ),
      ),
    );
  }
}

/// One number with a ▲ above and a ▼ below. Read-only: the value moves only
/// through the arrows, which is what makes an out-of-range time unreachable
/// rather than merely corrected afterwards.
class _Stepper extends StatelessWidget {
  const _Stepper({
    required this.label,
    required this.onUp,
    required this.onDown,
  });

  final String label;
  final VoidCallback onUp;
  final VoidCallback onDown;

  @override
  Widget build(BuildContext context) {
    final t = ZebuTheme.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _Arrow(icon: Icons.keyboard_arrow_up_rounded, onTap: onUp),
        Container(
          width: 38,
          padding: const EdgeInsets.symmetric(vertical: 8),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: zebuPopoverHoverBg(t),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Text(
            label,
            style: ZebuTextStyles.small(
              context,
              fontWeight: ZebuFonts.semiBold,
              color: zebuPopoverInk(t),
            ).copyWith(fontSize: 13, height: 1),
          ),
        ),
        _Arrow(icon: Icons.keyboard_arrow_down_rounded, onTap: onDown),
      ],
    );
  }
}

/// A stepper arrow that keeps firing while held. One click per minute makes
/// :00 to :45 forty-five clicks, which is the cost the arrows would otherwise
/// carry over a typed field.
class _Arrow extends StatefulWidget {
  const _Arrow({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback onTap;

  @override
  State<_Arrow> createState() => _ArrowState();
}

class _ArrowState extends State<_Arrow> {
  bool _hover = false;
  Timer? _repeat;

  @override
  void dispose() {
    _repeat?.cancel();
    super.dispose();
  }

  void _start() {
    widget.onTap();
    // A pause before the run, so a normal click moves exactly one step.
    _repeat = Timer(const Duration(milliseconds: 350), () {
      _repeat = Timer.periodic(
        const Duration(milliseconds: 60),
        (_) => widget.onTap(),
      );
    });
  }

  void _stop() {
    _repeat?.cancel();
    _repeat = null;
  }

  @override
  Widget build(BuildContext context) {
    final t = ZebuTheme.of(context);
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (_) => _start(),
        onTapUp: (_) => _stop(),
        onTapCancel: _stop,
        child: SizedBox(
          width: 34,
          height: 16,
          child: Icon(
            widget.icon,
            size: 15,
            color: _hover ? t.accent : zebuPopoverInkMuted(t),
          ),
        ),
      ),
    );
  }
}

class _AmPmToggle extends StatelessWidget {
  const _AmPmToggle({required this.pm, required this.onChanged});

  final bool pm;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final t = ZebuTheme.of(context);
    return Container(
      height: 26,
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        color: zebuPopoverHoverBg(t),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _half(context, 'AM', !pm, () => onChanged(false)),
          _half(context, 'PM', pm, () => onChanged(true)),
        ],
      ),
    );
  }

  Widget _half(BuildContext context, String label, bool on, VoidCallback tap) {
    final t = ZebuTheme.of(context);
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: tap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 80),
          padding: const EdgeInsets.symmetric(horizontal: 7),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: on
                ? zebuPopoverPanel(t)
                : zebuPopoverPanel(t).withValues(alpha: 0),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Text(
            label,
            style: ZebuTextStyles.small(
              context,
              fontWeight: on ? ZebuFonts.semiBold : ZebuFonts.regular,
              color: on ? t.accent : zebuPopoverInkMuted(t),
            ).copyWith(fontSize: 11),
          ),
        ),
      ),
    );
  }
}

// The footer's Apply and Clear now come from `ZebuTextAction` in
// `zebu_text_action.dart` — they were the private `_FooterLink` here until the
// pair was wanted on other surfaces.
