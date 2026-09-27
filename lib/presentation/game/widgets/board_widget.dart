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
import 'move_anim.dart';
import 'move_arrow_painter.dart';
import 'move_highlight.dart';
import 'piece_widget.dart';

/// 棋盘 widget：绘制网格、九宫、楚河汉界、棋子、选中高亮与合法走法提示，并接收点击。
///
/// 收到新的 [BoardWidget.moveAnim] 事件时（单步前进/后退/用户走子），
/// 在落点上方播放 300ms 的棋子直线移动动画：动画期间隐藏落点格的
/// 真实棋子，由一个随进度插值移动的浮层棋子代替，结束后恢复。
class BoardWidget extends StatefulWidget {
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
    this.moveAnim,
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

  /// 单步走子动画事件；控制器每次产生新事件（对象引用变化）时播放。
  final MoveAnimEvent? moveAnim;

  @override
  State<BoardWidget> createState() => _BoardWidgetState();
}

class _BoardWidgetState extends State<BoardWidget>
    with SingleTickerProviderStateMixin {
  /// 单步走子移动动画（时长与衔接计算共用 [kMoveAnimDuration]）。
  late final AnimationController _anim = AnimationController(
    vsync: this,
    duration: kMoveAnimDuration,
  );

  /// 当前正在播放的动画事件；null 表示无动画。
  MoveAnimEvent? _active;

  @override
  void initState() {
    super.initState();
    _anim.addStatusListener((status) {
      if (status == AnimationStatus.completed && _active != null) {
        // 动画结束：恢复常规绘制（落点棋子重新显示）
        setState(() => _active = null);
      }
    });
  }

  @override
  void didUpdateWidget(covariant BoardWidget old) {
    super.didUpdateWidget(old);
    final ev = widget.moveAnim;
    if (!identical(ev, old.moveAnim)) {
      if (ev != null) {
        // 新的动画事件：从头播放（快速连续操作时直接覆盖上一次）
        _active = ev;
        _anim.forward(from: 0);
      } else if (_active != null) {
        // 控制器清除了动画（跳跃跳转/重开/载入）：立即结束
        _anim.stop();
        _active = null;
      }
    }
  }

  @override
  void dispose() {
    _anim.dispose();
    super.dispose();
  }

  /// 动画期间需要隐藏的落点格：前进时为 to，后退时为 from。
  Position? get _hidePos {
    final a = _active;
    if (a == null) return null;
    return a.forward ? a.to : a.from;
  }

  @override
  Widget build(BuildContext context) {
    final board = widget.board;
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
        // 动画期间隐藏的落点格
        final hidePos = _hidePos;

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
              if (pos != null) widget.onTap(Position(pos.$1, pos.$2));
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
                if (widget.lastMove != null)
                  CustomPaint(
                    size: Size(boardWidth, boardHeight),
                    painter: _LastMovePainter(
                      padding: padding,
                      cellW: cellWidth,
                      cellH: cellHeight,
                      from: widget.lastMove!.$1,
                      to: widget.lastMove!.$2,
                      flipped: flipped,
                    ),
                  ),
                // 3. 棋子（动画期间隐藏落点格的真实棋子，由浮层代替）
                ...board.pieces().where((e) => e.position != hidePos).map(
                      (e) => _positionedPiece(
                        e.position,
                        e.piece,
                        padding,
                        cellWidth,
                        cellHeight,
                        pieceSize,
                      ),
                    ),
                // 2. 选中高亮 + 走法提示
                ..._buildHints(padding, cellWidth, cellHeight, pieceSize),
                // 2.5 提示箭头：在棋子之上绘制，避免被终点棋子盖住
                if (widget.hintArrow != null)
                  CustomPaint(
                    size: Size(boardWidth, boardHeight),
                    painter: MoveArrowPainter(
                      padding: padding,
                      cellW: cellWidth,
                      cellH: cellHeight,
                      flipped: flipped,
                      arrows: [
                        MoveArrow(
                          from: widget.hintArrow!.$1,
                          to: widget.hintArrow!.$2,
                          // 绿色，与分支标记的多色调色板区分
                          color: const Color(0xFF2E7D32),
                        ),
                      ],
                    ),
                  ),
                // 4. 分支标记层：在棋子之上绘制候选分支走法
                if (widget.branchMarkers.isNotEmpty)
                  CustomPaint(
                    size: Size(boardWidth, boardHeight),
                    painter: MoveArrowPainter(
                      padding: padding,
                      cellW: cellWidth,
                      cellH: cellHeight,
                      flipped: flipped,
                      arrows: widget.branchMarkers,
                    ),
                  ),
                // 5. 分析箭头层：PV1 前两步，红方红箭头、黑方黑箭头
                if (widget.analysisArrows.isNotEmpty)
                  CustomPaint(
                    size: Size(boardWidth, boardHeight),
                    painter: MoveArrowPainter(
                      padding: padding,
                      cellW: cellWidth,
                      cellH: cellHeight,
                      flipped: flipped,
                      arrows: widget.analysisArrows,
                    ),
                  ),
                // 6. 走子动画浮层：棋子从视觉起点到视觉终点直线移动，
                //    绘制在最上层保证全程可见
                if (_active != null)
                  AnimatedBuilder(
                    animation: _anim,
                    builder: (context, _) {
                      final a = _active!;
                      // 后退时视觉方向与棋步相反：从 to 滑回 from
                      final visualFrom = a.forward ? a.from : a.to;
                      final visualTo = a.forward ? a.to : a.from;
                      final start = CoordinateUtils.toPixel(
                        col: visualFrom.col,
                        row: visualFrom.row,
                        cellWidth: cellWidth,
                        cellHeight: cellHeight,
                        padding: padding,
                        flipped: flipped,
                      );
                      final end = CoordinateUtils.toPixel(
                        col: visualTo.col,
                        row: visualTo.row,
                        cellWidth: cellWidth,
                        cellHeight: cellHeight,
                        padding: padding,
                        flipped: flipped,
                      );
                      final t =
                          Curves.easeInOut.transform(_anim.value);
                      final c = Offset.lerp(start, end, t)!;
                      return Positioned(
                        left: c.dx - cellWidth / 2,
                        top: c.dy - cellWidth / 2,
                        width: cellWidth,
                        height: cellWidth,
                        child: Center(
                          child: PieceWidget(piece: a.piece, size: pieceSize),
                        ),
                      );
                    },
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
    for (final p in widget.hints) {
      final isCapture = widget.board.pieceAt(p) != null;
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
      selected: p == widget.selected,
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

  bool get flipped => widget.flipped;
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
