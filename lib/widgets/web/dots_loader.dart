import 'package:flutter/material.dart';

import '../../res/zebu_theme.dart';

/// Three-dot loading indicator, centred in whatever space it is given.
///
/// The dots fade in and out on a stagger rather than bouncing — vertical
/// motion inside a table body reads as content shifting, which is the one
/// thing a loader should never suggest.
class DotsLoader extends StatefulWidget {
  const DotsLoader({super.key, this.size = 8, this.gap = 6});

  /// Diameter of one dot.
  final double size;

  /// Space between dots.
  final double gap;

  @override
  State<DotsLoader> createState() => _DotsLoaderState();
}

class _DotsLoaderState extends State<DotsLoader>
    with SingleTickerProviderStateMixin {
  static const _dotCount = 3;

  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    // Created in initState and disposed below rather than with a
    // constructor-side `..repeat()` on a `late final`, which risked ticking
    // after the widget was unmounted when the parent swapped the loader for
    // the loaded rows.
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = ZebuTheme.of(context);
    return Center(
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) {
          return Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (var i = 0; i < _dotCount; i++) ...[
                if (i > 0) SizedBox(width: widget.gap),
                Opacity(
                  opacity: _opacityFor(i),
                  child: Container(
                    width: widget.size,
                    height: widget.size,
                    decoration: BoxDecoration(
                      color: t.textSecondary,
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
              ],
            ],
          );
        },
      ),
    );
  }

  /// Each dot runs the same fade a third of a cycle behind the last, so the
  /// brightness travels left to right and wraps.
  double _opacityFor(int index) {
    final phase = (_controller.value - index / _dotCount) % 1.0;
    // Ramp up over the first half of the phase, back down over the second —
    // a triangle wave, which reads smoother than a sine at this size.
    final wave = phase < 0.5 ? phase * 2 : (1 - phase) * 2;
    return 0.25 + wave * 0.75;
  }
}
