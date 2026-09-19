import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../domain/engine/fen.dart';
import '../../domain/engine/pikafish_engine.dart';
import '../../domain/game/game_engine.dart';
import '../../domain/game/game_result.dart';
import '../../domain/game/game_state.dart';
import '../../domain/models/piece.dart';
import '../../domain/models/position.dart';

/// UI 控制器：选中态、点击处理、AI 走子、刷新 UI。
class GameController extends ChangeNotifier {
  GameController()
      : _state = GameState(),
        super();

  final GameState _state;
  late final GameEngine _engine = GameEngine(_state);
  final PikafishEngine _ai = PikafishEngine.instance;

  bool _redIsAi = false;
  bool _blackIsAi = false;
  bool _aiThinking = false;

  bool get redIsAi => _redIsAi;
  bool get blackIsAi => _blackIsAi;
  bool get aiThinking => _aiThinking;

  GameState get state => _state;
  GameEngine get engine => _engine;
  GameResult get result => _state.result;
  bool get isOver => _state.isOver;
  Side get currentSide => _state.currentSide;
  Position? get selected => _state.selected;

  Iterable<Position> get selectedHints =>
      _state.selected == null ? const [] : _engine.legalMovesFrom(_state.selected!);

  void setRedAi(bool v) {
    _redIsAi = v;
    notifyListeners();
    _maybeTriggerAiMove();
  }

  void setBlackAi(bool v) {
    _blackIsAi = v;
    notifyListeners();
    _maybeTriggerAiMove();
  }

  void onTap(Position pos) {
    if (isOver) return;
    // AI 正在思考或当前轮到 AI 时，禁止人类点击
    if (_aiThinking) return;
    if (_isAiSide(currentSide)) return;

    final piece = _state.board.pieceAt(pos);

    if (_state.selected == null) {
      if (piece != null && piece.side == currentSide) {
        _state.selected = pos;
        notifyListeners();
      }
      return;
    }

    final selected = _state.selected!;
    if (selected == pos) {
      // _state.selected = null;
      // notifyListeners();
      return;
    }

    if (piece != null && piece.side == currentSide) {
      _state.selected = pos;
      notifyListeners();
      return;
    }

    if (_engine.tryMove(selected, pos)) {
      debugPrint('人类走子: $selected → $pos');
      notifyListeners();
      _maybeTriggerAiMove();
    } else {
      _state.selected = null;
      notifyListeners();
    }
  }

  void restart() {
    _state.reset();
    _aiThinking = false;
    notifyListeners();
    _maybeTriggerAiMove();
  }

  bool _isAiSide(Side side) =>
      side == Side.red ? _redIsAi : _blackIsAi;

  /// 若当前轮次属于 AI 方，则异步调用引擎走子。
  Future<void> _maybeTriggerAiMove() async {
    if (isOver || _aiThinking) return;
    if (!_isAiSide(currentSide)) return;

    _aiThinking = true;
    notifyListeners();
    var moveApplied = false;
    try {
      final fen = Fen.fromBoard(_state.board, currentSide);
      final move = await _ai.bestMove(fen, moveTimeMs: 500);
      if (move == '(none)' || move.isEmpty) {
        // 引擎未给出走法，停止本次自动走子，避免空转循环
        debugPrint('AI 未返回有效走法: $move');
        return;
      }
      final (from, to) = Fen.parseUciMove(move);
      if (_engine.tryMove(from, to)) {
        moveApplied = true;
        notifyListeners();
      } else {
        // 引擎走法未通过本地规则：打印 FEN 与走法以便定位坐标/规则问题
        debugPrint('AI 走法被本地规则拒绝: $move, $from, $to, fen=$fen');
      }
    } catch (e) {
      debugPrint('AI 走子失败: $e');
    } finally {
      _aiThinking = false;
      notifyListeners();
      // 仅在确实走子成功后，才可能继续触发另一方 AI
      if (moveApplied) _maybeTriggerAiMove();
    }
  }

  @override
  void dispose() {
    // fire-and-forget 关闭引擎子进程
    unawaited(_ai.dispose());
    super.dispose();
  }
}
