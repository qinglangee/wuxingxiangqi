import '../models/board.dart';
import '../models/piece.dart';
import '../models/position.dart';

/// 车规则：直线移动，路径上不能有其他棋子，目标点可为空或对方棋子。
class ChariotRules {
  const ChariotRules._();

  static Iterable<Position> validMoves(Board board, Position from) {
    final piece = board.pieceAt(from);
    if (piece == null || piece.type != PieceType.chariot) return const [];
    final results = <Position>[];
    const directions = [(0, 1), (0, -1), (1, 0), (-1, 0)];
    for (final (dc, dr) in directions) {
      var pos = from.offset(dc, dr);
      while (pos.isValid) {
        final target = board.pieceAt(pos);
        if (target == null) {
          results.add(pos);
        } else {
          if (target.side != piece.side) results.add(pos); // 可吃
          break; // 遇子停止
        }
        pos = pos.offset(dc, dr);
      }
    }
    return results;
  }
}
