import 'package:flutter_test/flutter_test.dart';
import 'package:zebu_helpdesk/models/common.dart';

/// TC_450 / TC_451: the Activity tab shows events newest-first with "Created"
/// at the bottom. The API orders by `timestamp` alone (v2controller.php:128),
/// so same-second events — "Created" and the assignment written in the same
/// request — come back in an order the database never promised.
/// [ThreadEvent.newestFirst] re-sorts on (timestamp, id) before reversing;
/// `id` is auto-increment, so it restores true insertion order.
const _display = ThreadEvent.newestFirst;

ThreadEvent _e(int id, String state, String at) =>
    ThreadEvent(id: id, state: state, created: DateTime.parse(at));

void main() {
  const t0 = '2026-08-21 10:00:00';

  test('same-second events keep insertion order, newest first', () {
    // Arrived shuffled, as an untied ORDER BY may return them.
    final out = _display([
      _e(3, 'assigned', t0),
      _e(1, 'created', t0),
      _e(2, 'transferred', t0),
    ]);
    expect(out.map((e) => e.id), [3, 2, 1]);
  });

  test('Created is the last row even when it ties with later events', () {
    final out = _display([_e(1, 'created', t0), _e(2, 'assigned', t0)]);
    expect(out.last.state, 'created');
  });

  test('distinct timestamps still sort newest first', () {
    final out = _display([
      _e(1, 'created', '2026-08-21 10:00:00'),
      _e(9, 'closed', '2026-08-21 12:00:00'),
      _e(5, 'assigned', '2026-08-21 11:00:00'),
    ]);
    expect(out.map((e) => e.id), [9, 5, 1]);
  });

  test('a timestamp the payload omitted falls back to id order', () {
    final out = _display([
      ThreadEvent(id: 1, state: 'created'),
      ThreadEvent(id: 2, state: 'collab'),
    ]);
    expect(out.map((e) => e.id), [2, 1]);
  });

  test('a collaborator event survives the sort', () {
    final out = _display([
      _e(1, 'created', t0),
      _e(2, 'collab', '2026-08-21 10:05:00'),
    ]);
    expect(out.first.state, 'collab');
  });
}
