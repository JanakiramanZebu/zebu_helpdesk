import 'package:flutter/material.dart';

import '../core/theme/app_text.dart';
import 'selection_check.dart';

/// The "Select all" toggle bar shown above a list while in multi-select mode.
/// The selected count lives in the app bar (see [buildSelectionAppBar]); this
/// bar only owns the select-all affordance. Shared by the ticket and task
/// lists so selection UI stays consistent.
class SelectionBar extends StatelessWidget {
  const SelectionBar({
    super.key,
    required this.allSelected,
    required this.onToggleSelectAll,
    this.trailing,
  });

  final bool allSelected;
  final VoidCallback onToggleSelectAll;

  /// Optional trailing widget (e.g. a hint). Usually null.
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
      decoration: BoxDecoration(
        color: scheme.surface,
        border: Border(
          bottom: BorderSide(color: scheme.outlineVariant, width: 1),
        ),
      ),
      child: Row(
        children: [
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onToggleSelectAll,
            child: Row(
              children: [
                SelectionCheck(selected: allSelected, size: 20),
                const SizedBox(width: 10),
                AppText.custmText(
                  context,
                  allSelected ? 'Deselect all' : 'Select all',
                  fs: 13,
                  fw: 1,
                  color: scheme.onSurface,
                ),
              ],
            ),
          ),
          const Spacer(),
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}

/// Builds the selection-mode app bar shared by the ticket and task lists: a
/// close button, an "N selected" title, and — when not [busy] — a primary
/// action plus an overflow menu of [menuItems].
///
/// Feature-specific behaviour is injected via [primaryAction] and [menuItems];
/// everything else (layout, busy spinner, title) is identical across screens.
PreferredSizeWidget buildSelectionAppBar(
  BuildContext context, {
  required int selectedCount,
  required VoidCallback onCancel,
  required bool busy,
  required Widget primaryAction,
  required void Function(String value) onMenuSelected,
  required List<PopupMenuEntry<String>> menuItems,
}) {
  return AppBar(
    leading: IconButton(
      icon: const Icon(Icons.close),
      tooltip: 'Cancel',
      onPressed: onCancel,
    ),
    title: AppText.titleText(context, '$selectedCount selected', fw: 1),
    actions: busy
        ? const [
            Padding(
              padding: EdgeInsets.symmetric(horizontal: 18),
              child: Center(
                child: SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2.4),
                ),
              ),
            ),
          ]
        : [
            primaryAction,
            PopupMenuButton<String>(
              onSelected: onMenuSelected,
              itemBuilder: (_) => menuItems,
            ),
          ],
  );
}

/// Convenience builder for a text popup-menu entry that respects the AppText
/// styling used everywhere else, so menus stay visually consistent.
PopupMenuItem<String> selectionMenuItem(
  BuildContext context, {
  required String value,
  required String label,
  bool destructive = false,
}) {
  return PopupMenuItem<String>(
    value: value,
    child: AppText.subText(
      context,
      label,
      color: destructive ? Theme.of(context).colorScheme.error : null,
    ),
  );
}
