import '../models/board.dart';
import '../models/move.dart';
import '../models/piece.dart';
import '../models/position.dart';
import 'game_result.dart';

/// 游戏状态：当前棋盘、当前轮次、走棋历史、被吃棋子列表、结果。
class GameState {
  GameState() {
    _board.resetToInitial();
  }

  final Board _board = Board();
  Side _currentSide = Side.red; // 红先
  final List<Move> _history = [];
  final List<Piece> _captured = [];
  GameResult _result = const GameResult(status: GameResultStatus.ongoing);

  Board get board => _board;
  Side get currentSide => _currentSide;
  List<Move> get history => List.unmodifiable(_history);
  List<Piece> get captured => List.unmodifiable(_captured);
  GameResult get result => _result;
  bool get isOver => _result.isOver;

  /// 是否已有选中棋子(供 UI 高亮)。
  Position? selected;

  /// 应用合法走法并翻转轮次。
  void applyMove(Move move) {
    final captured = _board.move(move.from, move.to);
    _history.add(Move(
      from: move.from,
      to: move.to,
      moving: move.moving,
      captured: captured,
    ));
    if (captured != null) _captured.add(captured);
    _currentSide = _currentSide == Side.red ? Side.black : Side.red;
    selected = null;
  }

  /// 设置游戏结果(用于引擎判定胜负后回填)。
  void setResult(GameResult result) {
    _result = result;
  }

  /// 重置整局(回到初始布局)。
  void reset() {
    _board.resetToInitial();
    _history.clear();
    _captured.clear();
    _currentSide = Side.red;
    selected = null;
    _result = const GameResult(status: GameResultStatus.ongoing);
  }
}
