import 'package:flutter/material.dart';

import '../../res/zebu_status_style.dart';
import '../../res/zebu_text_styles.dart';
import '../../res/zebu_theme.dart';

/// Badge for a ticket / task status.
///
/// Separate from `StatusPill`, which stays the generic tinted chip for tags
/// and anything else with a single arbitrary colour. A *status* is not
/// arbitrary — it comes from a fixed vocabulary with a designed fill weight,
/// edge, and glyph per value — and giving it its own widget is what stops a
/// screen from passing a status through the generic path and quietly losing
/// all of that.
class StatusBadge extends StatelessWidget {
  const StatusBadge({
    super.key,
    required this.label,
    required this.status,
    this.overdue = false,
    this.dense = false,
  });

  /// Text shown. Usually [status] itself, but the two are separate so a
  /// screen can show "Overdue" while styling against the real status.
  final String label;
  final String status;
  final bool overdue;
  final bool dense;

  @override
  Widget build(BuildContext context) => _BadgeBody(
    style: zebuStatusStyle(status, ZebuTheme.of(context), overdue: overdue),
    label: label,
    dense: dense,
  );
}

/// Badge for a ticket / task priority — same shell, different vocabulary.
/// See [zebuPriorityStyle].
class PriorityBadge extends StatelessWidget {
  const PriorityBadge({
    super.key,
    required this.label,
    required this.priority,
    this.dense = false,
  });

  final String label;
  final String? priority;
  final bool dense;

  @override
  Widget build(BuildContext context) => _BadgeBody(
    style: zebuPriorityStyle(priority, ZebuTheme.of(context)),
    label: label,
    dense: dense,
  );
}

/// The shared shell. Status and priority differ only in which table resolved
/// the style, so the rendering lives in exactly one place.
class _BadgeBody extends StatelessWidget {
  const _BadgeBody({
    required this.style,
    required this.label,
    required this.dense,
  });

  final ZebuStatusStyle style;
  final String label;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final s = style;
    final content = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        // if (s.icon != null) ...[
        //   Icon(s.icon, size: dense ? 11 : 12, color: s.ink),
        //   const SizedBox(width: 5),
        // ] else if (s.mark != ZebuStatusMark.none) ...[
        //   _Mark(mark: s.mark, color: s.ink),
        //   const SizedBox(width: 6),
        // ],
        Flexible(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style:
                ZebuFonts.face(
                  fontSize: dense ? 11.0 : 11.5,
                  fontWeight: ZebuFonts.semiBold,
                  color: s.ink,
                ).copyWith(
                  decoration: s.strikethrough
                      ? TextDecoration.lineThrough
                      : null,
                  decorationColor: s.ink,
                ),
          ),
        ),
      ],
    );

    final padding = dense
        ? const EdgeInsets.symmetric(horizontal: 7, vertical: 2)
        : const EdgeInsets.symmetric(horizontal: 9, vertical: 3);

    // A dashed edge needs a painter — Flutter's BorderSide has no dash
    // pattern — so the two edge styles take different paths to the same shape.
    if (s.dashed && s.border != null) {
      return CustomPaint(
        foregroundPainter: _DashedPill(color: s.border!),
        child: Container(
          padding: padding,
          decoration: BoxDecoration(
            color: s.bg,
            borderRadius: BorderRadius.circular(999),
          ),
          child: content,
        ),
      );
    }

    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: s.bg,
        border: s.border == null
            ? null
            : Border.all(color: s.border!, width: 1),
        borderRadius: BorderRadius.circular(999),
      ),
      child: content,
    );
  }
}

/// Dot, ring, dot-in-a-ring, or signal bars. Painted rather than assembled
/// from `Container`s so the halo can overlap without adding layout width.
class _Mark extends StatelessWidget {
  const _Mark({required this.mark, required this.color});
  final ZebuStatusMark mark;
  final Color color;

  bool get _isBars =>
      mark == ZebuStatusMark.bars1 ||
      mark == ZebuStatusMark.bars2 ||
      mark == ZebuStatusMark.bars3;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: _isBars ? 11 : (mark == ZebuStatusMark.haloDot ? 10 : 6),
    height: _isBars ? 10 : (mark == ZebuStatusMark.haloDot ? 10 : 6),
    child: CustomPaint(
      painter: _MarkPainter(mark: mark, color: color),
    ),
  );
}

class _MarkPainter extends CustomPainter {
  const _MarkPainter({required this.mark, required this.color});
  final ZebuStatusMark mark;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    switch (mark) {
      case ZebuStatusMark.none:
        return;
      case ZebuStatusMark.dot:
        canvas.drawCircle(c, 3, Paint()..color = color);
      case ZebuStatusMark.hollowDot:
        canvas.drawCircle(
          c,
          2.25,
          Paint()
            ..color = color
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.5,
        );
      case ZebuStatusMark.haloDot:
        canvas.drawCircle(c, 5, Paint()..color = color.withValues(alpha: 0.25));
        canvas.drawCircle(c, 3, Paint()..color = color);
      case ZebuStatusMark.bars1:
      case ZebuStatusMark.bars2:
      case ZebuStatusMark.bars3:
        _bars(canvas, size);
    }
  }

  /// Three ascending bars, with the ones above the level ghosted rather than
  /// omitted. The empty slots are what make the level readable — a lone short
  /// bar says nothing without the taller ones it failed to reach, the way a
  /// battery gauge needs its empty portion.
  void _bars(Canvas canvas, Size size) {
    final filled = switch (mark) {
      ZebuStatusMark.bars1 => 1,
      ZebuStatusMark.bars2 => 2,
      _ => 3,
    };
    const w = 2.5, gap = 1.75;
    const heights = [4.0, 7.0, 10.0];
    for (var i = 0; i < 3; i++) {
      final h = heights[i];
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(i * (w + gap), size.height - h, w, h),
          const Radius.circular(1),
        ),
        Paint()..color = i < filled ? color : color.withValues(alpha: 0.28),
      );
    }
  }

  @override
  bool shouldRepaint(_MarkPainter old) =>
      old.mark != mark || old.color != color;
}

/// Dashed pill outline, painted in the foreground so the dashes sit on top of
/// the fill rather than being covered by it.
class _DashedPill extends CustomPainter {
  const _DashedPill({required this.color});
  final Color color;

  static const double _on = 3;
  static const double _off = 3;

  @override
  void paint(Canvas canvas, Size size) {
    final rrect = RRect.fromRectAndRadius(
      Offset.zero & size,
      const Radius.circular(999),
    ).deflate(0.5);
    final pen = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    for (final m in (Path()..addRRect(rrect)).computeMetrics()) {
      var d = 0.0;
      while (d < m.length) {
        final end = (d + _on).clamp(0.0, m.length);
        canvas.drawPath(m.extractPath(d, end), pen);
        d = end + _off;
      }
    }
  }

  @override
  bool shouldRepaint(_DashedPill old) => old.color != color;
}
