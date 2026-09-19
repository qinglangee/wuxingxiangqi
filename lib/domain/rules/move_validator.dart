import '../models/board.dart';
import '../models/piece.dart';
import '../models/position.dart';
import 'general_rules.dart';
import 'advisor_rules.dart';
import 'elephant_rules.dart';
import 'horse_rules.dart';
import 'chariot_rules.dart';
import 'cannon_rules.dart';
import 'soldier_rules.dart';

/// 规则调度入口：按 PieceType 分发到各子规则，并应用全局约束(飞将、走后己方被将军)。
class MoveValidator {
  const MoveValidator();

  /// 列出 from 处棋子的所有合法终点(已过滤将军/飞将等)。
  Iterable<Position> legalMoves(Board board, Position from) sync* {
    final piece = board.pieceAt(from);
    if (piece == null) return;
    for (final to in _rawMoves(board, from, piece)) {
      if (_isMoveFullyLegal(board, from, to, piece.side)) {
        yield to;
      }
    }
  }

  /// 单点校验：from → to 是否为合法走法(含全局约束)。
  bool isLegalMove(Board board, Position from, Position to) {
    final piece = board.pieceAt(from);
    if (piece == null) return false;
    final raw = _rawMoves(board, from, piece).toSet();
    if (!raw.contains(to)) return false;
    return _isMoveFullyLegal(board, from, to, piece.side);
  }

  /// 各棋子的"形走法"(不含全局约束)。
  Iterable<Position> _rawMoves(Board board, Position from, Piece piece) {
    switch (piece.type) {
      case PieceType.general:
        return GeneralRules.validMoves(board, from);
      case PieceType.advisor:
        return AdvisorRules.validMoves(board, from);
      case PieceType.elephant:
        return ElephantRules.validMoves(board, from);
      case PieceType.horse:
        return HorseRules.validMoves(board, from);
      case PieceType.chariot:
        return ChariotRules.validMoves(board, from);
      case PieceType.cannon:
        return CannonRules.validMoves(board, from);
      case PieceType.soldier:
        return SoldierRules.validMoves(board, from);
    }
  }

  /// 全局合法性：走后己方不被将军，且不构成飞将(两将同列正对且无棋阻隔)。
  bool _isMoveFullyLegal(
      Board board, Position from, Position to, Side mover) {
    final snapshot = board.clone();
    snapshot.move(from, to);
    // 飞将已由 _isInCheck 中「对方将/帅攻击本方将/帅」的逻辑覆盖，无需单独判定
    return !_isInCheck(snapshot, mover);
  }

  /// 是否两将位于同列且中间无任何棋子(飞将)。
  bool _kingsFacing(Board board) {
    final red = board.findPiece(PieceType.general, Side.red);
    final black = board.findPiece(PieceType.general, Side.black);
    if (red == null || black == null) return false;
    if (red.col != black.col) return false;
    final r1 = red.row, r2 = black.row;
    final lo = r1 < r2 ? r1 : r2;
    final hi = r1 < r2 ? r2 : r1;
    for (var r = lo + 1; r < hi; r++) {
      if (board.pieceAt(Position(red.col, r)) != null) return false;
    }
    return true;
  }

  /// 给定阵营的将/帅是否被对方任何棋子"攻击"。
  bool _isInCheck(Board board, Side side) {
    final kingPos = board.findPiece(PieceType.general, side);
    if (kingPos == null) return false;
    final attacker = side == Side.red ? Side.black : Side.red;
    for (final (:position, :piece) in board.pieces(of: attacker)) {
      // 飞将：对方将正面攻击本方将
      if (piece.type == PieceType.general) {
        if (_kingsFacing(board)) {
          return true;
        }
        continue;
      }
      // 用各子规则的 raw 移动集合检测是否含 kingPos
      if (_rawMoves(board, position, piece).contains(kingPos)) {
        return true;
      }
    }
    return false;
  }
}
