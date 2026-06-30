import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../core/assets.dart';

/// Mynt Plus-style search field: a soft grey-filled pill with a leading SVG
/// search glyph, an inline clear button, and an optional trailing action
/// (e.g. a filter/tune button). Used in list-screen app bars.
class AppSearchField extends StatefulWidget {
  const AppSearchField({
    super.key,
    required this.controller,
    required this.onSubmitted,
    required this.onClear,
    this.onChanged,
    this.hintText = 'Search',
    this.autofocus = false,
    this.trailing,
  });

  final TextEditingController controller;
  final ValueChanged<String> onSubmitted;
  final VoidCallback onClear;

  /// Fires on every keystroke — wire this for live/as-you-type search.
  final ValueChanged<String>? onChanged;
  final String hintText;
  final bool autofocus;

  /// Optional action rendered at the far right of the pill — typically an
  /// [IconButton] for filtering/adding (the "Search & add" variant).
  final Widget? trailing;

  @override
  State<AppSearchField> createState() => _AppSearchFieldState();
}

class _AppSearchFieldState extends State<AppSearchField> {
  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onChange);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onChange);
    super.dispose();
  }

  void _onChange() => setState(() {});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final fill = isDark ? const Color(0xFF1E1E1E) : const Color(0xFFF1F1F1);
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    final hasText = widget.controller.text.isNotEmpty;

    return Container(
      height: 42,
      decoration: BoxDecoration(
        color: fill,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          const SizedBox(width: 14),
          SvgPicture.asset(
            Assets.search,
            width: 18,
            height: 18,
            colorFilter: ColorFilter.mode(muted, BlendMode.srcIn),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: TextField(
              controller: widget.controller,
              autofocus: widget.autofocus,
              textInputAction: TextInputAction.search,
              onChanged: widget.onChanged,
              onSubmitted: widget.onSubmitted,
              style: const TextStyle(fontSize: 14),
              decoration: InputDecoration(
                isDense: true,
                hintText: widget.hintText,
                hintStyle: TextStyle(fontSize: 14, color: muted),
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                filled: false,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 0,
                  vertical: 10,
                ),
              ),
            ),
          ),
          if (hasText)
            InkResponse(
              radius: 18,
              onTap: () {
                widget.controller.clear();
                widget.onClear();
              },
              child: Icon(Icons.close, size: 18, color: muted),
            ),
          if (widget.trailing != null) ...[
            const SizedBox(width: 4),
            widget.trailing!,
            const SizedBox(width: 6),
          ] else
            const SizedBox(width: 14),
        ],
      ),
    );
  }
}
