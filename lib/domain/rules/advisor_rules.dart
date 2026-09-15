import '../models/board.dart';
import '../models/piece.dart';
import '../models/position.dart';

/// 士/仕规则：九宫内斜走一格。
class AdvisorRules {
  const AdvisorRules._();

  static Iterable<Position> validMoves(Board board, Position from) {
    final piece = board.pieceAt(from);
    if (piece == null || piece.type != PieceType.advisor) return const [];
    final results = <Position>[];
    const deltas = [(1, 1), (1, -1), (-1, 1), (-1, -1)];
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
