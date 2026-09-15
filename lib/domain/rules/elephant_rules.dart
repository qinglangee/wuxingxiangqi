import '../models/board.dart';
import '../models/piece.dart';
import '../models/position.dart';

/// 象/相规则：田字格斜走两格，不可过河，象眼(中间点)须无子。
class ElephantRules {
  const ElephantRules._();

  static Iterable<Position> validMoves(Board board, Position from) {
    final piece = board.pieceAt(from);
    if (piece == null || piece.type != PieceType.elephant) return const [];
    final results = <Position>[];
    // 斜向田字：(±2, ±2)
    const deltas = [(2, 2), (2, -2), (-2, 2), (-2, -2)];
    for (final (dc, dr) in deltas) {
      final to = from.offset(dc, dr);
      if (!to.isValid) continue;
      if (!to.onSideOf(piece.side)) continue; // 不可过河
      // 象眼：起点与终点中点
      final eye = from.offset(dc ~/ 2, dr ~/ 2);
      if (board.pieceAt(eye) != null) continue; // 塞象眼
      final target = board.pieceAt(to);
      if (target == null || target.side != piece.side) {
        results.add(to);
      }
    }
    return results;
  }
}
