import 'package:flutter/material.dart';

import '../../../core/constants/board_constants.dart';
import '../../../core/theme/app_theme.dart';
import '../../../domain/models/board.dart' as m;
import '../../../domain/models/piece.dart';
import '../../../domain/models/position.dart';
import '../../../utils/coordinate_utils.dart';
import 'branch_marker.dart';
import 'move_highlight.dart';
import 'piece_widget.dart';

/// 棋盘 widget：绘制网格、九宫、楚河汉界、棋子、选中高亮与合法走法提示，并接收点击。
class BoardWidget extends StatelessWidget {
  const BoardWidget({
    super.key,
    required this.board,
    required this.selected,
    required this.hints,
    required this.onTap,
    this.branchMarkers = const [],
  });

  /// [hints] 是当前选中棋子的合法终点集合。
  final m.Board board;
  final Position? selected;
  final Set<Position> hints;
  final void Function(Position pos) onTap;

  /// 分支标记：到达分支点时，可视化各候选分支的走法。
  final List<BranchMarker> branchMarkers;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final boardWidth = constraints.maxWidth;
        // 棋盘 9×10。边缘棋子以最外侧交叉点为圆心，向外伸出 pieceSize/2，
        // 因此边距按棋子半径动态计算，保证棋子完整显示。
        const pieceRatio = 0.85;
        const outerMargin = 4.0;
        final cellWidth = (boardWidth - outerMargin * 2) /
            (BoardConstants.columnCount - 1 + pieceRatio);
        final cellHeight = cellWidth; // 方格接近正方形
        final pad = cellWidth * pieceRatio / 2 + outerMargin;
        final boardHeight = cellHeight * (BoardConstants.rowCount - 1) + pad * 2;
        final pieceSize = cellWidth * pieceRatio;
        final padding = EdgeInsets.all(pad);

        return SizedBox(
          width: boardWidth,
          height: boardHeight,
          child: GestureDetector(
            onTapDown: (details) {
              final pos = CoordinateUtils.fromPixel(
                x: details.localPosition.dx,
                y: details.localPosition.dy,
                cellWidth: cellWidth,
                cellHeight: cellHeight,
                padding: padding,
              );
              if (pos != null) onTap(Position(pos.$1, pos.$2));
            },
            child: Stack(
              children: [
                // 1. 棋盘背景与网格
                CustomPaint(
                  size: Size(boardWidth, boardHeight),
                  painter: _BoardPainter(padding: padding, cellW: cellWidth, cellH: cellHeight),
                ),
                // 3. 棋子
                ...board.pieces().map((e) => _positionedPiece(
                      e.position,
                      e.piece,
                      padding,
                      cellWidth,
                      cellHeight,
                      pieceSize,
                    )),
                // 2. 选中高亮 + 走法提示
                ..._buildHints(padding, cellWidth, cellHeight, pieceSize),
                // 4. 分支标记层：在棋子之上绘制候选分支走法
                if (branchMarkers.isNotEmpty)
                  CustomPaint(
                    size: Size(boardWidth, boardHeight),
                    painter: _BranchMarkerPainter(
                      padding: padding,
                      cellW: cellWidth,
                      cellH: cellHeight,
                      markers: branchMarkers,
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  List<Widget> _buildHints(
      EdgeInsets padding, double cw, double ch, double pieceSize) {
    final widgets = <Widget>[];
    for (final p in hints) {
      final isCapture = board.pieceAt(p) != null;
      widgets.add(_positioned(
        p,
        padding,
        cw,
        ch,
        MoveHighlight(size: pieceSize, isCapture: isCapture),
      ));
    }
    return widgets;
  }

  Widget _positionedPiece(Position p, Piece piece, EdgeInsets pad,
      double cw, double ch, double size) {
    return _positioned(p, pad, cw, ch, PieceWidget(
      piece: piece,
      size: size,
      selected: p == selected,
    ));
  }

  Widget _positioned(Position p, EdgeInsets pad, double cw, double ch, Widget child) {
    final center = CoordinateUtils.toPixel(
      col: p.col,
      row: p.row,
      cellWidth: cw,
      cellHeight: ch,
      padding: pad,
    );
    return Positioned(
      left: center.dx - cw / 2,
      top: center.dy - cw / 2,
      width: cw,
      height: cw,
      child: Center(child: child),
    );
  }
}

class _BoardPainter extends CustomPainter {
  const _BoardPainter({
    required this.padding,
    required this.cellW,
    required this.cellH,
  });

  final EdgeInsets padding;
  final double cellW;
  final double cellH;

  @override
  void paint(Canvas canvas, Size size) {
    final line = Paint()
      ..color = AppTheme.boardLine
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;

    final bg = Paint()..color = AppTheme.boardBackground;
    canvas.drawRect(Offset.zero & size, bg);

    final left = padding.left;
    final top = padding.top;
    final cols = BoardConstants.columnCount;
    final rows = BoardConstants.rowCount;

    // 横线 10 条
    for (var r = 0; r < rows; r++) {
      final y = top + r * cellH;
      canvas.drawLine(Offset(left, y), Offset(left + (cols - 1) * cellW, y), line);
    }
    // 竖线 9 条(中间 7 条在楚河处断开)
    for (var c = 0; c < cols; c++) {
      final x = left + c * cellW;
      // 边缘两条贯穿
      if (c == 0 || c == cols - 1) {
        canvas.drawLine(Offset(x, top), Offset(x, top + (rows - 1) * cellH), line);
      } else {
        // 上半
        canvas.drawLine(Offset(x, top),
            Offset(x, top + 4 * cellH), line);
        // 下半
        canvas.drawLine(Offset(x, top + 5 * cellH),
            Offset(x, top + 9 * cellH), line);
      }
    }

    // 九宫斜线
    final palaceLine = Paint()
      ..color = AppTheme.boardLine
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
    final ts = TextSpan(
      text: '楚 河                        汉 界',
      style: TextStyle(color: AppTheme.boardLine, fontSize: cellW * 0.55),
    );
    final tp = TextPainter(text: ts, textDirection: TextDirection.ltr)
      ..layout();
    tp.paint(
      canvas,
      Offset(left + cellW, top + 4 * cellH + (cellH - tp.height) / 2),
    );
  }

  @override
  bool shouldRepaint(covariant _BoardPainter oldDelegate) =>
      oldDelegate.padding != padding ||
      oldDelegate.cellW != cellW ||
      oldDelegate.cellH != cellH;
}

/// 分支标记绘制器：在棋盘上为每条候选分支画 from→to 连线，
/// 并在两端绘制带数字的小圆点。
class _BranchMarkerPainter extends CustomPainter {
  const _BranchMarkerPainter({
    required this.padding,
    required this.cellW,
    required this.cellH,
    required this.markers,
  });

  final EdgeInsets padding;
  final double cellW;
  final double cellH;
  final List<BranchMarker> markers;

  @override
  void paint(Canvas canvas, Size size) {
    // 不同分支用不同颜色，便于区分
    const colors = [
      Color(0xFFC62828), // 红
      Color(0xFF1565C0), // 蓝
      Color(0xFF2E7D32), // 绿
      Color(0xFF6A1B9A), // 紫
      Color(0xFFEF6C00), // 橙
      Color(0xFF00838F), // 青
      Color(0xFFAD1457), // 玫红
      Color(0xFF5D4037), // 棕
    ];

    final dotRadius = cellW * 0.22;
    final fontSize = cellW * 0.32;

    for (var i = 0; i < markers.length; i++) {
      final m = markers[i];
      final color = colors[i % colors.length];

      final fromCenter = CoordinateUtils.toPixel(
        col: m.from.col,
        row: m.from.row,
        cellWidth: cellW,
        cellHeight: cellH,
        padding: padding,
      );
      final toCenter = CoordinateUtils.toPixel(
        col: m.to.col,
        row: m.to.row,
        cellWidth: cellW,
        cellHeight: cellH,
        padding: padding,
      );

      // 半透明连线
      final linePaint = Paint()
        ..color = color.withValues(alpha: 0.55)
        ..strokeWidth = cellW * 0.10
        ..strokeCap = StrokeCap.round;
      canvas.drawLine(fromCenter, toCenter, linePaint);

      // 端点圆点 + 数字
      _drawDot(canvas, fromCenter, dotRadius, color, m.label, fontSize);
      _drawDot(canvas, toCenter, dotRadius, color, m.label, fontSize);
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
  bool shouldRepaint(covariant _BranchMarkerPainter oldDelegate) =>
      oldDelegate.padding != padding ||
      oldDelegate.cellW != cellW ||
      oldDelegate.cellH != cellH ||
      oldDelegate.markers != markers;
}
