import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../domain/models/position.dart';
import '../../../utils/coordinate_utils.dart';

/// 一条棋盘箭头标注：起点 [from] → 终点 [to] 的可视化。
///
/// 通用数据模型，供 [MoveArrowPainter] 绘制；不同场景（分支标记、
/// 残局提示等）各自传入颜色与可选序号。
class MoveArrow {
  const MoveArrow({
    required this.from,
    required this.to,
    required this.color,
    this.label,
  });

  /// 走法（箭头）起点。
  final Position from;

  /// 走法（箭头）终点。
  final Position to;

  /// 箭头颜色（连线半透明同色）。
  final Color color;

  /// 显示在箭尾的数字（如分支序号，1-based）；null 表示不显示圆点。
  final int? label;
}

/// 通用棋盘箭头绘制器：在起点与终点之间画半透明连线，终点绘制指向
/// 走法方向的三角形箭头；[MoveArrow.label] 非 null 时在终点之外半个
/// 棋子宽度处绘制带数字的圆点。
///
/// 使用场景：
/// - 分支标记：分支点的多条候选续着各画一支带序号箭头；
/// - 残局提示：引擎 bestmove 的 from→to 画单支提示箭头。
class MoveArrowPainter extends CustomPainter {
  const MoveArrowPainter({
    required this.padding,
    required this.cellW,
    required this.cellH,
    required this.arrows,
    this.flipped = false,
  });

  final EdgeInsets padding;
  final double cellW;
  final double cellH;
  final List<MoveArrow> arrows;

  /// 棋盘是否翻转（红黑上下互换）。
  final bool flipped;

  /// 多条并列箭头（分支标记等）使用的调色板，按序循环取色。
  static const List<Color> palette = [
    Color(0xFFC62828), // 红
    Color(0xFF1565C0), // 蓝
    Color(0xFF2E7D32), // 绿
    Color(0xFF6A1B9A), // 紫
    Color(0xFFEF6C00), // 橙
    Color(0xFF00838F), // 青
    Color(0xFFAD1457), // 玫红
    Color(0xFF5D4037), // 棕
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final dotRadius = cellW * 0.18;
    final fontSize = cellW * 0.26;
    // 半个棋子宽度（piece size = cellW * 0.85）
    final halfPiece = cellW * 0.425;
    // 箭头尺寸
    final arrowLen = cellW * 0.28;

    for (final a in arrows) {
      final color = a.color;

      final fromCenter = CoordinateUtils.toPixel(
        col: a.from.col,
        row: a.from.row,
        cellWidth: cellW,
        cellHeight: cellH,
        padding: padding,
        flipped: flipped,
      );
      final toCenter = CoordinateUtils.toPixel(
        col: a.to.col,
        row: a.to.row,
        cellWidth: cellW,
        cellHeight: cellH,
        padding: padding,
        flipped: flipped,
      );

      // 走法方向单位向量
      final dx = toCenter.dx - fromCenter.dx;
      final dy = toCenter.dy - fromCenter.dy;
      final len = math.sqrt(dx * dx + dy * dy);
      final ux = len > 0 ? dx / len : 0.0;
      final uy = len > 0 ? dy / len : 0.0;

      // 半透明连线（终点稍微缩进，留出箭头位置）
      final lineEnd = Offset(
        toCenter.dx - ux * arrowLen * 0.5,
        toCenter.dy - uy * arrowLen * 0.5,
      );
      final linePaint = Paint()
        ..color = color.withValues(alpha: 0.55)
        ..strokeWidth = cellW * 0.10
        ..strokeCap = StrokeCap.round;
      canvas.drawLine(fromCenter, lineEnd, linePaint);

      // 终点箭头（三角形，尖端在 toCenter 处，指向走法方向）
      final tip = toCenter;
      final baseCenter = Offset(
        toCenter.dx - ux * arrowLen,
        toCenter.dy - uy * arrowLen,
      );
      // 与方向垂直的基线
      final px = -uy;
      final py = ux;
      final base1 = Offset(
        baseCenter.dx + px * arrowLen * 0.5,
        baseCenter.dy + py * arrowLen * 0.5,
      );
      final base2 = Offset(
        baseCenter.dx - px * arrowLen * 0.5,
        baseCenter.dy - py * arrowLen * 0.5,
      );
      final arrowPath = Path()
        ..moveTo(tip.dx, tip.dy)
        ..lineTo(base1.dx, base1.dy)
        ..lineTo(base2.dx, base2.dy)
        ..close();
      canvas.drawPath(arrowPath, Paint()..color = color);

      // 序号圆点：在终点之外半个棋子宽度处，沿走法方向偏移
      if (a.label != null) {
        final numberCenter = Offset(
          toCenter.dx - ux * halfPiece,
          toCenter.dy - uy * halfPiece,
        );
        _drawDot(canvas, numberCenter, dotRadius, color, a.label!, fontSize);
      }
    }
  }

  void _drawDot(Canvas canvas, Offset center, double radius, Color color,
      int label, double fontSize) {
    // 白色描边底
    canvas.drawCircle(
      center,
      radius + 2,
      Paint()..color = Colors.white,
    );
    // 彩色填充
    canvas.drawCircle(center, radius, Paint()..color = color);

    final tp = TextPainter(
      text: TextSpan(
        text: '$label',
        style: TextStyle(
          color: Colors.white,
          fontSize: fontSize,
          fontWeight: FontWeight.bold,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(
      canvas,
      Offset(center.dx - tp.width / 2, center.dy - tp.height / 2),
    );
  }

  @override
  bool shouldRepaint(covariant MoveArrowPainter oldDelegate) =>
      oldDelegate.padding != padding ||
      oldDelegate.cellW != cellW ||
      oldDelegate.cellH != cellH ||
      oldDelegate.flipped != flipped ||
      oldDelegate.arrows != arrows;
}
