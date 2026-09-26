import 'package:flutter/material.dart';

import '../../core/assets/asset_catalog.dart';
import '../../core/config/board_calibration_store.dart';
import '../shared/board_grid_painter.dart';

/// 棋盘适配页面：像打谱页面一样铺满显示棋盘图片，上方叠加默认棋盘
/// 线格；用户拖动左上角 / 右下角的扇形手柄，使线格与图片上的格子
/// 对齐。松手即把适配参数（按比例）保存到独立配置文件。
class BoardCalibrationScreen extends StatefulWidget {
  const BoardCalibrationScreen({
    super.key,
    required this.boardFileName,
    required this.boardDisplayName,
  });

  /// 棋盘图片文件名（assets/images/boards/ 下），同时是配置键。
  final String boardFileName;

  /// 页面标题中显示的棋盘名称。
  final String boardDisplayName;

  @override
  State<BoardCalibrationScreen> createState() => _BoardCalibrationScreenState();
}

class _BoardCalibrationScreenState extends State<BoardCalibrationScreen> {
  /// 当前网格矩形（左上 / 右下交叉点），像素坐标。
  Rect? _grid;

  /// 已完成初始化所用的画布尺寸（尺寸变化时按比例换算）。
  Size _canvas = Size.zero;

  /// 正在拖动的手柄：0=左上角，1=右下角，null=未拖动。
  int? _dragging;

  /// 本次拖动起始时的手指位置与角点位置（用于按 1/3 速度跟随）。
  Offset _dragStartPointer = Offset.zero;
  Offset _dragStartCorner = Offset.zero;

  /// 手柄命中半径（等于扇形半径）。
  double get _hitRadius => _fanRadius;

  /// 扇形手柄半径：棋盘宽度的一半。
  double get _fanRadius => _canvas.width / 2;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('棋盘适配 · ${widget.boardDisplayName}'),
        actions: [
          IconButton(
            tooltip: '恢复默认',
            icon: const Icon(Icons.restart_alt),
            onPressed: _reset,
          ),
        ],
      ),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final width = constraints.maxWidth;
            final size = BoardLayout.sizeForWidth(width);
            _ensureInitialized(size);
            final grid = _grid!;
            return SingleChildScrollView(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Column(
                children: [
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                    child: Text(
                      '拖动左上角和右下角的扇形区域，让红色线格与棋盘图片上的格子对齐，'
                      '松手自动保存。',
                      style: TextStyle(fontSize: 12.5, color: Color(0xFF8B6B4A), height: 1.45),
                    ),
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    width: size.width,
                    height: size.height,
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onPanDown: (d) => _beginDrag(d.localPosition),
                      onPanUpdate: (d) => _updateDrag(d.localPosition),
                      onPanEnd: (_) => _endDrag(),
                      onPanCancel: _endDrag,
                      child: Stack(
                        children: [
                          // 1. 棋盘图片：与打谱页面一致地铺满
                          Positioned.fill(
                            child: Image.asset(
                              AssetCatalog.boardAsset(widget.boardFileName),
                              fit: BoxFit.fill,
                              errorBuilder: (_, _, _) => const ColoredBox(
                                color: Color(0xFFE8C988),
                                child: Center(
                                  child: Icon(Icons.broken_image,
                                      size: 40, color: Color(0xFF8B6B3D)),
                                ),
                              ),
                            ),
                          ),
                          // 2. 叠加线格（只画线，不铺底、不画河界文字）
                          Positioned.fill(
                            child: CustomPaint(
                              painter: BoardGridPainter(
                                gridRect: grid,
                                drawBackground: false,
                                drawRiverText: false,
                                strokeColor: const Color(0xFFD32F2F),
                              ),
                            ),
                          ),
                          // 3. 左上 / 右下扇形拖动手柄
                          Positioned.fill(
                            child: CustomPaint(
                              painter: _HandlePainter(
                                topLeft: grid.topLeft,
                                bottomRight: grid.bottomRight,
                                fanRadius: _fanRadius,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  /// 首次拿到画布尺寸时：优先使用已保存的适配参数（按比例换算为像素），
  /// 否则使用默认网格。
  void _ensureInitialized(Size size) {
    if (_grid != null && _canvas == size) return;
    final saved = BoardCalibrationStore.instance.get(widget.boardFileName);
    if (saved != null) {
      _grid = Rect.fromLTRB(
        saved.left * size.width,
        saved.top * size.height,
        saved.right * size.width,
        saved.bottom * size.height,
      );
    } else if (_grid == null) {
      _grid = BoardLayout.defaultGridRect(size);
    } else if (_canvas != Size.zero) {
      // 画布尺寸变化（旋转屏等）：按原比例缩放到新尺寸
      _grid = Rect.fromLTRB(
        _grid!.left / _canvas.width * size.width,
        _grid!.top / _canvas.height * size.height,
        _grid!.right / _canvas.width * size.width,
        _grid!.bottom / _canvas.height * size.height,
      );
    }
    _canvas = size;
  }

  void _beginDrag(Offset p) {
    final grid = _grid!;
    final dTL = (p - grid.topLeft).distance;
    final dBR = (p - grid.bottomRight).distance;
    if (dTL <= _hitRadius || dBR <= _hitRadius) {
      _dragging = dTL <= dBR ? 0 : 1;
      _dragStartPointer = p;
      _dragStartCorner = _dragging == 0 ? grid.topLeft : grid.bottomRight;
    }
  }

  void _updateDrag(Offset p) {
    if (_dragging == null) return;
    final size = _canvas;
    // 保证网格至少容得下 8×9 个最小格子
    final minCell = 8.0;
    // 角点按手指移动量的 1/3 速度跟随，便于精细对齐
    final moved = (p - _dragStartPointer) / 3;
    final target = _dragStartCorner + moved;
    setState(() {
      final g = _grid!;
      if (_dragging == 0) {
        _grid = Rect.fromLTRB(
          target.dx.clamp(0.0, g.right - minCell * 8),
          target.dy.clamp(0.0, g.bottom - minCell * 9),
          g.right,
          g.bottom,
        );
      } else {
        _grid = Rect.fromLTRB(
          g.left,
          g.top,
          target.dx.clamp(g.left + minCell * 8, size.width),
          target.dy.clamp(g.top + minCell * 9, size.height),
        );
      }
    });
  }

  void _endDrag() {
    if (_dragging == null) return;
    _dragging = null;
    _save();
  }

  void _save() {
    final grid = _grid;
    final size = _canvas;
    if (grid == null || size.isEmpty) return;
    BoardCalibrationStore.instance.save(
      widget.boardFileName,
      BoardCalibration(
        left: grid.left / size.width,
        top: grid.top / size.height,
        right: grid.right / size.width,
        bottom: grid.bottom / size.height,
      ),
    );
  }

  Future<void> _reset() async {
    setState(() {
      _grid = BoardLayout.defaultGridRect(_canvas);
    });
    await BoardCalibrationStore.instance.reset(widget.boardFileName);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('已恢复默认对齐')),
      );
    }
  }
}

/// 左上 / 右下角扇形拖动手柄：在两个角落各画一个朝向棋盘内部的
/// 四分之一扇形（半透明填充 + 描边）和角点实心圆。
class _HandlePainter extends CustomPainter {
  const _HandlePainter({
    required this.topLeft,
    required this.bottomRight,
    required this.fanRadius,
  });

  final Offset topLeft;
  final Offset bottomRight;
  final double fanRadius;

  static const _color = Color(0xFFD32F2F);

  @override
  void paint(Canvas canvas, Size size) {
    // 扇形半径较大（棋盘宽度一半），填充用很低的透明度，避免遮挡棋盘
    final fill = Paint()..color = _color.withValues(alpha: 0.08);
    final stroke = Paint()
      ..color = _color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    final dot = Paint()..color = _color;

    // 左上角：扇形朝向棋盘内部（向右 0 → 向下 pi/2）
    final tlRect = Rect.fromCircle(center: topLeft, radius: fanRadius);
    canvas.drawArc(tlRect, 0, 1.5707963, true, fill);
    canvas.drawArc(tlRect, 0, 1.5707963, true, stroke);
    canvas.drawCircle(topLeft, 5, dot);

    // 右下角：扇形朝向棋盘内部（向左 pi → 向上 3pi/2）
    final brRect =
        Rect.fromCircle(center: bottomRight, radius: fanRadius);
    canvas.drawArc(brRect, 3.1415926, 1.5707963, true, fill);
    canvas.drawArc(brRect, 3.1415926, 1.5707963, true, stroke);
    canvas.drawCircle(bottomRight, 5, dot);
  }

  @override
  bool shouldRepaint(covariant _HandlePainter oldDelegate) =>
      oldDelegate.topLeft != topLeft ||
      oldDelegate.bottomRight != bottomRight ||
      oldDelegate.fanRadius != fanRadius;
}
