/// 象棋棋盘常量。
///
/// 约定：
/// - 棋盘为 9 列(路) × 10 行(线)，列索引 0..8，行索引 0..9。
/// - 红方位于下方(行 5..9)，黑方位于上方(行 0..4)。
/// - 楚河汉界位于第 4 行与第 5 行之间。
class BoardConstants {
  BoardConstants._();

  /// 棋盘列数(9 路)。
  static const int columnCount = 9;

  /// 棋盘行数(10 线)。
  static const int rowCount = 10;

  /// 楚河汉界上方行索引(黑方一侧为 0..4)。
  static const int riverBlackSide = 4;

  /// 楚河汉界下方行索引(红方一侧为 5..9)。
  static const int riverRedSide = 5;

  /// 红方九宫行范围。
  static const int redPalaceRowStart = 7;
  static const int redPalaceRowEnd = 9;

  /// 黑方九宫行范围。
  static const int blackPalaceRowStart = 0;
  static const int blackPalaceRowEnd = 2;

  /// 九宫列范围(双方一致)。
  static const int palaceColumnStart = 3;
  static const int palaceColumnEnd = 5;

  /// 兵/卒过河前的起始行。
  static const int redSoldierRow = 6;
  static const int blackSoldierRow = 3;
}
