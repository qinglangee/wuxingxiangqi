import 'package:flutter/material.dart';

import '../../../core/assets/asset_catalog.dart';
import '../../../core/config/app_config.dart';
import '../../../core/config/config_manager.dart';
import '../../../core/constants/board_constants.dart';
import '../../../core/theme/app_theme.dart';
import '../../../domain/models/board.dart' as m;
import '../../../domain/models/piece.dart';
import '../../../domain/models/position.dart';
import '../../../utils/coordinate_utils.dart';
import 'move_arrow_painter.dart';
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
    this.lastMove,
    this.hintArrow,
  });

  /// [hints] 是当前选中棋子的合法终点集合。
  final m.Board board;
  final Position? selected;
  final Set<Position> hints;
  final void Function(Position pos) onTap;

  /// 分支标记：到达分支点时，可视化各候选分支的走法（带序号箭头）。
  final List<MoveArrow> branchMarkers;

  /// 上一步走法的起点与终点；null 表示当前局面无前序走法（开局/根节点）。
  final (Position from, Position to)? lastMove;

  /// 提示箭头（引擎 bestmove 的起点与终点）；null 表示无提示。
  final (Position, Position)? hintArrow;

  @override
  Widget build(BuildContext context) {
    // 监听配置变化：设置页切换棋盘/棋子样式后，整个棋盘子树立即刷新。
    return ListenableBuilder(
      listenable: ConfigManager.instance,
      builder: (context, _) => LayoutBuilder(
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

        final boardCfg = ConfigManager.instance.config.board;
        final useImageBoard =
            boardCfg.boardType == BoardConfig.kTypeImage &&
                boardCfg.boardStyle.isNotEmpty;

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
                // 1. 棋盘背景与网格：图片棋盘整幅铺满，否则代码绘制
                if (useImageBoard)
                  Positioned.fill(
                    child: Image.asset(
                      AssetCatalog.boardAsset(boardCfg.boardStyle),
                      fit: BoxFit.fill,
                    ),
                  )
                else
                  CustomPaint(
                    size: Size(boardWidth, boardHeight),
                    painter: _BoardPainter(padding: padding, cellW: cellWidth, cellH: cellHeight),
                  ),
                // 1.5 上一步走法标注：起点与终点各画一个高亮圈。
                // 绘制在棋子之下，终点处的棋子会盖住填充，外圈描边仍可见。
                if (lastMove != null)
                  CustomPaint(
                    size: Size(boardWidth, boardHeight),
                    painter: _LastMovePainter(
                      padding: padding,
                      cellW: cellWidth,
                      cellH: cellHeight,
                      from: lastMove!.$1,
                      to: lastMove!.$2,
                    ),
                  ),
                // 1.6 提示箭头：在引擎 bestmove 的起点与终点之间画绿色箭头
                if (hintArrow != null)
                  CustomPaint(
                    size: Size(boardWidth, boardHeight),
                    painter: MoveArrowPainter(
                      padding: padding,
                      cellW: cellWidth,
                      cellH: cellHeight,
                      arrows: [
                        MoveArrow(
                          from: hintArrow!.$1,
                          to: hintArrow!.$2,
                          // 绿色，与分支标记的多色调色板区分
                          color: const Color(0xFF2E7D32),
                        ),
                      ],
                    ),
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
                    painter: MoveArrowPainter(
                      padding: padding,
                      cellW: cellWidth,
                      cellH: cellHeight,
                      arrows: branchMarkers,
                    ),
                  ),
              ],
            ),
          ),
        );
      },
      ),
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

/// 上一步走法标注绘制器：在起点与终点各画一个高亮圈。
///
/// 绘制层位于棋子之下：起点处（已空）显示半透明填充 + 描边圆；
/// 终点处填充被棋子盖住，外圈描边环绕棋子边缘可见。
class _LastMovePainter extends CustomPainter {
  const _LastMovePainter({
    required this.padding,
    required this.cellW,
    required this.cellH,
    required this.from,
    required this.to,
  });

  final EdgeInsets padding;
  final double cellW;
  final double cellH;
  final Position from;
  final Position to;

  static const _color = Color(0xFF1565C0); // 蓝，与分支标记色板区分度好

  @override
  void paint(Canvas canvas, Size size) {
    // 棋子半径 cellW * 0.425；描边圈略大一圈，保证终点处环绕棋子可见
    final fillRadius = cellW * 0.425;
    final ringRadius = fillRadius + cellW * 0.06;
    final fillPaint = Paint()..color = _color.withValues(alpha: 0.22);
    final ringPaint = Paint()
      ..color = _color.withValues(alpha: 0.85)
      ..style = PaintingStyle.stroke
      ..strokeWidth = cellW * 0.045;

    // 起点：小圆点标记（格子已空，小标记足够指示来源）
    final fromCenter = CoordinateUtils.toPixel(
      col: from.col,
      row: from.row,
      cellWidth: cellW,
      cellHeight: cellH,
      padding: padding,
    );
    canvas.drawCircle(
        fromCenter, cellW * 0.2, Paint()..color = _color.withValues(alpha: 0.55));
    canvas.drawCircle(fromCenter, cellW * 0.3, ringPaint);

    // 终点：整圈高亮（棋子盖住填充，外圈描边环绕棋子边缘）
    final toCenter = CoordinateUtils.toPixel(
      col: to.col,
      row: to.row,
      cellWidth: cellW,
      cellHeight: cellH,
      padding: padding,
    );
    canvas.drawCircle(toCenter, fillRadius, fillPaint);
    canvas.drawCircle(toCenter, ringRadius, ringPaint);
  }

  @override
  bool shouldRepaint(covariant _LastMovePainter oldDelegate) =>
      oldDelegate.padding != padding ||
      oldDelegate.cellW != cellW ||
      oldDelegate.cellH != cellH ||
      oldDelegate.from != from ||
      oldDelegate.to != to;
}

