import 'package:flutter/material.dart';

import '../core/theme/app_text.dart';
import '../models/meta.dart';
import 'app_search_field.dart';
import 'app_sheet.dart';

/// Bottom-sheet multi-select over a `GET /meta/{kind}` list — the mobile
/// equivalent of the web's `<select multiple>` filter boxes ("Hold Ctrl/Cmd to
/// select multiple. Leave none selected for all.").
///
/// Returns the chosen ids, or null if the sheet was dismissed without applying.
/// An empty set is a meaningful result: it means "all", same as the web.
Future<Set<int>?> pickMultiMeta(
  BuildContext context, {
  required String title,
  required List<MetaItem> items,
  required Set<int> selected,
}) => showAppSheet<Set<int>>(
  context: context,
  builder: (_) =>
      _MultiSelectSheet(title: title, items: items, initial: selected),
);

class _MultiSelectSheet extends StatefulWidget {
  const _MultiSelectSheet({
    required this.title,
    required this.items,
    required this.initial,
  });

  final String title;
  final List<MetaItem> items;
  final Set<int> initial;

  @override
  State<_MultiSelectSheet> createState() => _MultiSelectSheetState();
}

class _MultiSelectSheetState extends State<_MultiSelectSheet> {
  late final Set<int> _picked = {...widget.initial};
  final _searchCtrl = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  List<MetaItem> get _visible {
    if (_query.isEmpty) return widget.items;
    final q = _query.toLowerCase();
    return [
      for (final i in widget.items)
        if (i.name.toLowerCase().contains(q)) i,
    ];
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final visible = _visible;
    // Long lists get a search box, matching the single-select picker's rule.
    final searchable = widget.items.length > 8;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 8, 4),
          child: Row(
            children: [
              Expanded(child: AppText.titleText(context, widget.title, fw: 2)),
              if (_picked.isNotEmpty)
                TextButton(
                  onPressed: () => setState(_picked.clear),
                  child: const Text('Clear'),
                ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: AppText.paraText(
            context,
            _picked.isEmpty
                ? 'None selected — all included'
                : '${_picked.length} selected',
            color: scheme.onSurfaceVariant,
          ),
        ),
        if (searchable)
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 6),
            child: AppSearchField(
              controller: _searchCtrl,
              hintText: 'Search ${widget.title.toLowerCase()}',
              onChanged: (v) => setState(() => _query = v.trim()),
              onSubmitted: (v) => setState(() => _query = v.trim()),
              onClear: () => setState(() => _query = ''),
            ),
          ),
        Flexible(
          child: visible.isEmpty
              ? Padding(
                  padding: const EdgeInsets.all(24),
                  child: AppText.paraText(context, 'Nothing matches'),
                )
              : ListView.builder(
                  shrinkWrap: true,
                  itemCount: visible.length,
                  itemBuilder: (_, i) {
                    final item = visible[i];
                    return CheckboxListTile(
                      dense: true,
                      controlAffinity: ListTileControlAffinity.leading,
                      value: _picked.contains(item.id),
                      title: AppText.custmText(
                        context,
                        item.name,
                        fs: 14,
                        fw: 0,
                      ),
                      onChanged: (on) => setState(() {
                        if (on == true) {
                          _picked.add(item.id);
                        } else {
                          _picked.remove(item.id);
                        }
                      }),
                    );
                  },
                ),
        ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
            child: SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: () => Navigator.pop(context, _picked),
                child: const Text('Apply'),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
