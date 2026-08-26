import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zebu_helpdesk/widgets/action_menu.dart';

/// TK-019 / TC_459-464: the ⋮ menu is built as permission-gated groups —
/// workflow, assignment, attributes, relations, metadata, delete — and a
/// divider separates them. Gating a whole group out must not leave a dangling
/// or doubled divider behind.
PopupMenuItem<String> _item(String v) =>
    PopupMenuItem<String>(value: v, child: Text(v));

int _dividers(List<PopupMenuEntry<String>> out) =>
    out.whereType<PopupMenuDivider>().length;

List<String> _values(List<PopupMenuEntry<String>> out) => [
  for (final e in out)
    if (e is PopupMenuItem<String>) e.value!,
];

void main() {
  test('a divider is inserted between every pair of non-empty groups', () {
    final out = joinMenuGroups([
      [_item('status'), _item('mark')],
      [_item('assign')],
      [_item('delete')],
    ]);
    expect(_dividers(out), 2);
    expect(_values(out), ['status', 'mark', 'assign', 'delete']);
  });

  test('an empty group contributes no divider', () {
    final out = joinMenuGroups([
      [_item('status')],
      <PopupMenuEntry<String>>[], // whole group gated out by permission
      [_item('delete')],
    ]);
    expect(_dividers(out), 1);
  });

  test('no leading divider when the first groups are all gated out', () {
    final out = joinMenuGroups([
      <PopupMenuEntry<String>>[],
      <PopupMenuEntry<String>>[],
      [_item('collaborators')],
    ]);
    expect(_dividers(out), 0);
    expect(out.first, isA<PopupMenuItem<String>>());
  });

  test('no trailing divider when the last groups are all gated out', () {
    final out = joinMenuGroups([
      [_item('collaborators')],
      <PopupMenuEntry<String>>[],
      <PopupMenuEntry<String>>[],
    ]);
    expect(_dividers(out), 0);
    expect(out.last, isA<PopupMenuItem<String>>());
  });

  test('never two dividers in a row', () {
    final out = joinMenuGroups([
      [_item('a')],
      <PopupMenuEntry<String>>[],
      <PopupMenuEntry<String>>[],
      [_item('b')],
    ]);
    expect(_dividers(out), 1);
    for (var i = 0; i < out.length - 1; i++) {
      expect(out[i] is PopupMenuDivider && out[i + 1] is PopupMenuDivider,
          isFalse);
    }
  });

  test('an agent with only Collaborators sees one item and no dividers', () {
    // The permission floor: TK-019 keeps Collaborators available to everyone.
    final out = joinMenuGroups([
      <PopupMenuEntry<String>>[],
      <PopupMenuEntry<String>>[],
      <PopupMenuEntry<String>>[],
      <PopupMenuEntry<String>>[],
      [_item('collaborators')],
      <PopupMenuEntry<String>>[],
    ]);
    expect(out, hasLength(1));
    expect(_dividers(out), 0);
  });
}
