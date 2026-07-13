import 'package:flutter/material.dart';

import '../core/theme/app_text.dart';

/// Shared modal bottom-sheet scaffold used across the app.
///
/// Gives every sheet the same Jira / Asana / ClickUp-style treatment:
/// the theme's grabber up top (from [AppTheme.bottomSheetTheme]), a bold
/// title row, a hairline divider, and a keyboard-aware, scrollable body.
/// All colours and fonts come from the global [ThemeData] — this widget
/// adds no hard-coded palette of its own. Sheets are dismissed by the
/// grabber, a downward swipe, or tapping the scrim (no close button).
///
/// Present it with [showAppSheet], or drop [AppSheet] straight into any
/// existing `showModalBottomSheet` builder.
class AppSheet extends StatelessWidget {
  const AppSheet({
    super.key,
    required this.title,
    required this.child,
    this.subtitle,
    this.actions,
    this.scrollable = true,
    this.padding = const EdgeInsets.fromLTRB(20, 4, 20, 20),
  });

  /// Bold heading shown at the top-left of the sheet.
  final String title;

  /// Optional muted line under the title.
  final String? subtitle;

  /// Optional trailing widgets placed at the end of the header row (e.g. an
  /// "Add" action).
  final List<Widget>? actions;

  /// Sheet body. Typically a [Column] of form fields or a list.
  final Widget child;

  /// Whether the body scrolls. Keep `true` for forms so the keyboard never
  /// clips content; set `false` when [child] manages its own scrolling
  /// (e.g. it already contains a [ListView]).
  final bool scrollable;

  /// Padding around the body (below the header).
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final viewInsets = MediaQuery.of(context).viewInsets.bottom;

    // Compact grabber (~20px tall) in place of Material's 48px handle box, so
    // the sheet header sits close to the top edge.
    final grabber = Center(
      child: Container(
        width: 32,
        height: 4,
        margin: const EdgeInsets.only(top: 10, bottom: 8),
        decoration: BoxDecoration(
          color: scheme.onSurfaceVariant.withValues(alpha: 0.3),
          borderRadius: BorderRadius.circular(100),
        ),
      ),
    );

    final header = Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                AppText.titleText(context, title, fw: 2),
                if (subtitle != null) ...[
                  const SizedBox(height: 2),
                  AppText.paraText(
                    context,
                    subtitle!,
                    color: scheme.onSurfaceVariant,
                  ),
                ],
              ],
            ),
          ),
          if (actions != null) ...actions!,
        ],
      ),
    );

    final divider = Divider(
      height: 1,
      thickness: 1,
      color: scheme.outlineVariant,
    );

    final body = Padding(
      padding: padding.add(EdgeInsets.only(bottom: viewInsets)),
      child: child,
    );

    return SafeArea(
      top: false,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          grabber,
          header,
          divider,
          if (scrollable)
            Flexible(
              child: SingleChildScrollView(
                physics: const ClampingScrollPhysics(),
                child: body,
              ),
            )
          else
            Flexible(child: body),
        ],
      ),
    );
  }
}

/// Search field styled for use inside a sheet or dialog: a soft grey-filled
/// pill with a leading search glyph and an inline clear button, with no
/// enabled/focused/input borders — matching the app's list-screen search box.
///
/// Unlike the app-bar [AppSearchField], this uses a Material icon (no SVG
/// asset dependency) so it drops cleanly into any sheet body.
class SheetSearchField extends StatelessWidget {
  const SheetSearchField({
    super.key,
    required this.controller,
    this.hintText = 'Search',
    this.onChanged,
    this.onSubmitted,
    this.onClear,
    this.autofocus = false,
  });

  final TextEditingController controller;
  final String hintText;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final VoidCallback? onClear;
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final fill = isDark ? const Color(0xFF1E1E1E) : const Color(0xFFF1F1F1);
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;

    return Container(
      height: 44,
      decoration: BoxDecoration(
        color: fill,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          const SizedBox(width: 12),
          Icon(Icons.search, size: 20, color: muted),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              controller: controller,
              autofocus: autofocus,
              textInputAction: TextInputAction.search,
              onChanged: onChanged,
              onSubmitted: onSubmitted,
              style: AppText.style(context, fontSize: 14),
              decoration: InputDecoration(
                isDense: true,
                filled: false,
                hintText: hintText,
                hintStyle: AppText.style(context, fontSize: 14, color: muted),
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(vertical: 12),
              ),
            ),
          ),
          ValueListenableBuilder<TextEditingValue>(
            valueListenable: controller,
            builder: (context, value, _) => value.text.isEmpty
                ? const SizedBox(width: 12)
                : Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: InkResponse(
                      radius: 18,
                      onTap: () {
                        controller.clear();
                        onClear?.call();
                      },
                      child: Icon(Icons.close, size: 18, color: muted),
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

/// Presents [builder]'s content inside a themed modal sheet. A thin wrapper
/// over [showModalBottomSheet] with the app's standard flags (safe-area,
/// scroll-controlled) so callers don't repeat them. Wrap the builder result
/// in an [AppSheet] for the standard header treatment.
Future<T?> showAppSheet<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool isScrollControlled = true,
}) {
  return showModalBottomSheet<T>(
    context: context,
    useSafeArea: true,
    isScrollControlled: isScrollControlled,
    builder: builder,
  );
}
