import '../models/board.dart';
import '../models/piece.dart';
import '../models/position.dart';

/// 将/帅规则：九宫内一格直走(横或纵)，且不可与对方将同列正对(飞将禁律)。
///
/// 飞将判定放在 [MoveValidator.validateMove] 中统一处理，此处只检查走法形态。
class GeneralRules {
  const GeneralRules._();

  static Iterable<Position> validMoves(Board board, Position from) {
    final piece = board.pieceAt(from);
    if (piece == null || piece.type != PieceType.general) return const [];
    final results = <Position>[];
    const deltas = [(0, 1), (0, -1), (1, 0), (-1, 0)];
    for (final (dc, dr) in deltas) {
      final to = from.offset(dc, dr);
      if (!to.isValid) continue;
      if (!to.inPalaceOf(piece.side)) continue;
      final target = board.pieceAt(to);
      if (target == null || target.side != piece.side) {
        results.add(to);
      }
    }
    return results;
  }
}
