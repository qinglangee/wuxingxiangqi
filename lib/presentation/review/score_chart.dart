import 'dart:math';

import 'package:flutter/material.dart';

import '../../../domain/models/piece.dart';
import '../../../domain/review/review_analysis.dart';

/// 局势折线图：展示每步局面的评分（红方视角）。
///
/// X 轴 = 棋谱序号（0=起始局面），Y 轴 = 评分（正值红优，负值黑优）。
/// 中线（0 分）为水平基准线，上方红优、下方黑优。
/// 竖向光标线可拖动，拖动时切换棋谱到对应节点并显示当前评分。
class ScoreChart extends StatefulWidget {
  const ScoreChart({
    super.key,
    required this.evaluations,
    required this.currentIndex,
    required this.onCursorMoved,
  });

  final List<MoveEvaluation> evaluations;
  final int currentIndex;
  final ValueChanged<int> onCursorMoved;

  @override
  State<ScoreChart> createState() => _ScoreChartState();
}

class _ScoreChartState extends State<ScoreChart> {
  /// Y 轴最大绝对值（厘兵）。初始为 50，当有评分超过此值时自动扩大（只增不减）。
  double _yMax = 50.0;

  @override
  void initState() {
    super.initState();
    _yMax = _computeMaxAbs(widget.evaluations);
  }

  @override
  void didUpdateWidget(covariant ScoreChart oldWidget) {
    super.didUpdateWidget(oldWidget);
    final newMax = _computeMaxAbs(widget.evaluations);
    if (newMax > _yMax) {
      setState(() => _yMax = newMax);
    }
  }

  /// 计算评估数据中绝对值的最大值，下限为 50。
  double _computeMaxAbs(List<MoveEvaluation> evals) {
    if (evals.isEmpty) return 50.0;
    final m = evals.map((e) => e.redPerspectiveScore.abs()).reduce(max);
    return max(50.0, m.toDouble());
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final w = constraints.maxWidth;
        final h = constraints.maxHeight;
        // 绘图区域（留出左右边距给坐标标签）
        final plotLeft = 36.0;
        final plotRight = w - 4.0;
        final plotTop = 8.0;
        final plotBottom = h - 20.0;
        final plotW = plotRight - plotLeft;
        final plotH = plotBottom - plotTop;

        return GestureDetector(
          onPanUpdate: _onPan,
          onTapDown: _onTap,
          child: CustomPaint(
            size: Size(w, h),
            painter: _ChartPainter(
              evaluations: widget.evaluations,
              currentIndex: widget.currentIndex,
              plotLeft: plotLeft,
              plotRight: plotRight,
              plotTop: plotTop,
              plotBottom: plotBottom,
              plotW: plotW,
              plotH: plotH,
              yMax: _yMax,
            ),
          ),
        );
      },
    );
  }

  void _onPan(DragUpdateDetails details) =>
      _handleDrag(details.localPosition.dx);

  void _onTap(TapDownDetails details) => _handleDrag(details.localPosition.dx);

  void _handleDrag(double localX) {
    final evals = widget.evaluations;
    if (evals.isEmpty) return;
    final plotLeft = 36.0;
    final plotRight = MediaQuery.of(context).size.width - 4.0;
    final plotW = plotRight - plotLeft;
    final n = evals.length;
    // 把 X 像素映射到序号
    final t = ((localX - plotLeft) / plotW).clamp(0.0, 1.0);
    final idx = (t * (n - 1)).round().clamp(0, n - 1);
    if (idx != widget.currentIndex) {
      widget.onCursorMoved(idx);
    }
  }
}

class _ChartPainter extends CustomPainter {
  const _ChartPainter({
    required this.evaluations,
    required this.currentIndex,
    required this.plotLeft,
    required this.plotRight,
    required this.plotTop,
    required this.plotBottom,
    required this.plotW,
    required this.plotH,
    required this.yMax,
  });

  final List<MoveEvaluation> evaluations;
  final int currentIndex;
  final double plotLeft;
  final double plotRight;
  final double plotTop;
  final double plotBottom;
  final double plotW;
  final double plotH;
  final double yMax;

  double _xOfIndex(int i) {
    if (evaluations.length <= 1) return plotLeft + plotW / 2;
    return plotLeft + (i / (evaluations.length - 1)) * plotW;
  }

  double _yOfScore(int score) {
    final clamped = score.clamp(-yMax.toInt(), yMax.toInt()).toDouble();
    final t = clamped / yMax; // -1 ~ 1
    return plotBottom - (t + 1) / 2 * plotH; // 翻转 Y
  }

  @override
  void paint(Canvas canvas, Size size) {
    // 背景区域分色：上半红、下半黑
    final midY = (plotTop + plotBottom) / 2;
    final redBg = Paint()..color = const Color(0x15C62828);
    final blackBg = Paint()..color = const Color(0x121A1A1A);
    canvas.drawRect(
      Rect.fromLTRB(plotLeft, plotTop, plotRight, midY),
      redBg,
    );
    canvas.drawRect(
      Rect.fromLTRB(plotLeft, midY, plotRight, plotBottom),
      blackBg,
    );

    // 网格线（步长随 yMax 自适应）
    final gridPaint = Paint()
      ..color = const Color(0xFFE0D5B8)
      ..strokeWidth = 0.5;
    final step = yMax <= 100 ? 25 : yMax <= 500 ? 100 : 300;
    for (var v = -yMax.toInt(); v <= yMax.toInt(); v += step) {
      final y = _yOfScore(v);
      canvas.drawLine(
        Offset(plotLeft, y),
        Offset(plotRight, y),
        gridPaint,
      );
    }

    // 中线（0 分）
    final midPaint = Paint()
      ..color = const Color(0xFF8B6B3D)
      ..strokeWidth = 1.2;
    canvas.drawLine(
      Offset(plotLeft, midY),
      Offset(plotRight, midY),
      midPaint,
    );

    // Y 轴标签
    final labelStyle = TextStyle(fontSize: 9, color: const Color(0xFF8B6B3D));
    for (final v in [-yMax.toInt(), 0, yMax.toInt()]) {
      final y = _yOfScore(v);
      final textSpan = TextSpan(
        text: v == 0 ? '0' : (v > 0 ? '+$v' : '$v'),
        style: labelStyle,
      );
      final tp = TextPainter(
        text: textSpan,
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(plotLeft - tp.width - 2, y - tp.height / 2));
    }

    if (evaluations.isEmpty) return;

    // 折线
    final linePaint = Paint()
      ..color = const Color(0xFF5D4423)
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;
    final path = Path();
    for (var i = 0; i < evaluations.length; i++) {
      final x = _xOfIndex(i);
      final y = _yOfScore(evaluations[i].redPerspectiveScore);
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    canvas.drawPath(path, linePaint);

    // 数据点
    for (var i = 0; i < evaluations.length; i++) {
      final x = _xOfIndex(i);
      final y = _yOfScore(evaluations[i].redPerspectiveScore);
      final isRed = evaluations[i].sideToMove == Side.red;
      final paint = Paint()..color = isRed ? const Color(0xFFC62828) : const Color(0xFF1A1A1A);
      canvas.drawCircle(Offset(x, y), i == currentIndex ? 4 : 2, paint);
    }

    // 光标线
    final cursorX = _xOfIndex(currentIndex);
    final cursorPaint = Paint()
      ..color = const Color(0xFF1565C0)
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;
    canvas.drawLine(
      Offset(cursorX, plotTop),
      Offset(cursorX, plotBottom),
      cursorPaint,
    );

    // 光标位置的数据点高亮
    final curY = _yOfScore(evaluations[currentIndex].redPerspectiveScore);
    canvas.drawCircle(
      Offset(cursorX, curY),
      6,
      Paint()..color = const Color(0xFF1565C0),
    );
    canvas.drawCircle(
      Offset(cursorX, curY),
      6,
      Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
  }

  @override
  bool shouldRepaint(covariant _ChartPainter old) =>
      evaluations != old.evaluations ||
      currentIndex != old.currentIndex ||
      yMax != old.yMax;
}
