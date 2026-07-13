import 'package:flutter/material.dart';

/// A single shimmering placeholder block. Animates a soft highlight sweeping
/// across a rounded rectangle, tinted from the ambient theme so it works in
/// both light and dark mode without a hard-coded palette.
class SkeletonBox extends StatefulWidget {
  const SkeletonBox({
    super.key,
    this.width,
    this.height = 12,
    this.radius = 6,
  });

  final double? width;
  final double height;
  final double radius;

  @override
  State<SkeletonBox> createState() => _SkeletonBoxState();
}

class _SkeletonBoxState extends State<SkeletonBox>
    with SingleTickerProviderStateMixin {
  // Created eagerly in initState (not lazily) so that if a skeleton is disposed
  // before it ever builds, dispose tears down an existing controller rather
  // than creating a Ticker against a deactivated element.
  late final AnimationController _c;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final base = scheme.onSurface.withValues(alpha: 0.08);
    final highlight = scheme.onSurface.withValues(alpha: 0.04);

    return AnimatedBuilder(
      animation: _c,
      builder: (context, _) {
        final t = _c.value;
        return Container(
          width: widget.width,
          height: widget.height,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(widget.radius),
            gradient: LinearGradient(
              begin: Alignment(-1 - 2 * t, 0),
              end: Alignment(1 - 2 * t, 0),
              colors: [base, highlight, base],
              stops: const [0.35, 0.5, 0.65],
            ),
          ),
        );
      },
    );
  }
}

/// A placeholder card shaped like a [TicketRow]/[TaskRow]: a header line, a
/// title line, and a footer line. Shown while the first page loads.
class ListRowSkeleton extends StatelessWidget {
  const ListRowSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.6)),
      ),
      child: const Padding(
        padding: EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                SkeletonBox(width: 48, height: 12),
                Spacer(),
                SkeletonBox(width: 64, height: 20, radius: 8),
              ],
            ),
            SizedBox(height: 12),
            SkeletonBox(height: 14),
            SizedBox(height: 8),
            SkeletonBox(width: 220, height: 14),
            SizedBox(height: 14),
            Row(
              children: [
                SkeletonBox(width: 24, height: 24, radius: 12),
                SizedBox(width: 8),
                SkeletonBox(width: 120, height: 12),
                Spacer(),
                SkeletonBox(width: 40, height: 12),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// A placeholder shaped like a compact (Gmail-style) list row: a leading avatar
/// circle, a title line, and a shorter meta line. Divider matches the real
/// compact rows so the loading state lines up with what replaces it.
class CompactRowSkeleton extends StatelessWidget {
  const CompactRowSkeleton({super.key, this.divider = true});

  /// Draw a hairline divider below, mirroring the separated compact list.
  final bool divider;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(13, 11, 16, 11),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SkeletonBox(width: 38, height: 38, radius: 19),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: const [
                    Row(
                      children: [
                        Expanded(child: SkeletonBox(height: 14)),
                        SizedBox(width: 8),
                        SkeletonBox(width: 36, height: 11),
                      ],
                    ),
                    SizedBox(height: 7),
                    SkeletonBox(width: 180, height: 12),
                  ],
                ),
              ),
            ],
          ),
        ),
        // if (divider)
        //   Divider(
        //     height: 1,
        //     thickness: 0.5,
        //     indent: 66,
        //     color: scheme.outlineVariant.withValues(alpha: 0.4),
        //   ),
      ],
    );
  }
}

/// A column of [count] shimmering placeholders — drop-in initial-load
/// placeholder for a paged list. Set [compact] to mirror the dense single-line
/// layout; otherwise it shows card-shaped rows.
class ListSkeleton extends StatelessWidget {
  const ListSkeleton({super.key, this.count = 6, this.compact = false});
  final int count;

  /// Match the compact (Gmail-style) row layout instead of the rich card.
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 6),
      physics: const NeverScrollableScrollPhysics(),
      itemCount: count,
      itemBuilder: (_, i) => compact
          ? CompactRowSkeleton(divider: i < count - 1)
          : const ListRowSkeleton(),
    );
  }
}
