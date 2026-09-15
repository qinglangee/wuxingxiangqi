import 'piece.dart';
import 'position.dart';

/// 棋盘状态：9 列 × 10 行的格子，每格可空或放置一枚棋子。
///
/// 用 `List<List<Piece?>>` 表示，第一维为 row(0..9)，第二维为 col(0..8)。
class Board {
  Board() : _cells = List.generate(10, (_) => List<Piece?>.filled(9, null));

  final List<List<Piece?>> _cells;

  /// 读取指定坐标的棋子(可能为 null)。
  Piece? pieceAt(Position p) {
    if (!p.isValid) return null;
    return _cells[p.row][p.col];
  }

  /// 在指定坐标放置棋子(覆盖原有)。
  void place(Piece piece, Position p) {
    if (!p.isValid) {
      throw ArgumentError('位置越界: $p');
    }
    _cells[p.row][p.col] = piece;
  }

  /// 移动棋子(从 from 到 to)，返回被吃掉的棋子(若有)。
  Piece? move(Position from, Position to) {
    final moving = pieceAt(from);
    if (moving == null) {
      throw StateError('起点无棋子: $from');
    }
    final captured = pieceAt(to);
    _cells[from.row][from.col] = null;
    _cells[to.row][to.col] = moving;
    return captured;
  }

  /// 拷贝当前棋盘(深拷贝)。
  Board clone() {
    final b = Board();
    for (var r = 0; r < 10; r++) {
      for (var c = 0; c < 9; c++) {
        b._cells[r][c] = _cells[r][c];
      }
    }
    return b;
  }

  /// 查找某阵营某类型棋子的位置(通常用于找将/帅)。
  Position? findPiece(PieceType type, Side side) {
    for (var r = 0; r < 10; r++) {
      for (var c = 0; c < 9; c++) {
        final p = _cells[r][c];
        if (p != null && p.type == type && p.side == side) {
          return Position(c, r);
        }
      }
    }
    return null;
  }

  /// 遍历所有棋子(可指定阵营过滤)。
  Iterable<({Position position, Piece piece})> pieces({Side? of}) sync* {
    for (var r = 0; r < 10; r++) {
      for (var c = 0; c < 9; c++) {
        final p = _cells[r][c];
        if (p != null && (of == null || p.side == of)) {
          yield (position: Position(c, r), piece: p);
        }
      }
    }
  }

  /// 复位到象棋初始布局。
  void resetToInitial() {
    for (var r = 0; r < 10; r++) {
      for (var c = 0; c < 9; c++) {
        _cells[r][c] = null;
      }
    }
    // 黑方(上) 第 0 行：车 马 象 士 将 士 象 马 车
    const blackRow0 = [
      PieceType.chariot, PieceType.horse, PieceType.elephant,
      PieceType.advisor, PieceType.general, PieceType.advisor,
      PieceType.elephant, PieceType.horse, PieceType.chariot,
    ];
    for (var c = 0; c < 9; c++) {
      _cells[0][c] = Piece(type: blackRow0[c], side: Side.black);
    }
    // 黑炮：第 2 行 col 1、7
    _cells[2][1] = const Piece(type: PieceType.cannon, side: Side.black);
    _cells[2][7] = const Piece(type: PieceType.cannon, side: Side.black);
    // 黑卒：第 3 行 col 0,2,4,6,8
    for (final c in [0, 2, 4, 6, 8]) {
      _cells[3][c] = const Piece(type: PieceType.soldier, side: Side.black);
    }
    // 红方(下) 第 9 行
    const redRow9 = [
      PieceType.chariot, PieceType.horse, PieceType.elephant,
      PieceType.advisor, PieceType.general, PieceType.advisor,
      PieceType.elephant, PieceType.horse, PieceType.chariot,
    ];
    for (var c = 0; c < 9; c++) {
      _cells[9][c] = Piece(type: redRow9[c], side: Side.red);
    }
    // 红炮：第 7 行 col 1、7
    _cells[7][1] = const Piece(type: PieceType.cannon, side: Side.red);
    _cells[7][7] = const Piece(type: PieceType.cannon, side: Side.red);
    // 红兵：第 6 行 col 0,2,4,6,8
    for (final c in [0, 2, 4, 6, 8]) {
      _cells[6][c] = const Piece(type: PieceType.soldier, side: Side.red);
    }
  }
}
