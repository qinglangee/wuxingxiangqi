import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/constants/board_constants.dart';
import '../../../core/theme/app_theme.dart';
import '../../../domain/engine/fen.dart';
import '../../../domain/models/board.dart';
import '../../../domain/models/piece.dart';
import '../../../domain/models/position.dart';
import '../../controllers/game_controller.dart';
import '../../shared/board_grid_painter.dart';
import '../../shared/error_dialog.dart';
import '../../shared/floating_toast.dart';
import 'board_widget.dart';
import 'piece_widget.dart';

/// 全屏摆局页面：自由摆放棋子生成局面。
///
/// - 棋盘在上方；棋盘下方两排待摆棋子（红上黑下），每排 7 种棋子
///   并显示剩余可用数量（初始数量减去已在棋盘上的数量）。
/// - 点击棋子选中种类，再点击棋盘空位放置（可用数量为零不可放置）；
///   点击棋盘上的棋子则将其移除、可用数量回增。
/// - 按钮区：红先/黑先（先走方，默认红先）、摆满（初始局面）、
///   清空（仅保留将帅）、复制 FEN、粘贴 FEN、翻转、对称。
/// - 「完成」复制当前 FEN 后以该 FEN 关闭页面，打谱页用其初始化；
///   顶部导航条关闭按钮直接关闭、不做其它动作。
class BoardSetupScreen extends StatefulWidget {
  const BoardSetupScreen({super.key, required this.controller});

  final GameController controller;

  /// 打开摆局页；「完成」时以最终 FEN 作为返回值关闭（取消返回 null）。
  static Future<String?> open(BuildContext context, GameController controller) {
    return Navigator.of(context).push<String>(
      MaterialPageRoute<String>(
        builder: (_) => BoardSetupScreen(controller: controller),
        fullscreenDialog: true,
      ),
    );
  }

  @override
  State<BoardSetupScreen> createState() => _BoardSetupScreenState();
}

class _BoardSetupScreenState extends State<BoardSetupScreen> {
  /// 各棋子的标准可用数量（初始局面的组成）。
  static const Map<PieceType, int> _stdCounts = {
    PieceType.general: 1,
    PieceType.advisor: 2,
    PieceType.elephant: 2,
    PieceType.horse: 2,
    PieceType.chariot: 2,
    PieceType.cannon: 2,
    PieceType.soldier: 5,
  };

  /// 待摆棋子的 7 种类型（按摆子排列顺序）。
  static const List<PieceType> _types = [
    PieceType.general,
    PieceType.advisor,
    PieceType.elephant,
    PieceType.horse,
    PieceType.chariot,
    PieceType.cannon,
    PieceType.soldier,
  ];

  /// 正在编辑的棋盘：以打谱页当前局面为起点。
  late Board _board = widget.controller.state.board.clone();

  /// 先走方，默认红先。
  Side _sideToMove = Side.red;

  /// 棋盘翻转状态（沿用打谱页的翻转设置）。
  late bool _flipped = widget.controller.boardFlipped;

  /// 当前选中的摆子种类（null 表示未选中）。
  (Side, PieceType)? _selected;

  /// 某阵营某棋子的剩余可用数量（标准数量 - 棋盘上已有数量）。
  int _available(Side side, PieceType type) {
    var onBoard = 0;
    for (final e in _board.pieces(of: side)) {
      if (e.piece.type == type) onBoard++;
    }
    return _stdCounts[type]! - onBoard;
  }

  /// 棋盘点击：空位放子（需先选中种类且有余量），有子则移除。
  void _onBoardTap(Position pos) {
    final p = _board.pieceAt(pos);
    if (p != null) {
      var removed = _board.removeAt(pos);
      if (removed != null) {
        // setState(() {});
        _selected = (removed.side, removed.type);
      }
    } else {
      final sel = _selected;
      if (sel == null) return;
      final (side, type) = sel;
      if (_available(side, type) <= 0) {
        FloatingToast.show(context, '该棋子可用数量为零');
        return;
      }
      _board.place(Piece(type: type, side: side), pos);
    }
    setState(() {});
  }

  /// 摆满：恢复到标准初始局面。
  void _fillInitial() {
    setState(() => _board = Board()..resetToInitial());
  }

  /// 清空：初始局面只保留双方的将和帅。
  void _clearExceptGenerals() {
    final b = Board();
    b.place(
        const Piece(type: PieceType.general, side: Side.red),
        const Position(4, 9));
    b.place(
        const Piece(type: PieceType.general, side: Side.black),
        const Position(4, 0));
    setState(() => _board = b);
  }

  /// 复制当前局面 FEN 到剪贴板。
  Future<void> _copyFen() async {
    final fen = Fen.fromBoard(_board, _sideToMove);
    await Clipboard.setData(ClipboardData(text: fen));
    if (mounted) FloatingToast.show(context, '已复制 FEN');
  }

  /// 从剪贴板读取 FEN 并摆到棋盘上（先走方随 FEN 更新）。
  Future<void> _pasteFen() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final fen = data?.text?.trim() ?? '';
    if (fen.isEmpty) {
      if (mounted) FloatingToast.show(context, '剪贴板中没有文本');
      return;
    }
    try {
      final (b, side) = Fen.toBoard(fen);
      setState(() {
        _board = b;
        _sideToMove = side;
      });
    } catch (e) {
      if (mounted) showErrorDialog(context, 'FEN 格式错误：$e');
    }
  }

  /// 左右对称：所有棋子按中线镜像到另一侧。
  void _mirror() {
    final b = Board();
    for (final e in _board.pieces()) {
      b.place(
        e.piece,
        Position(
          BoardConstants.columnCount - 1 - e.position.col,
          e.position.row,
        ),
      );
    }
    setState(() => _board = b);
  }

  /// 完成：复制 FEN 并以 FEN 关闭，打谱页用它初始化。
  Future<void> _finish() async {
    final fen = Fen.fromBoard(_board, _sideToMove);
    await Clipboard.setData(ClipboardData(text: fen));
    if (mounted) Navigator.of(context).pop(fen);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('摆局'),
        // 关闭按钮：直接关闭，不做其它动作
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            // 棋盘区：占剩余空间，按宽度自适应并保证完整显示
            Expanded(
              child: LayoutBuilder(
                builder: (context, c) {
                  var w = c.maxWidth;
                  final h = BoardLayout.sizeForWidth(w).height;
                  if (h > c.maxHeight) w = w * c.maxHeight / h;
                  final size = BoardLayout.sizeForWidth(w);
                  return Center(
                    child: SizedBox(
                      width: size.width,
                      height: size.height,
                      child: BoardWidget(
                        board: _board,
                        selected: null,
                        hints: const {},
                        onTap: _onBoardTap,
                        flipped: _flipped,
                      ),
                    ),
                  );
                },
              ),
            ),
            // 待摆棋子：红上黑下，每排 7 种
            _paletteRow(Side.red),
            _paletteRow(Side.black),
            const SizedBox(height: 4),
            // 先走方选择
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Checkbox(
                  value: _sideToMove == Side.red,
                  onChanged: (_) => setState(() => _sideToMove = Side.red),
                ),
                const Text('红先'),
                const SizedBox(width: 24),
                Checkbox(
                  value: _sideToMove == Side.black,
                  onChanged: (_) => setState(() => _sideToMove = Side.black),
                ),
                const Text('黑先'),
              ],
            ),
            // 摆满 / 清空 / 翻转 / 对称
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                OutlinedButton(
                  onPressed: _fillInitial,
                  child: const Text('摆满'),
                ),
                OutlinedButton(
                  onPressed: _clearExceptGenerals,
                  child: const Text('清空'),
                ),
                OutlinedButton(
                  onPressed: () => setState(() => _flipped = !_flipped),
                  child: const Text('翻转'),
                ),
                OutlinedButton(onPressed: _mirror, child: const Text('对称')),
              ],
            ),
            const SizedBox(height: 4),
            // 复制 / 粘贴 FEN
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                OutlinedButton(
                  onPressed: _copyFen,
                  child: const Text('复制 FEN'),
                ),
                OutlinedButton(
                  onPressed: _pasteFen,
                  child: const Text('粘贴 FEN'),
                ),
              ],
            ),
            const SizedBox(height: 4),
            // 完成
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: AppTheme.boardLine,
                  ),
                  onPressed: _finish,
                  child: const Text('完成'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 一排待摆棋子：7 种棋子 + 各自剩余可用数量。
  Widget _paletteRow(Side side) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        for (final t in _types)
          _PaletteChip(
            piece: Piece(type: t, side: side),
            available: _available(side, t).clamp(0, 99),
            selected: _selected == (side, t),
            onTap: () => setState(() {
              _selected = _selected == (side, t) ? null : (side, t);
            }),
          ),
      ],
    );
  }
}

/// 待摆棋子组件：棋子图 + 剩余数量角标，选中时高亮描边。
class _PaletteChip extends StatelessWidget {
  const _PaletteChip({
    required this.piece,
    required this.available,
    required this.selected,
    required this.onTap,
  });

  final Piece piece;
  final int available;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 2),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: selected ? AppTheme.selectedHighlight : Colors.transparent,
            width: 2,
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            PieceWidget(piece: piece, size: 36, selected: selected),
            Text(
              '×$available',
              style: TextStyle(
                fontSize: 11,
                color: available > 0 ? Colors.black87 : Colors.red,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
