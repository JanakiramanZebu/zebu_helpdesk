import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zebu_helpdesk/widgets/web/zebu_date_picker.dart';

/// A fixed range so the grid under test never depends on the day the suite
/// runs. June 2026 starts on a Monday, which puts a leading blank in column 0
/// and exercises the Sunday-first offset.
final _first = DateTime(2026, 6, 1);
final _last = DateTime(2026, 8, 31);

/// Stepper arrows, in row order: index 0 is the hour, 1 the minute.
final _up = find.byIcon(Icons.keyboard_arrow_up_rounded);
final _down = find.byIcon(Icons.keyboard_arrow_down_rounded);

/// Opens the picker from a centered button on a surface tall enough for the
/// panel to open downward at full height — the default 800×600 is shorter than
/// the picker, so it would otherwise test the capped-and-scrolling path every
/// time.
Future<void> _host(
  WidgetTester tester,
  Future<void> Function(BuildContext) onPressed,
) async {
  tester.view.physicalSize = const Size(1000, 1000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        // The `Builder` has to sit *inside* `Center`, so the context it hands
        // over belongs to the button. Put it above and the anchor rect is the
        // whole body, which parks the popover off the bottom of the screen.
        body: Center(
          child: Builder(
            builder: (context) => TextButton(
              onPressed: () => onPressed(context),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('picks a day and applies it with the time on the row', (
    tester,
  ) async {
    ZebuDateResult? out;
    await _host(
      tester,
      (c) async => out = await showZebuDatePicker(
        c,
        initial: DateTime(2026, 6, 10, 9, 30),
        firstDate: _first,
        lastDate: _last,
      ),
    );

    expect(find.text('June 2026'), findsOneWidget);

    await tester.tap(find.text('17'));
    await tester.pumpAndSettle();
    // Still open — with a time row, a day tap selects and Apply commits.
    expect(out, isNull);

    await tester.tap(find.text('Apply'));
    await tester.pumpAndSettle();

    expect(out, isNotNull);
    expect(out!.cleared, isFalse);
    expect(out!.date, DateTime(2026, 6, 17, 9, 30));
  });

  testWidgets('date-only commits on the day tap, with no time', (tester) async {
    ZebuDateResult? out;
    await _host(
      tester,
      (c) async => out = await showZebuDatePicker(
        c,
        initial: DateTime(2026, 6, 10, 14, 45),
        firstDate: _first,
        lastDate: _last,
        withTime: false,
      ),
    );

    expect(find.text('Time'), findsNothing);

    await tester.tap(find.text('3'));
    await tester.pumpAndSettle();

    expect(out, isNotNull);
    // Midnight, not the initial 14:45 — a date-only picker returns a date.
    expect(out!.date, DateTime(2026, 6, 3));
  });

  testWidgets('Clear is an answer of its own', (tester) async {
    ZebuDateResult? out;
    var returned = false;
    await _host(tester, (c) async {
      out = await showZebuDatePicker(
        c,
        initial: DateTime(2026, 6, 10),
        firstDate: _first,
        lastDate: _last,
        clearLabel: 'Clear',
      );
      returned = true;
    });

    await tester.tap(find.text('Clear'));
    await tester.pumpAndSettle();

    expect(returned, isTrue);
    expect(out!.cleared, isTrue);
    expect(out!.date, isNull);
    // The distinction the result type exists for: cleared is not dismissed.
    expect(out, isNotNull);
  });

  testWidgets('dismissing answers nothing at all', (tester) async {
    ZebuDateResult? out;
    var returned = false;
    await _host(tester, (c) async {
      out = await showZebuDatePicker(
        c,
        initial: DateTime(2026, 6, 10),
        firstDate: _first,
        lastDate: _last,
      );
      returned = true;
    });

    // Tap the barrier, well away from the panel.
    await tester.tapAt(const Offset(20, 20));
    await tester.pumpAndSettle();

    expect(returned, isTrue);
    expect(out, isNull);
  });

  testWidgets('no clear link when the field is already empty', (tester) async {
    await _host(
      tester,
      (c) async => showZebuDatePicker(
        c,
        firstDate: _first,
        lastDate: _last,
        clearLabel: null,
      ),
    );

    expect(find.text('Clear'), findsNothing);
    // Apply is present but inert until a day is picked.
    expect(find.text('Apply'), findsOneWidget);
  });

  testWidgets('days outside the range do not answer', (tester) async {
    ZebuDateResult? out;
    await _host(
      tester,
      (c) async => out = await showZebuDatePicker(
        c,
        initial: DateTime(2026, 6, 10),
        // Only the 5th to the 20th is selectable.
        firstDate: DateTime(2026, 6, 5),
        lastDate: DateTime(2026, 6, 20),
        withTime: false,
      ),
    );

    await tester.tap(find.text('2'));
    await tester.pumpAndSettle();
    expect(out, isNull, reason: 'before firstDate');

    await tester.tap(find.text('25'));
    await tester.pumpAndSettle();
    expect(out, isNull, reason: 'after lastDate');

    await tester.tap(find.text('12'));
    await tester.pumpAndSettle();
    expect(out!.date, DateTime(2026, 6, 12));
  });

  testWidgets('the month label opens a year list that moves the grid', (
    tester,
  ) async {
    await _host(
      tester,
      (c) async => showZebuDatePicker(
        c,
        initial: DateTime(2026, 6, 10),
        firstDate: _first,
        lastDate: _last,
      ),
    );

    expect(find.text('June 2026'), findsOneWidget);

    await tester.tap(find.text('June 2026'));
    await tester.pumpAndSettle();
    // The grid is replaced by the year list, so no day cells remain.
    expect(find.text('17'), findsNothing);

    await tester.tap(find.text('2026'));
    await tester.pumpAndSettle();
    expect(find.text('June 2026'), findsOneWidget);
    expect(find.text('17'), findsOneWidget);
  });

  testWidgets('month chevrons stop at the range ends', (tester) async {
    await _host(
      tester,
      (c) async => showZebuDatePicker(
        c,
        initial: DateTime(2026, 6, 10),
        firstDate: _first,
        lastDate: _last,
      ),
    );

    // Back one from June is May, before firstDate — the chevron is disabled,
    // so the label must not move.
    await tester.tap(find.byIcon(Icons.chevron_left_rounded));
    await tester.pumpAndSettle();
    expect(find.text('June 2026'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.chevron_right_rounded));
    await tester.pumpAndSettle();
    expect(find.text('July 2026'), findsOneWidget);
  });

  testWidgets('an edited time rides along with the picked day', (tester) async {
    ZebuDateResult? out;
    await _host(
      tester,
      (c) async => out = await showZebuDatePicker(
        c,
        initial: DateTime(2026, 6, 10, 9, 30),
        firstDate: _first,
        lastDate: _last,
      ),
    );

    // 09:30 → hour up → 10:30 → minute down → 10:29 → PM → 22:29.
    await tester.tap(_up.at(0));
    await tester.pumpAndSettle();
    await tester.tap(_down.at(1));
    await tester.pumpAndSettle();
    await tester.tap(find.text('PM'));
    await tester.pumpAndSettle();

    // Loose finders: the grid carries a day 10 and a day 29 of its own, so
    // the committed value below is what actually pins the time down.
    expect(find.text('10'), findsWidgets);
    expect(find.text('29'), findsWidgets);

    await tester.tap(find.text('12'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Apply'));
    await tester.pumpAndSettle();

    expect(out!.date, DateTime(2026, 6, 12, 22, 29));
  });

  testWidgets('minutes carry into the hour instead of wrapping in place', (
    tester,
  ) async {
    ZebuDateResult? out;
    await _host(
      tester,
      (c) async => out = await showZebuDatePicker(
        c,
        // One minute short of the hour, and one short of noon.
        initial: DateTime(2026, 6, 10, 11, 59),
        firstDate: _first,
        lastDate: _last,
      ),
    );

    expect(find.text('59'), findsOneWidget);
    await tester.tap(_up.at(1));
    await tester.pumpAndSettle();

    // 11:59 AM + 1 minute is noon, so the minute resets, the hour carries and
    // AM/PM follows — the three cannot disagree because they are one counter.
    expect(find.text('00'), findsOneWidget);
    expect(find.text('12'), findsWidgets);

    await tester.tap(find.text('17'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Apply'));
    await tester.pumpAndSettle();
    expect(out!.date, DateTime(2026, 6, 17, 12, 0));
  });

  testWidgets('stepping below midnight wraps instead of going negative', (
    tester,
  ) async {
    ZebuDateResult? out;
    await _host(
      tester,
      (c) async => out = await showZebuDatePicker(
        c,
        initial: DateTime(2026, 6, 10, 0, 0),
        firstDate: _first,
        lastDate: _last,
      ),
    );

    await tester.tap(_down.at(1));
    await tester.pumpAndSettle();

    await tester.tap(find.text('17'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Apply'));
    await tester.pumpAndSettle();

    // 00:00 − 1 minute is 23:59, never −1.
    expect(out!.date, DateTime(2026, 6, 17, 23, 59));
  });

  testWidgets('there is no way to type an out-of-range time', (tester) async {
    await _host(
      tester,
      (c) async => showZebuDatePicker(
        c,
        initial: DateTime(2026, 6, 10, 9, 30),
        firstDate: _first,
        lastDate: _last,
      ),
    );

    // The old control was two text fields that clamped only on blur, so `99`
    // could sit in the minute box looking accepted. There is no field now.
    expect(find.byType(TextField), findsNothing);
    expect(_up, findsNWidgets(2));
    expect(_down, findsNWidgets(2));
  });

  testWidgets('a short window caps the panel instead of running off it', (
    tester,
  ) async {
    // The default surface is shorter than the picker, which is the case that
    // used to hang the footer off the bottom of the screen.
    ZebuDateResult? out;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: Builder(
              builder: (context) => TextButton(
                onPressed: () async => out = await showZebuDatePicker(
                  context,
                  initial: DateTime(2026, 6, 10, 9, 30),
                  firstDate: _first,
                  lastDate: _last,
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    final screen = tester.view.physicalSize / tester.view.devicePixelRatio;
    final apply = tester.getRect(find.text('Apply'));
    expect(
      apply.bottom,
      lessThanOrEqualTo(screen.height),
      reason: 'the footer must stay on screen',
    );

    // And it still works from there.
    await tester.tap(find.text('Apply'));
    await tester.pumpAndSettle();
    expect(out!.date, DateTime(2026, 6, 10, 9, 30));
  });
}
