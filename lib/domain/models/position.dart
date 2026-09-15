import 'piece.dart' show Side;

/// 棋盘坐标(col, row)。
///
/// col: 0..8(列)，row: 0..9(行)。
/// 红方在底部(row 较大)，黑方在顶部(row 较小)。
class Position {
  const Position(this.col, this.row);

  final int col;
  final int row;

  bool get isValid => col >= 0 && col <= 8 && row >= 0 && row <= 9;

  Position offset(int dCol, int dRow) => Position(col + dCol, row + dRow);

  /// 该坐标是否在红方一侧(包括河界及以下)。
  bool get isRedSide => row >= 5;

  /// 该坐标是否在黑方一侧。
  bool get isBlackSide => row <= 4;

  /// 是否在红方九宫内。
  bool get inRedPalace => row >= 7 && row <= 9 && col >= 3 && col <= 5;

  /// 是否在黑方九宫内。
  bool get inBlackPalace => row >= 0 && row <= 2 && col >= 3 && col <= 5;

  /// 是否在给定阵营的九宫内。
  bool inPalaceOf(Side side) => side == Side.red ? inRedPalace : inBlackPalace;

  /// 是否在给定阵营的本侧(未过河)。
  bool onSideOf(Side side) => side == Side.red ? isRedSide : isBlackSide;

  @override
  bool operator ==(Object other) =>
      other is Position && other.col == col && other.row == row;

  @override
  int get hashCode => Object.hash(col, row);

  @override
  String toString() => '($col,$row)';
}
