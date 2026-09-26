import 'package:flutter/material.dart';

import '../../core/constants/board_constants.dart';
import '../../core/theme/app_theme.dart';

/// 棋盘布局计算与网格绘制的通用模块。
///
/// 经典代码棋盘、图片棋盘以及棋盘适配页面共用同一套布局约定：
/// 9 列 × 10 行交叉点，边缘棋子以最外侧交叉点为圆心、向外伸出半个
/// 棋子半径。适配数据只确定「左上 / 右下交叉点」的矩形区域，
/// 其余格子尺寸由该矩形均分得到。
class BoardLayout {
  BoardLayout._();

  /// 棋子直径相对格宽的比例。
  static const double pieceRatio = 0.85;

  /// 棋盘最外侧预留边距（像素）。
  static const double outerMargin = 4.0;

  /// 默认（未适配）布局参数：给定整块棋盘画布尺寸，返回网格边距与
  /// 格子宽高。经典棋盘与适配页面的初始状态都使用它。
  static ({EdgeInsets padding, double cellW, double cellH}) defaultMetrics(
    Size size,
  ) {
    final cellW =
        (size.width - outerMargin * 2) /
            (BoardConstants.columnCount - 1 + pieceRatio);
    final cellH = cellW;
    final pad = cellW * pieceRatio / 2 + outerMargin;
    return (
      padding: EdgeInsets.all(pad),
      cellW: cellW,
      cellH: cellH,
    );
  }

  /// 默认布局下，给定整块棋盘宽度时的画布尺寸（宽高）。
  /// 打谱棋盘与适配页面都按该尺寸显示棋盘图片。
  static Size sizeForWidth(double width) {
    final m = defaultMetrics(Size(width, 0));
    final height =
        m.cellH * (BoardConstants.rowCount - 1) + m.padding.vertical;
    return Size(width, height);
  }

  /// 默认布局下，左上交叉点（0,0）到右下交叉点（8,9）构成的网格矩形。
  static Rect defaultGridRect(Size size) {
    final m = defaultMetrics(size);
    return Rect.fromLTWH(
      m.padding.left,
      m.padding.top,
      m.cellW * (BoardConstants.columnCount - 1),
      m.cellH * (BoardConstants.rowCount - 1),
    );
  }

  /// 由适配矩形反推布局参数（边距 + 格子宽高）。
  static ({EdgeInsets padding, double cellW, double cellH}) metricsFromRect(
    Rect gridRect,
  ) {
    return (
      padding: EdgeInsets.only(left: gridRect.left, top: gridRect.top),
      cellW: gridRect.width / (BoardConstants.columnCount - 1),
      cellH: gridRect.height / (BoardConstants.rowCount - 1),
    );
  }
}

/// 棋盘网格（横线 / 竖线 / 九宫斜线 / 楚河汉界）绘制器。
///
/// 经典棋盘使用 [drawBackground] = true 先铺底色并绘制楚河汉界文字；
/// 适配页面叠加在棋盘图片之上时只画线，不铺底、不画河界文字
/// （图片自身已带）。
class BoardGridPainter extends CustomPainter {
  const BoardGridPainter({
    required this.gridRect,
    this.drawBackground = false,
    this.drawRiverText = true,
    this.strokeColor,
  });

  /// 左上交叉点（0,0）到右下交叉点（8,9）的网格矩形。
  final Rect gridRect;

  /// 是否绘制棋盘底色（经典代码棋盘）。
  final bool drawBackground;

  /// 是否绘制楚河汉界文字（经典棋盘需要；叠加图片时不需要）。
  final bool drawRiverText;

  /// 网格线颜色；默认取主题棋盘线色。
  final Color? strokeColor;

  @override
  void paint(Canvas canvas, Size size) {
    if (drawBackground) {
      canvas.drawRect(
        Offset.zero & size,
        Paint()..color = AppTheme.boardBackground,
      );
    }
    paintGrid(
      canvas,
      gridRect,
      color: strokeColor ?? AppTheme.boardLine,
      drawRiverText: drawRiverText,
    );
  }

  /// 纯静态网格绘制：不依赖 CustomPainter，供适配页面等直接调用。
  static void paintGrid(
    Canvas canvas,
    Rect rect, {
    required Color color,
    bool drawRiverText = true,
  }) {
    final line = Paint()
      ..color = color
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;

    final left = rect.left;
    final top = rect.top;
    final cellW = rect.width / (BoardConstants.columnCount - 1);
    final cellH = rect.height / (BoardConstants.rowCount - 1);
    final cols = BoardConstants.columnCount;
    final rows = BoardConstants.rowCount;

    // 横线 10 条
    for (var r = 0; r < rows; r++) {
      final y = top + r * cellH;
      canvas.drawLine(Offset(left, y), Offset(rect.right, y), line);
    }
    // 竖线 9 条(中间 7 条在楚河处断开)
    for (var c = 0; c < cols; c++) {
      final x = left + c * cellW;
      // 边缘两条贯穿
      if (c == 0 || c == cols - 1) {
        canvas.drawLine(Offset(x, top), Offset(x, rect.bottom), line);
      } else {
        // 上半
        canvas.drawLine(
            Offset(x, top), Offset(x, top + 4 * cellH), line);
        // 下半
        canvas.drawLine(
            Offset(x, top + 5 * cellH), Offset(x, rect.bottom), line);
      }
    }

    // 九宫斜线
    final palaceLine = Paint()
      ..color = color
      ..strokeWidth = 1.2;
    // 黑方九宫
    canvas.drawLine(
      Offset(left + 3 * cellW, top),
      Offset(left + 5 * cellW, top + 2 * cellH),
      palaceLine,
    );
    canvas.drawLine(
      Offset(left + 5 * cellW, top),
      Offset(left + 3 * cellW, top + 2 * cellH),
      palaceLine,
    );
    // 红方九宫
    canvas.drawLine(
      Offset(left + 3 * cellW, top + 7 * cellH),
      Offset(left + 5 * cellW, top + 9 * cellH),
      palaceLine,
    );
    canvas.drawLine(
      Offset(left + 5 * cellW, top + 7 * cellH),
      Offset(left + 3 * cellW, top + 9 * cellH),
      palaceLine,
    );

    // 楚河汉界文字
    if (drawRiverText) {
      final ts = TextSpan(
        text: '楚 河                        汉 界',
        style: TextStyle(color: color, fontSize: cellW * 0.55),
      );
      final tp =
          TextPainter(text: ts, textDirection: TextDirection.ltr)..layout();
      tp.paint(
        canvas,
        Offset(left + cellW, top + 4 * cellH + (cellH - tp.height) / 2),
      );
    }
  }

  @override
  bool shouldRepaint(covariant BoardGridPainter oldDelegate) =>
      oldDelegate.gridRect != gridRect ||
      oldDelegate.drawBackground != drawBackground ||
      oldDelegate.drawRiverText != drawRiverText ||
      oldDelegate.strokeColor != strokeColor;
}
