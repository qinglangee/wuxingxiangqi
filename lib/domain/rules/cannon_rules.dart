import '../models/board.dart';
import '../models/piece.dart';
import '../models/position.dart';

/// 炮规则：直线移动同车；不吃子时路径须无阻挡；吃子时路径须有且仅有一个棋子(炮架)。
class CannonRules {
  const CannonRules._();

  static Iterable<Position> validMoves(Board board, Position from) {
    final piece = board.pieceAt(from);
    if (piece == null || piece.type != PieceType.cannon) return const [];
    final results = <Position>[];
    const directions = [(0, 1), (0, -1), (1, 0), (-1, 0)];
    for (final (dc, dr) in directions) {
      var pos = from.offset(dc, dr);
      var jumped = false; // 是否已越过炮架
      while (pos.isValid) {
        final target = board.pieceAt(pos);
        if (!jumped) {
          if (target == null) {
            results.add(pos); // 平移
          } else {
            jumped = true; // 遇到炮架，继续找吃子目标
          }
        } else {
          if (target != null) {
            if (target.side != piece.side) results.add(pos); // 越架吃子
            break;
          }
        }
        pos = pos.offset(dc, dr);
      }
    }
    return results;
  }
}
