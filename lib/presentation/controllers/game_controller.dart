import 'package:flutter/foundation.dart';

import '../../domain/engine/fen.dart';
import '../../domain/engine/pikafish_engine.dart';
import '../../domain/game/game_engine.dart';
import '../../domain/game/game_result.dart';
import '../../domain/game/game_state.dart';
import '../../domain/models/move.dart';
import '../../domain/models/piece.dart';
import '../../domain/models/position.dart';
import '../../domain/notation/move_record.dart';
import '../../domain/notation/notation_node.dart';
import '../../domain/notation/notation_text.dart';
import '../../domain/notation/parsers/notation_exception.dart';
import '../../domain/notation/parsers/notation_replay.dart';
import '../../domain/notation/parsers/parsed_game.dart';

/// UI 控制器：选中态、点击处理、AI 走子、棋谱树记录与前进/后退导航。
class GameController extends ChangeNotifier {
  GameController()
      : _state = GameState(),
        super() {
    _root = NotationNode.root(_state.board.clone());
    _current = _root;
    // 标准开局 = 一局新游戏
    _ai.notifyNewGame(Fen.fromBoard(_state.board, Side.red));
  }

  final GameState _state;
  late final GameEngine _engine = GameEngine(_state);
  final PikafishEngine _ai = PikafishEngine.instance;

  /// 棋谱树根（初始局面）。
  late NotationNode _root;

  /// 当前浏览/对弈所在的节点。
  late NotationNode _current;

  bool _redIsAi = false;
  bool _blackIsAi = false;
  bool _aiThinking = false;

  /// 终局事件计数：仅当「新走子」导致对局结束时 +1。
  ///
  /// 前进/后退到已记录的终局节点不改变计数，避免浏览棋谱时反复弹结束窗。
  int _resultTick = 0;
  int get resultTick => _resultTick;

  bool get redIsAi => _redIsAi;
  bool get blackIsAi => _blackIsAi;
  bool get aiThinking => _aiThinking;

  GameState get state => _state;
  GameEngine get engine => _engine;
  GameResult get result => _state.result;
  bool get isOver => _state.isOver;
  Side get currentSide => _state.currentSide;
  Position? get selected => _state.selected;

  // ---- 棋谱导航相关 ----

  /// 当前棋谱节点。
  NotationNode get currentNode => _current;

  /// 根 → 末梢的主线（含根节点），用于棋谱栏展示。
  List<NotationNode> get mainLine => _root.mainLine();

  bool get canGoBack => !_current.isRoot;
  bool get canGoForward => _current.mainChild != null;

  /// 是否正处于棋谱末梢（只有末梢上的新走子才触发 AI 续走）。
  bool get atTip => _current.isTip;

  /// 是否存在上一个分支点（沿父链向上的某祖先有多于 1 个续着）。
  bool get canGoPrevBranch {
    var n = _current.parent;
    while (n != null) {
      if (n.children.length > 1) return true;
      n = n.parent;
    }
    return false;
  }

  /// 是否存在下一个分支点（沿主线向下的某后代有多于 1 个续着）。
  bool get canGoNextBranch {
    var n = _current.mainChild;
    while (n != null) {
      if (n.children.length > 1) return true;
      n = n.mainChild;
    }
    return false;
  }

  /// 当前节点是否为分支点（有多条候选续着）。
  bool get atBranch => _current.children.length > 1;

  /// 当前节点下的所有候选分支（每个对应一步棋）。
  ///
  /// 非分支点时返回空列表。
  List<NotationNode> get branchOptions =>
      List.unmodifiable(_current.children);

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

    // 未选中任何棋子时，点击任意棋子选中该棋子
    if (_state.selected == null) {
      if (piece != null && piece.side == currentSide) {
        _state.selected = pos;
        notifyListeners();
      }
      return;
    }
    // 已选中棋子时，点击相同位置子不变
    final selected = _state.selected!;
    if (selected == pos) {
      return;
    }
    // 已选中棋子时，点击不同位置子选中该棋子
    if (piece != null && piece.side == currentSide) {
      _state.selected = pos;
      notifyListeners();
      return;
    }

    if (_applyAndRecord(selected, pos)) {
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
    _root = NotationNode.root(_state.board.clone());
    _current = _root;
    _aiThinking = false;
    _resultTick = 0;
    // 重开 = 一局新游戏
    _ai.notifyNewGame(Fen.fromBoard(_state.board, Side.red));
    notifyListeners();
    _maybeTriggerAiMove();
  }

  /// 从外部解析结果（[ParsedGame]）载入棋谱并构建棋谱树。
  ///
  /// 流程：
  /// 1. 通过 [NotationReplay.resolve] 解析起始局面并校验每步着法
  ///    （调用方通常已在跳转前验证过，[replay] 可直接传入复用）；
  /// 2. 顺序回放坐标构建棋谱树；
  /// 3. 完成后跳回根节点，显示棋谱初始状态。
  ///
  /// 解析或规则校验失败时抛 [NotationParseException]。
  void loadParsedGame(ParsedGame game, {ReplayData? replay}) {
    final data = replay ?? NotationReplay.resolve(game);

    _state.restoreFrom(
      board: data.startBoard,
      sideToMove: data.startSide,
      result: const GameResult(status: GameResultStatus.ongoing),
      history: const [],
      isInitialState: true,
    );
    _root = NotationNode.root(data.startBoard.clone(),
        sideToMove: data.startSide);
    _root.comment = game.rootComment; // 开局评注挂在根节点的局面注释上
    _current = _root;
    _aiThinking = false;
    _resultTick = 0;
    // 导入棋谱 = 一局新游戏，初始局面为棋谱起始 FEN
    _ai.notifyNewGame(Fen.fromBoard(data.startBoard, data.startSide));

    for (var i = 0; i < data.moves.length; i++) {
      final (from, to) = data.moves[i];
      if (!_applyAndRecord(from, to)) {
        // 理论上不会发生（resolve 已验证），这里做防御性兜底
        throw NotationParseException(
          '第 ${i + 1} 步着法不符合规则：${game.moves[i].moveText}',
        );
      }
      final comment = game.moves[i].comment;
      if (comment != null && comment.isNotEmpty) {
        _current.move?.comment = comment;
      }
    }

    // 回放到末尾后，跳回根节点显示初始状态
    _current = _root;
    _restoreStateFromCurrent();
    notifyListeners();
  }

  // ---- 棋谱前进 / 后退 / 跳转 ----

  /// 直接从 FEN 字符串载入一个起始局面（残局模式）。
  ///
  /// 重建棋谱树根节点为该局面，重置当前节点、AI 状态与结果计数。
  /// 与 [loadParsedGame] 互斥：用于无完整棋谱、仅给定起始 FEN 的场景。
  void loadFen(String fen) {
    final (board, side) = Fen.toBoard(fen);
    _state.restoreFrom(
      board: board,
      sideToMove: side,
      result: const GameResult(status: GameResultStatus.ongoing),
      history: const [],
      isInitialState: true,
    );
    _root = NotationNode.root(board.clone(), sideToMove: side);
    _current = _root;
    _aiThinking = false;
    _resultTick = 0;
    // 载入残局局面 = 一局新游戏
    _ai.notifyNewGame(fen);
    notifyListeners();
  }

  /// 后退一步：回到上一节点并恢复盘面。导航操作不触发 AI。
  void goBack() => _jumpTo(_current.parent);

  /// 前进一步：沿当前续着指针前进。
  void goForward() => _jumpTo(_current.mainChild);

  /// 跳转到棋谱树中的任意节点（点击棋谱步时使用）。
  void jumpTo(NotationNode node) => _jumpTo(node);

  /// 跳到上一个分支点（沿父链向上最近的有多个续着的祖先）。
  void goToPrevBranch() {
    var n = _current.parent;
    while (n != null) {
      if (n.children.length > 1) {
        _jumpTo(n);
        return;
      }
      n = n.parent;
    }
  }

  /// 跳到下一个分支点（沿主线下行最近的有多个续着的后代）。
  void goToNextBranch() {
    var n = _current.mainChild;
    while (n != null) {
      if (n.children.length > 1) {
        _jumpTo(n);
        return;
      }
      n = n.mainChild;
    }
  }

  /// 选择当前分支点下的第 [index] 条分支（0-based）。
  ///
  /// 把父节点（当前节点）的 [NotationNode.mainChildIndex] 改为 [index]，
  /// 然后跳到该分支节点。后续「前进」会沿该分支继续走。
  void selectBranch(int index) {
    if (index < 0 || index >= _current.children.length) return;
    _current.mainChildIndex = index;
    _jumpTo(_current.children[index]);
  }

  /// 当前节点的注释文本（无则返回空字符串）。
  ///
  /// - 非根节点：注释属于「到达当前节点的那步棋」，保存于
  ///   [MoveRecord.comment]；
  /// - 根节点：注释为「开局局面评注」，保存于 [NotationNode.comment]。
  String get currentComment {
    final move = _current.move;
    if (move != null) return move.comment ?? '';
    return _current.comment ?? '';
  }

  /// 设置当前节点的注释。空字符串视为清除注释。
  ///
  /// 根节点写入 [NotationNode.comment]（开局评注），其余节点写入
  /// 到达该节点那步棋的 [MoveRecord.comment]。
  void setCurrentComment(String text) {
    final trimmed = text.trim();
    final move = _current.move;
    if (move != null) {
      move.comment = trimmed.isEmpty ? null : trimmed;
    } else {
      _current.comment = trimmed.isEmpty ? null : trimmed;
    }
    notifyListeners();
  }

  void _jumpTo(NotationNode? target) {
    if (target == null || _aiThinking || identical(target, _current)) return;
    _current = target;
    _restoreStateFromCurrent();
    notifyListeners();
  }

  void _restoreStateFromCurrent() {
    final path = _current.pathFromRoot();
    final moves = path
        .skip(1)
        .map((n) {
          final m = n.move!;
          return Move(from: m.from, to: m.to, moving: m.moving, captured: m.captured);
        })
        .toList();
    _state.restoreFrom(
      board: _current.board,
      sideToMove: _current.sideToMove,
      result: _current.result,
      history: moves,
      isInitialState: _current.isRoot,
    );
  }

  bool _isAiSide(Side side) =>
      side == Side.red ? _redIsAi : _blackIsAi;

  /// 执行走法并写入棋谱树。
  ///
  /// 若当前节点已有续着（后退后另走），新走法作为分支加入，
  /// 且前进指针自动指向新分支。
  bool _applyAndRecord(Position from, Position to) {
    final before = _state.board.clone();
    final moving = before.pieceAt(from);
    if (moving == null) return false;

    // 记谱必须基于走子前盘面（同列多子消歧等）
    final notation = NotationText.describe(before, from, to);
    final captured = before.pieceAt(to);

    if (!_engine.tryMove(from, to)) return false;

    final record = MoveRecord(
      from: from,
      to: to,
      moving: moving,
      side: moving.side,
      notation: notation,
      captured: captured,
    );
    _current = _current.addChild(
      move: record,
      board: _state.board.clone(),
      sideToMove: _state.currentSide,
      result: _state.result,
    );
    if (_state.isOver) _resultTick++;
    return true;
  }

  /// 若当前轮次属于 AI 方且处于棋谱末梢，则异步调用引擎走子。
  Future<void> _maybeTriggerAiMove() async {
    if (isOver || _aiThinking) return;
    if (!atTip) return; // 浏览历史着法时不自动走子
    if (!_isAiSide(currentSide)) return;

    _aiThinking = true;
    notifyListeners();
    var moveApplied = false;
    try {
      final fen = Fen.fromBoard(_state.board, currentSide);
      final move = await _ai.bestMove(
        fen,
        moveTimeMs: 3500,
        isInitialState: _state.isInitialState,
      );
      if (move == '(none)' || move.isEmpty) {
        // 引擎未给出走法，停止本次自动走子，避免空转循环
        debugPrint('AI 未返回有效走法: $move');
        return;
      }
      final (from, to) = Fen.parseUciMove(move);
      if (_applyAndRecord(from, to)) {
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
    // 引擎是跨页面共享的全局单例，不能在此关闭进程，否则再次进入打谱页
    // 时进程已死且不会被重新拉起（命令全部丢失）。
    // 只中止当前思考请求：发 stop 并丢弃待返回的 bestmove。
    _ai.cancelSearch();
    super.dispose();
  }
}
