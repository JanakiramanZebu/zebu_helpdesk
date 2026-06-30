import 'package:flutter/material.dart';
import 'package:intl/intl.dart' show DateFormat;

/// One plotted line (e.g. "Opened" or "Closed").
class ChartSeries {
  const ChartSeries({
    required this.label,
    required this.color,
    required this.values,
  });

  final String label;
  final Color color;
  final List<double> values;
}

/// A dependency-free line + area chart for daily ticket activity, styled to
/// match the osTicket "Ticket Activity" graph. Draws gridlines, a Y scale,
/// a few X date labels, area fills, lines, and (for short ranges) point dots.
class ActivityLineChart extends StatelessWidget {
  const ActivityLineChart({
    super.key,
    required this.series,
    required this.dates,
    this.height = 200,
  });

  final List<ChartSeries> series;
  final List<DateTime?> dates;
  final double height;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SizedBox(
      height: height,
      width: double.infinity,
      child: CustomPaint(
        painter: _LineChartPainter(
          series: series,
          dates: dates,
          gridColor: theme.colorScheme.outlineVariant,
          labelColor: theme.colorScheme.onSurfaceVariant,
          labelStyle:
              theme.textTheme.bodySmall ?? const TextStyle(fontSize: 11),
        ),
      ),
    );
  }
}

enum _HAlign { left, center, right }

class _LineChartPainter extends CustomPainter {
  _LineChartPainter({
    required this.series,
    required this.dates,
    required this.gridColor,
    required this.labelColor,
    required this.labelStyle,
  });

  final List<ChartSeries> series;
  final List<DateTime?> dates;
  final Color gridColor;
  final Color labelColor;
  final TextStyle labelStyle;

  static final _xFmt = DateFormat('d MMM');
  static const _divisions = 4;

  @override
  void paint(Canvas canvas, Size size) {
    final n = series.isEmpty
        ? 0
        : series.map((s) => s.values.length).reduce((a, b) => a > b ? a : b);
    if (n == 0) return;

    var rawMax = 0.0;
    for (final s in series) {
      for (final v in s.values) {
        if (v > rawMax) rawMax = v;
      }
    }
    final step = _roundStep((rawMax / _divisions).ceil().clamp(1, 1 << 30));
    final maxY = (step * _divisions).toDouble();

    const leftPad = 30.0;
    const rightPad = 10.0;
    const topPad = 10.0;
    const bottomPad = 22.0;
    final chartW = size.width - leftPad - rightPad;
    final chartH = size.height - topPad - bottomPad;
    if (chartW <= 0 || chartH <= 0) return;

    final originX = leftPad;
    final originY = topPad + chartH;

    final gridStyle = labelStyle.copyWith(color: labelColor, fontSize: 10);
    final gridPaint = Paint()
      ..color = gridColor.withValues(alpha: 0.6)
      ..strokeWidth = 1;
    for (var i = 0; i <= _divisions; i++) {
      final t = i / _divisions;
      final y = topPad + chartH * t;
      canvas.drawLine(
        Offset(originX, y),
        Offset(originX + chartW, y),
        gridPaint,
      );
      _text(
        canvas,
        '${step * (_divisions - i)}',
        Offset(originX - 6, y),
        gridStyle,
        hAlign: _HAlign.right,
        vCenter: true,
      );
    }

    double xAt(int i) =>
        n == 1 ? originX + chartW / 2 : originX + chartW * (i / (n - 1));
    double yAt(double v) => topPad + chartH * (1 - (v / maxY)).clamp(0.0, 1.0);

    for (final s in series) {
      if (s.values.isEmpty) continue;
      final line = Path();
      final area = Path();
      for (var i = 0; i < s.values.length; i++) {
        final p = Offset(xAt(i), yAt(s.values[i]));
        if (i == 0) {
          line.moveTo(p.dx, p.dy);
          area.moveTo(p.dx, originY);
          area.lineTo(p.dx, p.dy);
        } else {
          line.lineTo(p.dx, p.dy);
          area.lineTo(p.dx, p.dy);
        }
      }
      area.lineTo(xAt(s.values.length - 1), originY);
      area.close();

      canvas.drawPath(
        area,
        Paint()
          ..color = s.color.withValues(alpha: 0.08)
          ..style = PaintingStyle.fill,
      );
      canvas.drawPath(
        line,
        Paint()
          ..color = s.color
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..strokeJoin = StrokeJoin.round
          ..strokeCap = StrokeCap.round,
      );

      if (n <= 31) {
        final dot = Paint()..color = s.color;
        for (var i = 0; i < s.values.length; i++) {
          canvas.drawCircle(Offset(xAt(i), yAt(s.values[i])), 2.2, dot);
        }
      }
    }

    final labelCount = n < 4 ? n : 4;
    for (var k = 0; k < labelCount; k++) {
      final i = labelCount == 1 ? 0 : (k * (n - 1) / (labelCount - 1)).round();
      final d = (i < dates.length) ? dates[i] : null;
      if (d == null) continue;
      final align = k == 0
          ? _HAlign.left
          : (k == labelCount - 1 ? _HAlign.right : _HAlign.center);
      _text(
        canvas,
        _xFmt.format(d),
        Offset(xAt(i), originY + 5),
        gridStyle,
        hAlign: align,
      );
    }
  }

  /// Round a raw step up to a "nice" number so the Y axis reads cleanly.
  int _roundStep(int s) {
    const steps = [
      1,
      2,
      5,
      10,
      15,
      20,
      25,
      50,
      100,
      150,
      200,
      250,
      500,
      1000,
      2000,
      5000,
    ];
    for (final x in steps) {
      if (s <= x) return x;
    }
    return ((s / 1000).ceil()) * 1000;
  }

  void _text(
    Canvas canvas,
    String text,
    Offset at,
    TextStyle style, {
    _HAlign hAlign = _HAlign.center,
    bool vCenter = false,
  }) {
    final tp = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: TextDirection.ltr,
    )..layout();
    var dx = at.dx;
    if (hAlign == _HAlign.right) {
      dx = at.dx - tp.width;
    } else if (hAlign == _HAlign.center) {
      dx = at.dx - tp.width / 2;
    }
    final dy = vCenter ? at.dy - tp.height / 2 : at.dy;
    tp.paint(canvas, Offset(dx, dy));
  }

  @override
  bool shouldRepaint(_LineChartPainter old) =>
      old.series != series || old.dates != dates;
}
