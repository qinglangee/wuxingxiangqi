import '../../core/constants/board_constants.dart' show BoardConstants;
import '../models/board.dart';
import '../models/piece.dart';
import '../models/position.dart';

/// 象棋 FEN 串转换。
///
/// 象棋 FEN 格式：
///   rnbakabnr/9/1c5c1/p1p1p1p1p/9/9/P1P1P1P1P/1C5C1/9/RNBAKABNR w - - 0 1
/// 棋子字母（黑方小写、红方大写）：
///   r 车 / n 马 / b 象 / a 士 / k 将 / c 炮 / p 卒
/// 行按从黑方顶部(row=0)到红方底部(row=9)排列，连续空格用数字表示。
class Fen {
  Fen._();

  static const _pieceLetters = <PieceType, String>{
    PieceType.chariot: 'r',
    PieceType.horse: 'n',
    PieceType.elephant: 'b',
    PieceType.advisor: 'a',
    PieceType.general: 'k',
    PieceType.cannon: 'c',
    PieceType.soldier: 'p',
  };

  /// 将棋盘状态转换为 FEN 串。
  ///
  /// [currentSide] 决定 FEN 中轮次部分（w = 红方，b = 黑方）。
  static String fromBoard(Board board, Side currentSide) {
    final rows = <String>[];
    for (var r = 0; r < 10; r++) {
      final buf = StringBuffer();
      var empty = 0;
      for (var c = 0; c < 9; c++) {
        final p = board.pieceAt(Position(c, r));
        if (p == null) {
          empty++;
        } else {
          if (empty > 0) {
            buf.write(empty);
            empty = 0;
          }
          final letter = _pieceLetters[p.type]!;
          buf.write(p.side == Side.red ? letter.toUpperCase() : letter);
        }
      }
      if (empty > 0) buf.write(empty);
      rows.add(buf.toString());
    }
    final side = currentSide == Side.red ? 'w' : 'b';
    return '${rows.join('/')} $side - - 0 1';
  }

  /// 将 UCI 走法坐标(如 b2c3) 转换为 (from, to) 两个 Position。
  ///
  /// UCI 列字母 a..i 对应 col 0..8；行号 0..9 对应 row 0..9。
  static (Position, Position) parseUciMove(String move) {
    final fromCol = move.codeUnitAt(0) - 'a'.codeUnitAt(0);
    final fromRow = BoardConstants.rowCount - 1 - int.parse(move[1]);
    final toCol = move.codeUnitAt(2) - 'a'.codeUnitAt(0);
    final toRow = BoardConstants.rowCount - 1 - int.parse(move[3]);
    return (Position(fromCol, fromRow), Position(toCol, toRow));
  }

  /// 将 Position 转换为 UCI 坐标(如 a0)。
  static String positionToUci(Position p) {
    final col = String.fromCharCode('a'.codeUnitAt(0) + p.col);
    return '$col${p.row}';
  }
}
