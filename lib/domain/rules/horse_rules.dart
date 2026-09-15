import '../models/board.dart';
import '../models/piece.dart';
import '../models/position.dart';

/// 马规则：日字格斜走，蹩马腿(相邻直线点)须无子。
class HorseRules {
  const HorseRules._();

  static Iterable<Position> validMoves(Board board, Position from) {
    final piece = board.pieceAt(from);
    if (piece == null || piece.type != PieceType.horse) return const [];
    final results = <Position>[];
    // (走法终点, 蹩马腿位置)
    const moves = <(int, int, int, int)>[
      (1, 2, 0, 1),   // 右下日字，腿在正下
      (-1, 2, 0, 1),  // 左下日字，腿在正下
      (1, -2, 0, -1),
      (-1, -2, 0, -1),
      (2, 1, 1, 0),   // 右下日字(横向起步)，腿在正右
      (2, -1, 1, 0),
      (-2, 1, -1, 0),
      (-2, -1, -1, 0),
    ];
    for (final (dc, dr, lc, lr) in moves) {
      final to = from.offset(dc, dr);
      if (!to.isValid) continue;
      final leg = from.offset(lc, lr);
      if (board.pieceAt(leg) != null) continue; // 蹩马腿
      final target = board.pieceAt(to);
      if (target == null || target.side != piece.side) {
        results.add(to);
      }
    }
    return results;
  }
}
