import '../models/board.dart';
import '../models/piece.dart';
import '../models/position.dart';

/// 兵/卒规则：未过河只能向前一格；过河后可向前或左右一格，不可后退。
class SoldierRules {
  const SoldierRules._();

  static Iterable<Position> validMoves(Board board, Position from) {
    final piece = board.pieceAt(from);
    if (piece == null || piece.type != PieceType.soldier) return const [];
    final results = <Position>[];

    // 前进方向：红方向上(row 减小)，黑方向下(row 增加)
    final forwardDelta = piece.side == Side.red ? -1 : 1;
    final crossedRiver = piece.side == Side.red
        ? from.isBlackSide // 红兵过河到黑方一侧
        : from.isRedSide;  // 黑卒过河到红方一侧

    final candidates = <Position>[from.offset(0, forwardDelta)];
    if (crossedRiver) {
      candidates.add(from.offset(-1, 0));
      candidates.add(from.offset(1, 0));
    }
    for (final to in candidates) {
      if (!to.isValid) continue;
      final target = board.pieceAt(to);
      if (target == null || target.side != piece.side) {
        results.add(to);
      }
    }
    return results;
  }
}
