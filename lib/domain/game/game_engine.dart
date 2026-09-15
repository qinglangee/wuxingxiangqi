import '../models/move.dart';
import '../models/piece.dart';
import '../models/position.dart';
import '../rules/move_validator.dart';
import 'game_result.dart';
import 'game_state.dart';

/// 引擎：执行走法、合法性总校验、将军/将死/胜负判定。
class GameEngine {
  GameEngine(this._state) : _validator = const MoveValidator();

  final GameState _state;
  final MoveValidator _validator;

  GameState get state => _state;
  MoveValidator get validator => _validator;

  /// 列出 from 处棋子的合法终点。
  Iterable<Position> legalMovesFrom(Position from) {
    final piece = _state.board.pieceAt(from);
    if (piece == null) return const [];
    if (piece.side != _state.currentSide) return const [];
    if (_state.isOver) return const [];
    return _validator.legalMoves(_state.board, from);
  }

  /// 尝试执行 from → to 走法。成功返回 true。
  bool tryMove(Position from, Position to) {
    if (_state.isOver) return false;
    final piece = _state.board.pieceAt(from);
    if (piece == null || piece.side != _state.currentSide) return false;
    if (!_validator.isLegalMove(_state.board, from, to)) return false;

    final captured = _state.board.pieceAt(to);
    _state.applyMove(Move(
      from: from,
      to: to,
      moving: piece,
      captured: captured,
    ));

    _updateResultAfterMove();
    return true;
  }

  /// 走完后更新结果：若对方无合法走法且其将被将军，则本方胜。
  void _updateResultAfterMove() {
    final nextSide = _state.currentSide; // applyMove 后已翻为下一方
    final hasMove = _hasAnyLegalMove(nextSide);
    final inCheck = _isInCheck(nextSide);
    if (!hasMove) {
      final winner = nextSide == Side.red ? Side.black : Side.red;
      _state.setResult(GameResult(
        status: winner == Side.red
            ? GameResultStatus.redWins
            : GameResultStatus.blackWins,
        reason: inCheck ? '将死' : '困毙',
      ));
    }
  }

  bool _hasAnyLegalMove(Side side) {
    for (final r in _state.board.pieces(of: side)) {
      if (_validator.legalMoves(_state.board, r.position).isNotEmpty) {
        return true;
      }
    }
    return false;
  }

  bool _isInCheck(Side side) {
    final board = _state.board;
    final kingPos = board.findPiece(PieceType.general, side);
    if (kingPos == null) return false;
    final attacker = side == Side.red ? Side.black : Side.red;
    for (final r in board.pieces(of: attacker)) {
      // 借助 validator 的 raw 判断是否攻击 kingPos
      // 简化：直接用 legalMoves(过滤后) 检测是否吃将。
      if (_validator.legalMoves(board, r.position).contains(kingPos)) {
        return true;
      }
    }
    return false;
  }
}
