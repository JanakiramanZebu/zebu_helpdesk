import 'package:flutter/material.dart';

import '../../../widgets/skeleton.dart';

/// A dashboard-shaped loading placeholder: a section-label shimmer followed by
/// a 2-column grid of stat-tile-shaped shimmers, matching the real layout so
/// the transition from loading → loaded doesn't shift the page.
class StatGridSkeleton extends StatelessWidget {
  const StatGridSkeleton({super.key, this.rows = 3});

  /// Number of tile rows (2 tiles per row) to render.
  final int rows;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.only(left: 4, top: 4, bottom: 10),
          child: SkeletonBox(width: 96, height: 18, radius: 6),
        ),
        for (var r = 0; r < rows; r++)
          Padding(
            padding: EdgeInsets.only(bottom: r == rows - 1 ? 0 : 10),
            child: const Row(
              children: [
                Expanded(child: _TileSkeleton()),
                SizedBox(width: 10),
                Expanded(child: _TileSkeleton()),
              ],
            ),
          ),
      ],
    );
  }
}

class _TileSkeleton extends StatelessWidget {
  const _TileSkeleton();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.7)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 14),
      child: const Row(
        children: [
          SkeletonBox(width: 42, height: 42, radius: 12),
          SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                SkeletonBox(width: 48, height: 20, radius: 6),
                SizedBox(height: 8),
                SkeletonBox(width: 70, height: 11, radius: 5),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
