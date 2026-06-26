import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../core/assets.dart';

/// Mynt Plus-style search field: a slim grey-filled pill with a leading SVG
/// search glyph and an inline clear button. Used in list-screen app bars.
class AppSearchField extends StatefulWidget {
  const AppSearchField({
    super.key,
    required this.controller,
    required this.onSubmitted,
    required this.onClear,
    this.hintText = 'Search',
    this.autofocus = false,
  });

  final TextEditingController controller;
  final ValueChanged<String> onSubmitted;
  final VoidCallback onClear;
  final String hintText;
  final bool autofocus;

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
    final scheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final fill = isDark ? const Color(0xFF1E1E1E) : const Color(0xFFF9F9F9);
    final muted = scheme.onSurfaceVariant;
    final hasText = widget.controller.text.isNotEmpty;

    return Container(
      height: 42,
      decoration: BoxDecoration(
        color: fill,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Row(
        children: [
          const SizedBox(width: 12),
          SvgPicture.asset(
            Assets.search,
            width: 18,
            height: 18,
            colorFilter: ColorFilter.mode(muted, BlendMode.srcIn),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              controller: widget.controller,
              autofocus: widget.autofocus,
              textInputAction: TextInputAction.search,
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
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 0, vertical: 12),
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
          const SizedBox(width: 12),
        ],
      ),
    );
  }
}
