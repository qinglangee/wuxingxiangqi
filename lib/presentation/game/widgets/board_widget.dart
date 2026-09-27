import 'package:flutter/material.dart';

import '../../../core/assets/asset_catalog.dart';
import '../../../core/config/app_config.dart';
import '../../../core/config/board_calibration_store.dart';
import '../../../core/config/config_manager.dart';
import '../../../core/constants/board_constants.dart';
import '../../../domain/models/board.dart' as m;
import '../../../domain/models/piece.dart';
import '../../../domain/models/position.dart';
import '../../../presentation/shared/board_grid_painter.dart';
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
    this.analysisArrows = const [],
    this.lastMove,
    this.hintArrow,
    this.flipped = false,
  });

  /// [hints] 是当前选中棋子的合法终点集合。
  final m.Board board;
  final Position? selected;
  final Set<Position> hints;
  final void Function(Position pos) onTap;

  /// 分支标记：到达分支点时，可视化各候选分支的走法（带序号箭头）。
  final List<MoveArrow> branchMarkers;

  /// 无限分析时 PV1 前两步的指示箭头（红/黑着色，无序号）。
  final List<MoveArrow> analysisArrows;

  /// 上一步走法的起点与终点；null 表示当前局面无前序走法（开局/根节点）。
  final (Position from, Position to)? lastMove;

  /// 提示箭头（引擎 bestmove 的起点与终点）；null 表示无提示。
  final (Position, Position)? hintArrow;

  /// 棋盘是否翻转（红黑上下互换）。
  final bool flipped;

  @override
  Widget build(BuildContext context) {
    // 监听配置变化：设置页切换棋盘/棋子样式、修改棋盘适配后，
    // 整个棋盘子树立即刷新。
    return ListenableBuilder(
      listenable: Listenable.merge([
        ConfigManager.instance,
        BoardCalibrationStore.instance,
      ]),
      builder: (context, _) => LayoutBuilder(
      builder: (context, constraints) {
        final boardWidth = constraints.maxWidth;
        final boardSize = BoardLayout.sizeForWidth(boardWidth);
        final boardHeight = boardSize.height;

        final boardCfg = ConfigManager.instance.config.board;
        final useImageBoard =
            boardCfg.boardType == BoardConfig.kTypeImage &&
                boardCfg.boardStyle.isNotEmpty;

        // 默认（经典棋盘/未适配的图片棋盘）使用统一的标准布局；
        // 已适配的图片棋盘按用户对齐的左上/右下交叉点反推格距。
        var metrics = BoardLayout.defaultMetrics(boardSize);
        if (useImageBoard) {
          final cal =
              BoardCalibrationStore.instance.get(boardCfg.boardStyle);
          if (cal != null) {
            metrics = BoardLayout.metricsFromRect(Rect.fromLTRB(
              cal.left * boardSize.width,
              cal.top * boardSize.height,
              cal.right * boardSize.width,
              cal.bottom * boardSize.height,
            ));
          }
        }
        final cellWidth = metrics.cellW;
        final cellHeight = metrics.cellH;
        final padding = metrics.padding;
        // 棋子大小 = 格宽 × 占格比例 × 用户设置的大小缩放（0.2-2.0）
        final pieceSize = cellWidth *
            BoardLayout.pieceRatio *
            boardCfg.pieceSizeScale;

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
                flipped: flipped,
              );
              if (pos != null) onTap(Position(pos.$1, pos.$2));
            },
            child: Stack(
              children: [
                // 1. 棋盘背景与网格：图片棋盘整幅铺满，否则代码绘制
                if (useImageBoard)
                  Positioned.fill(
                    // 翻转时把整幅棋盘图旋转 180°（网格本身中心对称）
                    child: Transform(
                      alignment: Alignment.center,
                      transform: flipped
                          ? (Matrix4.identity()..rotateZ(3.1415926535897932))
                          : Matrix4.identity(),
                      child: Image.asset(
                        AssetCatalog.boardAsset(boardCfg.boardStyle),
                        fit: BoxFit.fill,
                      ),
                    ),
                  )
                else
                  CustomPaint(
                    size: Size(boardWidth, boardHeight),
                    painter: BoardGridPainter(
                      gridRect: Rect.fromLTWH(
                        padding.left,
                        padding.top,
                        cellWidth * (BoardConstants.columnCount - 1),
                        cellHeight * (BoardConstants.rowCount - 1),
                      ),
                      drawBackground: true,
                    ),
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
                      flipped: flipped,
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
                // 2.5 提示箭头：在棋子之上绘制，避免被终点棋子盖住
                if (hintArrow != null)
                  CustomPaint(
                    size: Size(boardWidth, boardHeight),
                    painter: MoveArrowPainter(
                      padding: padding,
                      cellW: cellWidth,
                      cellH: cellHeight,
                      flipped: flipped,
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
                // 4. 分支标记层：在棋子之上绘制候选分支走法
                if (branchMarkers.isNotEmpty)
                  CustomPaint(
                    size: Size(boardWidth, boardHeight),
                    painter: MoveArrowPainter(
                      padding: padding,
                      cellW: cellWidth,
                      cellH: cellHeight,
                      flipped: flipped,
                      arrows: branchMarkers,
                    ),
                  ),
                // 5. 分析箭头层：PV1 前两步，红方红箭头、黑方黑箭头
                if (analysisArrows.isNotEmpty)
                  CustomPaint(
                    size: Size(boardWidth, boardHeight),
                    painter: MoveArrowPainter(
                      padding: padding,
                      cellW: cellWidth,
                      cellH: cellHeight,
                      flipped: flipped,
                      arrows: analysisArrows,
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
      flipped: flipped,
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
    this.flipped = false,
  });

  final EdgeInsets padding;
  final double cellW;
  final double cellH;
  final Position from;
  final Position to;
  final bool flipped;

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
      flipped: flipped,
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
      flipped: flipped,
    );
    canvas.drawCircle(toCenter, fillRadius, fillPaint);
    canvas.drawCircle(toCenter, ringRadius, ringPaint);
  }

  @override
  bool shouldRepaint(covariant _LastMovePainter oldDelegate) =>
      oldDelegate.padding != padding ||
      oldDelegate.cellW != cellW ||
      oldDelegate.cellH != cellH ||
      oldDelegate.flipped != flipped ||
      oldDelegate.from != from ||
      oldDelegate.to != to;
}

