import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Density options for scrollable list screens (Tickets / Tasks).
enum ListLayout {
  /// Rich card: two-line subject, requester, department/assignee. Fewer per
  /// screen, easiest to read.
  comfortable('Comfortable'),

  /// Dense single-line row: number + subject + status. More items per screen,
  /// best for scanning.
  compact('Compact');

  const ListLayout(this.label);
  final String label;
}

/// Owns the user's preferred [ListLayout] and persists it so it survives
/// restarts. Shared across the Tickets and Tasks lists.
class ListLayoutController extends Notifier<ListLayout> {
  static const _key = 'list_layout';
  static const _storage = FlutterSecureStorage();

  @override
  ListLayout build() {
    _load();
    return ListLayout.comfortable;
  }

  Future<void> _load() async {
    final raw = await _storage.read(key: _key);
    final layout = _parse(raw);
    if (layout != state) state = layout;
  }

  Future<void> set(ListLayout layout) async {
    if (layout == state) return;
    state = layout;
    await _storage.write(key: _key, value: layout.name);
  }

  void toggle() => set(
    state == ListLayout.comfortable
        ? ListLayout.compact
        : ListLayout.comfortable,
  );

  static ListLayout _parse(String? raw) => switch (raw) {
    'compact' => ListLayout.compact,
    _ => ListLayout.comfortable,
  };
}

final listLayoutProvider = NotifierProvider<ListLayoutController, ListLayout>(
  ListLayoutController.new,
);
