import 'package:flutter/material.dart';

import '../../core/assets.dart';
import '../../res/zebu_theme.dart';
import '../../res/zebu_spacing.dart';
import '../svg_icon.dart';
import '../../res/zebu_text_styles.dart';

/// Unified search input used at the top of every list screen.
///
/// Simplified "subtle-fill" style: no hairline border at rest — the field
/// reads as a soft filled rectangle so it recedes into the header
/// chrome. Hover deepens the fill, focus lifts the field to `bgElevated`
/// with a 1 px accent hairline. Same 40 px height as the filter button
/// so the two sit on one baseline.
class ListSearchInput extends StatefulWidget {
  const ListSearchInput({
    super.key,
    required this.onChanged,
    this.hintText = 'Search…',
    this.autofocus = false,
  });

  final ValueChanged<String> onChanged;
  final String hintText;
  final bool autofocus;

  @override
  State<ListSearchInput> createState() => _ListSearchInputState();
}

class _ListSearchInputState extends State<ListSearchInput> {
  final _controller = TextEditingController();
  final _focus = FocusNode();

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = ZebuTheme.of(context);
    // White surface with a hairline border — reads as a proper outlined
    // input (matches the filter button beside it and the app's other
    // form fields). Static: no hover fill shift or focus color change,
    // so the geometry never moves under the user.
    return MouseRegion(
      cursor: SystemMouseCursors.text,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: t.bgElevated,
          borderRadius: BorderRadius.circular(5),
          border: Border.all(color: t.borderSubtle, width: 1),
        ),
        child: SizedBox(
          height: 40,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: ZebuSpacing.s3),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                SvgIcon(Assets.search, size: 16, color: t.textSecondary),
                // const SizedBox(width: 4),
                Expanded(
                  child: TextField(
                    controller: _controller,
                    focusNode: _focus,
                    autofocus: widget.autofocus,
                    onChanged: (v) {
                      widget.onChanged(v);
                      setState(() {});
                    },
                    textAlign: TextAlign.start,
                    // Center the text baseline in the input box so it lines
                    // up with the leading icon's optical center. Left to its
                    // default the field would draw text a couple of pixels
                    // above center.
                    textAlignVertical: TextAlignVertical.center,
                    style: ZebuTextStyles.body(
                      context,
                    ).copyWith(fontWeight: FontWeight.w500),
                    decoration: InputDecoration(
                      isCollapsed: true,
                      // The global inputDecorationTheme fills every TextField with
                      // grey `#F9F9F9` and paints an `enabledBorder` — great for
                      // full-page forms, wrong here because the outer
                      // AnimatedContainer already owns the border. Override all
                      // four border slots + filled so the field paints as a plain
                      // transparent text run inside the container.
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      disabledBorder: InputBorder.none,
                      errorBorder: InputBorder.none,
                      focusedErrorBorder: InputBorder.none,
                      filled: false,
                      fillColor: Colors.transparent,
                      hoverColor: Colors.transparent,
                      hintText: widget.hintText,
                      hintStyle: ZebuTextStyles.body(
                        context,
                      ).copyWith(color: t.textSecondary, letterSpacing: -0.1),
                    ),
                  ),
                ),
                if (_controller.text.isNotEmpty)
                  _ClearButton(
                    onTap: () {
                      _controller.clear();
                      widget.onChanged('');
                      setState(() {});
                    },
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ClearButton extends StatefulWidget {
  const _ClearButton({required this.onTap});
  final VoidCallback onTap;

  @override
  State<_ClearButton> createState() => _ClearButtonState();
}

class _ClearButtonState extends State<_ClearButton> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final t = ZebuTheme.of(context);
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 100),
          width: 22,
          height: 22,
          decoration: BoxDecoration(
            color: _hover ? t.bgHover : Colors.transparent,
            borderRadius: BorderRadius.circular(ZebuRadius.rFull),
          ),
          child: Icon(Icons.close_rounded, size: 14, color: t.textSecondary),
        ),
      ),
    );
  }
}
