import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../domain/engine/engine_info.dart';
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
import '../../domain/notation/win_line.dart';
import '../../domain/notation/parsers/notation_exception.dart';
import '../../domain/notation/parsers/notation_replay.dart';
import '../../domain/notation/parsers/parsed_game.dart';
import 'board_change_notifier.dart';

/// UI 控制器：选中态、点击处理、AI 走子、棋谱树记录与前进/后退导航。
class GameController extends ChangeNotifier {
  GameController()
      : _state = GameState(),
        super() {
    _root = NotationNode.root(_state.board.clone());
    _current = _root;
    // 标准开局 = 一局新游戏
    _ai.notifyNewGame();
    // 引擎搜索 info 实时转发给监听方（引擎面板）
    _infoSub = _ai.infoStream.listen((info) {
      _engineInfo = info;
      notifyListeners();
    });
  }

  StreamSubscription<EngineSearchInfo>? _infoSub;

  final GameState _state;
  late final GameEngine _engine = GameEngine(_state);
  final PikafishEngine _ai = PikafishEngine.instance;

  /// 局面变化专用通知器（供云库等模块订阅）。
  ///
  /// 与本类的 notifyListeners 分离——后者在选中棋子、引擎 info 流等
  /// 场景下高频触发；boardChange 仅在「初始化局面」和「走棋方改变」
  /// （走子完成、跳转棋谱节点）时发送。
  final BoardChangeNotifier boardChange = BoardChangeNotifier();

  /// 棋谱树根（初始局面）。
  late NotationNode _root;

  /// 当前浏览/对弈所在的节点。
  late NotationNode _current;

  bool _redIsAi = false;
  bool _blackIsAi = false;
  bool _aiThinking = false;

  /// 提示箭头（仅当用户点击「提示」且提示自动关闭时展示）。
  ///
  /// 值为 bestMove 的 (from, to)，在棋盘上以绿色箭头标注；
  /// 走子（[_applyAndRecord]）或跳转（[_jumpTo]）时清除。
  (Position, Position)? _hintMark;
  (Position, Position)? get hintMark => _hintMark;

  /// 引擎最近一次搜索信息快照（引擎面板展示）；无搜索时为 null。
  EngineSearchInfo? _engineInfo;
  EngineSearchInfo? get engineInfo => _engineInfo;

  /// 当前走子方是否正被将军（终局后不再提示将军）。
  bool get currentInCheck =>
      !_state.isOver && _engine.isInCheck(_state.currentSide);

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

  void setRedAi(bool v, {bool notify = true}) {
    _redIsAi = v;
    if (notify) {
      notifyListeners();
      _maybeTriggerAiMove();
    }
  }

  void setBlackAi(bool v, {bool notify = true}) {
    _blackIsAi = v;
    if (notify) {
      notifyListeners();
      _maybeTriggerAiMove();
    }
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
      _afterMoveApplied();
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
    _hintMark = null;
    // 重开 = 一局新游戏
    _ai.notifyNewGame();
    boardChange.emit();
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
    );
    _root = NotationNode.root(data.startBoard.clone(),
        sideToMove: data.startSide);
    _root.comment = game.rootComment; // 开局评注挂在根节点的局面注释上
    _current = _root;
    _aiThinking = false;
    _resultTick = 0;
    // 导入棋谱 = 一局新游戏
    _ai.notifyNewGame();

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
    boardChange.emit();
    notifyListeners();
  }

  // ---- 棋谱前进 / 后退 / 跳转 ----

  /// 直接从 FEN 字符串载入一个起始局面（残局模式）。
  ///
  /// 重建棋谱树根节点为该局面，重置当前节点、AI 状态与结果计数。
  /// 与 [loadParsedGame] 互斥：用于无完整棋谱、仅给定起始 FEN 的场景。
  ///
  /// [notify] 为 false 时只改状态不发通知——用于 Provider build 阶段
  /// 的首次载入（此时 notifyListeners 会触发 build 期重建异常）；首帧
  /// 构建会直接读到已改好的状态。用户主动切换残局时保持默认 true。
  void loadFen(String fen, {bool notify = true}) {
    final (board, side) = Fen.toBoard(fen);
    _state.restoreFrom(
      board: board,
      sideToMove: side,
      result: const GameResult(status: GameResultStatus.ongoing),
      history: const [],
    );
    _root = NotationNode.root(board.clone(), sideToMove: side);
    _current = _root;
    _aiThinking = false;
    _resultTick = 0;
    _hintMark = null;
    // 载入残局局面 = 一局新游戏
    _ai.notifyNewGame();
    boardChange.emit();
    if (notify) notifyListeners();
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
    _hintMark = null; // 跳转后清除提示标记
    // 跳转后走棋方恢复为目标节点的行棋方（可能已改变）
    boardChange.emit();
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
    );
  }

  bool _isAiSide(Side side) =>
      side == Side.red ? _redIsAi : _blackIsAi;

  /// 请求引擎为当前局面给出 bestmove，并根据 [autoMove] 决定处理方式。
  ///
  /// - [autoMove] 为 true：直接按 bestmove 走子，并交给
  ///   [_afterMoveApplied] 触发后续自动处理（对方为 AI 时继续应手、
  ///   胜线传播等），残局模式下黑方电脑因此能接着走；
  /// - [autoMove] 为 false：仅把 bestmove 的 from 标记到棋盘上（[hintMark]）。
  Future<void> requestHint({required bool autoMove}) async {
    if (isOver || _aiThinking) return;
    if (!atTip) return;

    _aiThinking = true;
    notifyListeners();
    var moveApplied = false;
    try {
      final fen = Fen.fromBoard(_state.board, currentSide);
      final result = await _ai.bestMove(fen, moveTimeMs: 500);
      final uci = result.move;
      if (uci == '(none)' || uci.isEmpty) return;

      final (from, to) = Fen.parseUciMove(uci);
      if (autoMove) {
        // _applyAndRecord 内部已清除提示标记
        moveApplied = _applyAndRecord(from, to);
      } else {
        _hintMark = (from, to);
        notifyListeners();
      }
    } catch (e) {
      debugPrint('提示请求失败: $e');
    } finally {
      _aiThinking = false;
      notifyListeners();
      // 先复位 _aiThinking 再触发后续处理，否则 _maybeTriggerAiMove
      // 会因思考标志被拦。仅在确实走子成功后继续。
      if (moveApplied) await _afterMoveApplied();
    }
  }

  /// 从外部（如云库面板点击着法）尝试在当前局面走 from → to。
  ///
  /// 与人类点击走子等价：合法性校验、写入棋谱树、触发后续
  /// （AI 应手 / 胜线传播）。返回 true 表示走子成功。
  bool applyMove(Position from, Position to) {
    if (isOver) return false;
    if (_aiThinking) return false;
    if (_isAiSide(currentSide)) return false;
    if (!_applyAndRecord(from, to)) return false;
    notifyListeners();
    _afterMoveApplied();
    return true;
  }

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

    _hintMark = null; // 走子后清除提示标记
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
    // 走子完成 = 走棋方改变（loadParsedGame 批量回放时的连续通知
    // 由订阅方的 FEN 门控与防抖自然合并）
    boardChange.emit();
    return true;
  }

  /// 一步棋真正走完后的统一自动处理（人类走子、AI 走子、胜线自动应手
  /// 后都调用本方法，不可在无新走子时调用——传播判定依赖"刚走的一招"）。
  ///
  /// 1. **胜线推进**：若刚走的一招与父节点所挂某条胜利线的首招一致
  ///    （坐标与走子方都匹配，无论走子方是胜方还是败方、是人还是 AI），
  ///    就把去掉首招后的剩余线路挂到当前节点，使线路沿实际招法传递；
  /// 2. **胜方自动应手**：推进后若轮到的胜方是 AI，则 AI 不请求引擎、
  ///    直接按线上的胜方应手走，并链式继续；胜方是人类时不自动走；
  /// 3. **败方 AI 跟线**：不满足胜方应手条件时，交给
  ///    [_maybeTriggerAiMove]——败方若为 AI 同样按线首招跟线（免引擎），
  ///    败方为人类则等待手动走子；无线可跟时 AI 才请求引擎思考。
  Future<void> _afterMoveApplied() async {
    if (isOver) return;
    if (!atTip) return; // 浏览历史着法时不自动走子

    final node = _current;
    final parent = node.parent;
    final record = node.move;
    if (parent != null && record != null) {
      WinLine? matched;
      for (final line in parent.winLines) {
        if (line.moves.isEmpty) continue;
        final first = line.moves.first;
        if (first.moving.side != record.side) continue;
        if (first.from != record.from || first.to != record.to) continue;
        matched = line;
        break;
      }
      if (matched != null) {
        final rest = matched.moves.sublist(1);
        // 无论是否自动应手，都先把剩余线路挂到当前节点（人类胜方之后
        // 手动走对招时，还要靠这条剩余线路继续判定与传递）。
        if (rest.isNotEmpty) {
          _attachWinLine(
            node,
            WinLine(winner: matched.winner, moves: rest),
          );
        }
        // 仅当胜方是 AI 时才自动应手；胜方为人类则等其自行走子。
        if (rest.isNotEmpty && _isAiSide(matched.winner)) {
          final reply = rest.first;
          if (reply.moving.side == matched.winner &&
              _applyAndRecord(reply.from, reply.to)) {
            notifyListeners();
            await _afterMoveApplied();
            return;
          }
        }
        // 不自动应手（胜方是人类）：败方若为 AI 会在下面按线跟线，
        // 败方为人类则等待手动走子；都无操作。
        await _maybeTriggerAiMove();
        return;
      }
    }

    await _maybeTriggerAiMove();
  }

  /// 若当前轮次属于 AI 方且处于棋谱末梢，则让其走子。
  ///
  /// 规则：AI 无论在杀线中是胜方还是败方都**跟线**——只要当前节点
  /// 挂有首招轮到本方的胜利线，就直接按线首招走，不请求引擎；人类
  /// 永远不跟线（自动走子只可能由本方法触发，人类走子走 onTap）。
  /// 无可用线时才请求引擎；引擎返回的 PV 若在本地模拟可成杀（AI 为
  /// 胜方），则把去掉首招后的胜利线路挂到走子后的节点上。
  Future<void> _maybeTriggerAiMove() async {
    if (isOver || _aiThinking) return;
    if (!atTip) return; // 浏览历史着法时不自动走子
    if (!_isAiSide(currentSide)) return;

    // AI 跟线（胜方应手或败方首招）：直接按线走，免请求引擎
    final follow = _followLineFor(currentSide);
    if (follow != null) {
      final m = follow.moves.first;
      if (_applyAndRecord(m.from, m.to)) {
        notifyListeners();
        await _afterMoveApplied();
      }
      return;
    }

    _aiThinking = true;
    _engineInfo = null; // 新一次思考：清空上一次的搜索信息
    notifyListeners();
    var moveApplied = false;
    try {
      final fen = Fen.fromBoard(_state.board, currentSide);
      final aiSide = currentSide;
      final result = await _ai.bestMove(fen, moveTimeMs: 500);
      final uci = result.move;
      if (uci == '(none)' || uci.isEmpty) {
        // 引擎未给出走法，停止本次自动走子，避免空转循环
        debugPrint('AI 未返回有效走法: $uci');
        return;
      }

      // 组装完整候选线路：以 bestmove 为首，拼上 PV 剩余招法
      final pv = result.pv;
      final List<String> lineUci;
      if (pv.isEmpty) {
        lineUci = [uci];
      } else if (pv.first == uci) {
        lineUci = pv;
      } else {
        lineUci = [uci, ...pv];
      }

      // 走子前在当前局面克隆上模拟整条 PV，确认是否构成杀线
      final win = _simulateWinLine(lineUci);

      final (from, to) = Fen.parseUciMove(uci);
      if (_applyAndRecord(from, to)) {
        moveApplied = true;
        // 仅当线路以 AI 方胜利告终时记录；去掉 AI 刚走的首招，
        // 剩余 [对方应手, 我方应手, ...] 挂到走子后的节点
        if (win != null && win.winner == aiSide && win.moves.length >= 2) {
          _attachWinLine(
            _current,
            WinLine(winner: aiSide, moves: win.moves.sublist(1)),
          );
        }
        notifyListeners();
      } else {
        // 引擎走法未通过本地规则：打印 FEN 与走法以便定位坐标/规则问题
        debugPrint('AI 走法被本地规则拒绝: $uci, $from, $to, fen=$fen');
      }
    } catch (e) {
      debugPrint('AI 走子失败: $e');
    } finally {
      _aiThinking = false;
      notifyListeners();
      // 仅在确实走子成功后，才继续后续自动处理（胜线传播/另一方 AI）
      if (moveApplied) await _afterMoveApplied();
    }
  }

  /// 在当前局面克隆上按本地规则逐步走 [uciLine]，若整条线路合法且
  /// 最终分出胜负，返回 (胜利方, 招法列表)；否则返回 null。
  ({Side winner, List<Move> moves})? _simulateWinLine(
      List<String> uciLine) {
    final sim = GameState();
    sim.restoreFrom(
      board: _state.board.clone(),
      sideToMove: currentSide,
      result: const GameResult(status: GameResultStatus.ongoing),
      history: const [],
    );
    final simEngine = GameEngine(sim);
    final moves = <Move>[];
    for (final uci in uciLine) {
      if (uci.length < 4) return null;
      final (from, to) = Fen.parseUciMove(uci);
      final piece = sim.board.pieceAt(from);
      if (piece == null || piece.side != sim.currentSide) return null;
      final captured = sim.board.pieceAt(to);
      if (!simEngine.tryMove(from, to)) return null;
      moves.add(Move(from: from, to: to, moving: piece, captured: captured));
    }
    final status = sim.result.status;
    if (status == GameResultStatus.redWins) {
      return (winner: Side.red, moves: moves);
    }
    if (status == GameResultStatus.blackWins) {
      return (winner: Side.black, moves: moves);
    }
    return null;
  }

  /// 查找当前节点上首招轮到 [side] 走的任意胜利线（不区分 [side] 在
  /// 该线中是胜方还是败方——AI 两种角色都跟线）。
  WinLine? _followLineFor(Side side) {
    for (final line in _current.winLines) {
      if (line.moves.isEmpty) continue;
      if (line.moves.first.moving.side == side) return line;
    }
    return null;
  }

  /// 向节点挂载胜利线，按胜利方+长度+首招去重。
  void _attachWinLine(NotationNode node, WinLine line) {
    final dup = node.winLines.any((l) =>
        l.winner == line.winner &&
        l.moves.length == line.moves.length &&
        l.moves.isNotEmpty &&
        l.moves.first.from == line.moves.first.from &&
        l.moves.first.to == line.moves.first.to);
    if (!dup) node.winLines.add(line);
  }

  @override
  void dispose() {
    // 引擎是跨页面共享的全局单例，不能在此关闭进程，否则再次进入打谱页
    // 时进程已死且不会被重新拉起（命令全部丢失）。
    // 只中止当前思考请求：发 stop 并丢弃待返回的 bestmove。
    _infoSub?.cancel();
    _ai.cancelSearch();
    boardChange.dispose();
    super.dispose();
  }
}
