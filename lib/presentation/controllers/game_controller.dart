import 'package:flutter/foundation.dart';

import '../../domain/game/game_engine.dart';
import '../../domain/game/game_result.dart';
import '../../domain/game/game_state.dart';
import '../../domain/models/piece.dart';
import '../../domain/models/position.dart';

/// UI 控制器：选中态、点击处理、请求走法、刷新 UI。
///
/// 通过 [ChangeNotifier] 通知 UI 重建。UI 用 `context.select` 或 `ListenableBuilder`
/// 订阅；棋盘等组件可在 `notifyListeners()` 后刷新。
class GameController extends ChangeNotifier {
  GameController()
      : _state = GameState(),
        super();

  final GameState _state;
  late final GameEngine _engine = GameEngine(_state);

  GameState get state => _state;
  GameEngine get engine => _engine;
  GameResult get result => _state.result;
  bool get isOver => _state.isOver;
  Side get currentSide => _state.currentSide;
  Position? get selected => _state.selected;

  /// 当前选中棋子的合法终点集合(用于 UI 提示)。
  Iterable<Position> get selectedHints =>
      _state.selected == null ? const [] : _engine.legalMovesFrom(_state.selected!);

  /// 处理棋盘点击。逻辑：
  /// 1. 未选中 + 点击己方棋子 → 选中。
  /// 2. 已选中 + 点击合法终点 → 走子并翻轮。
  /// 3. 已选中 + 点击同色另一棋子 → 改选。
  /// 4. 其它情况 → 取消选中。
  void onTap(Position pos) {
    if (isOver) return;
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
      // 再点一次取消选中
      _state.selected = null;
      notifyListeners();
      return;
    }

    if (piece != null && piece.side == currentSide) {
      _state.selected = pos; // 改选同色棋子
      notifyListeners();
      return;
    }

    if (_engine.tryMove(selected, pos)) {
      notifyListeners(); // 走子成功，UI 刷新；选中态已在 applyMove 内清空
    } else {
      // 非法目标：取消选中
      _state.selected = null;
      notifyListeners();
    }
  }

  /// 重开新局。
  void restart() {
    _state.reset();
    notifyListeners();
  }
}
