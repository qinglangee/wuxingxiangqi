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

  /// 显示在箭尾的序号文字（如分支序号字母 A-Z）；null 表示不显示圆点。
  final String? label;
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
      String label, double fontSize) {
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
        text: label,
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

  /// 命中测试：判断点击点 [point] 是否落在某支箭头上（序号圆点、三角
  /// 箭头或连线），返回命中箭头在 [arrows] 中的下标；都未命中返回 null。
  ///
  /// 按绘制顺序逆序检测，保证重叠时最上层的箭头优先。触摸热区比实际
  /// 绘制图形略大（圆点/连线较细，方便手指点击）。
  static int? hitTestArrow({
    required Offset point,
    required List<MoveArrow> arrows,
    required EdgeInsets padding,
    required double cellW,
    required double cellH,
    required bool flipped,
  }) {
    if (arrows.isEmpty) return null;
    final dotRadius = cellW * 0.18;
    // 半个棋子宽度（piece size = cellW * 0.85）
    final halfPiece = cellW * 0.425;
    // 箭头尺寸
    final arrowLen = cellW * 0.28;
    // 触摸热区：圆点与箭头尖端取不小于棋子半径三分之一的舒适范围
    final dotHit = math.max(dotRadius + 2, cellW * 0.27);
    final headHit = cellW * 0.24;
    final lineHit = math.max(cellW * 0.10 / 2, cellW * 0.15);

    Offset centerOf(Position p) => CoordinateUtils.toPixel(
          col: p.col,
          row: p.row,
          cellWidth: cellW,
          cellHeight: cellH,
          padding: padding,
          flipped: flipped,
        );

    for (var i = arrows.length - 1; i >= 0; i--) {
      final a = arrows[i];
      final from = centerOf(a.from);
      final to = centerOf(a.to);
      final dx = to.dx - from.dx;
      final dy = to.dy - from.dy;
      final len = math.sqrt(dx * dx + dy * dy);
      if (len == 0) continue;
      final ux = dx / len;
      final uy = dy / len;
      // 与方向垂直的向量
      final px = -uy;
      final py = ux;

      // 1. 序号圆点（终点之外半个棋子宽度处）
      if (a.label != null) {
        final dotCenter = Offset(
          to.dx - ux * halfPiece,
          to.dy - uy * halfPiece,
        );
        if ((point - dotCenter).distance <= dotHit) return i;
      }

      // 2. 终点三角箭头：尖端圆形热区 + 三角形内部
      final tip = to;
      final baseCenter = Offset(
        to.dx - ux * arrowLen,
        to.dy - uy * arrowLen,
      );
      final base1 = Offset(
        baseCenter.dx + px * arrowLen * 0.5,
        baseCenter.dy + py * arrowLen * 0.5,
      );
      final base2 = Offset(
        baseCenter.dx - px * arrowLen * 0.5,
        baseCenter.dy - py * arrowLen * 0.5,
      );
      if ((point - tip).distance <= headHit ||
          _pointInTriangle(point, tip, base1, base2)) {
        return i;
      }

      // 3. 半透明连线（终点缩进半个箭头长度）
      final lineEnd = Offset(
        to.dx - ux * arrowLen * 0.5,
        to.dy - uy * arrowLen * 0.5,
      );
      if (_distanceToSegment(point, from, lineEnd) <= lineHit) return i;
    }
    return null;
  }

  /// 点到线段 [a]-[b] 的最短距离。
  static double _distanceToSegment(Offset p, Offset a, Offset b) {
    final abx = b.dx - a.dx;
    final aby = b.dy - a.dy;
    final apx = p.dx - a.dx;
    final apy = p.dy - a.dy;
    final ab2 = abx * abx + aby * aby;
    var t = ab2 == 0 ? 0.0 : (apx * abx + apy * aby) / ab2;
    t = t.clamp(0.0, 1.0);
    final closest = Offset(a.dx + abx * t, a.dy + aby * t);
    return (p - closest).distance;
  }

  /// 点 [p] 是否在三角形 (v1, v2, v3) 内部（含边界）。
  static bool _pointInTriangle(
      Offset p, Offset v1, Offset v2, Offset v3) {
    double sign(Offset a, Offset b, Offset c) =>
        (a.dx - c.dx) * (b.dy - c.dy) -
        (b.dx - c.dx) * (a.dy - c.dy);
    final d1 = sign(p, v1, v2);
    final d2 = sign(p, v2, v3);
    final d3 = sign(p, v3, v1);
    final hasNeg = d1 < 0 || d2 < 0 || d3 < 0;
    final hasPos = d1 > 0 || d2 > 0 || d3 > 0;
    return !(hasNeg && hasPos);
  }

  @override
  bool shouldRepaint(covariant MoveArrowPainter oldDelegate) =>
      oldDelegate.padding != padding ||
      oldDelegate.cellW != cellW ||
      oldDelegate.cellH != cellH ||
      oldDelegate.flipped != flipped ||
      oldDelegate.arrows != arrows;
}
