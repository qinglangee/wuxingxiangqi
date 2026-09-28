import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../app/app.dart';
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
import '../settings/eval_file_dialog.dart';
import '../../core/config/config_manager.dart';
import '../../core/services/sound_service.dart';
import '../game/widgets/move_anim.dart';
import 'board_change_notifier.dart';

/// UI 控制器：选中态、点击处理、AI 走子、棋谱树记录与前进/后退导航。
class GameController extends ChangeNotifier {
  GameController()
      : _state = GameState(),
        super() {
    _root = NotationNode.root(_state.board.clone());
    _current = _root;
    // 从打谱功能条的按钮配置恢复 check button 的上次状态
    // （与 AdjustableButtonBar 的持久化同源，配置不存在时用默认值）
    final checks =
        ConfigManager.instance.buttonBarConfig('ai_config_bar')?.checked;
    _redIsAi = checks?['红AI'] ?? false;
    _blackIsAi = checks?['黑AI'] ?? false;
    _analysisOn = checks?['分析'] ?? false;
    _boardFlipped = checks?['反转'] ?? false;
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

  /// 棋谱来源文件的绝对路径（从文件打开时设置）；
  /// null 表示新对局或从残局/FEN 开始，保存时走「另存为」。
  String? _sourceFilePath;
  String? get sourceFilePath => _sourceFilePath;

  /// 最近一次载入棋谱的元信息（赛事、对弈方等），保存时写回。
  GameInfo _gameInfo = const GameInfo();

  /// 保存成功后更新来源路径（「另存为」后再次保存即覆盖新文件）。
  // ignore: use_setters_to_change_properties
  void markSavedTo(String path) => _sourceFilePath = path;

  bool _redIsAi = false;
  bool _blackIsAi = false;
  bool _aiThinking = false;

  /// 提示箭头（仅当用户点击「提示」且提示自动关闭时展示）。
  ///
  /// 值为 bestMove 的 (from, to)，在棋盘上以绿色箭头标注；
  /// 走子（[_applyAndRecord]）或跳转（[_jumpTo]）时清除。
  (Position, Position)? _hintMark;
  (Position, Position)? get hintMark => _hintMark;

  /// 单步走子动画事件：单步前进/后退看棋谱与用户走子时设置，棋盘
  /// 组件播放 300ms 直线移动动画。跳跃跳转/重开/载入时置 null。
  MoveAnimEvent? _moveAnim;
  MoveAnimEvent? get moveAnim => _moveAnim;

  /// 最近一次走子动画的预计结束时刻（含一帧调度余量）；
  /// 初始为过去时刻，表示当前没有动画在播放。
  DateTime _animEndTime = DateTime.fromMillisecondsSinceEpoch(0);

  /// 引擎无限分析开关（「分析」check button）。
  bool _analysisOn = false;
  bool get isAnalysisOn => _analysisOn;

  /// 当前局面已被「分支」功能禁止的引擎 bestmove（UCI）列表。
  /// 仅对当前局面有效，局面变化后清空。
  final List<String> _bannedMoves = [];

  /// 棋盘是否翻转（红黑上下互换）。
  bool _boardFlipped = false;
  bool get boardFlipped => _boardFlipped;

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

    if (_applyAndRecord(selected, pos, animate: true)) {
      debugPrint('人类走子: $selected → $pos');
      notifyListeners();
      _afterMoveApplied();
    } else {
      // 点击处无法走子：取消选中并播放提示音效
      _state.selected = null;
      SoundService.playAlarm();
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
    _moveAnim = null;
    _sourceFilePath = null;
    _gameInfo = const GameInfo();
    // 重开 = 一局新游戏
    _ai.notifyNewGame();
    boardChange.emit();
    notifyListeners();
    _restartAnalysisForNewPosition();
    _maybeTriggerAiMove();
  }

  /// 从外部解析结果（[ParsedGame]）载入棋谱并构建棋谱树。
  ///
  /// 流程：
  /// 1. 通过 [NotationReplay.resolve] 解析起始局面并校验每步着法
  ///    （含全部分支线；调用方通常已在跳转前验证过，[replay] 可直接
  ///    传入复用）；
  /// 2. 递归回放坐标构建棋谱树：主线挂为各节点的 children[0]，
  ///    变着线挂为其分叉节点的后续 children（不改变主线前进指针）；
  /// 3. 完成后跳回根节点，显示棋谱初始状态。
  ///
  /// 解析或规则校验失败时抛 [NotationParseException]。
  void loadParsedGame(
    ParsedGame game, {
    ReplayData? replay,
    String? sourcePath,
  }) {
    final data = replay ?? NotationReplay.resolve(game);

    _sourceFilePath = sourcePath;
    _gameInfo = game.info;

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
    _moveAnim = null;
    // 导入棋谱 = 一局新游戏
    _ai.notifyNewGame();

    // 主线 + 起始局面的变着线，递归构建整棵棋谱树
    _buildLine(_root, game.moves, data.moves, '主线');
    for (var i = 0; i < game.rootBranches.length; i++) {
      _buildLine(_root, game.rootBranches[i], data.rootBranches[i],
          '根变着 ${i + 1}');
    }

    // 回放到末尾后，跳回根节点显示初始状态
    _current = _root;
    _restoreStateFromCurrent();
    boardChange.emit();
    notifyListeners();
    _restartAnalysisForNewPosition();
  }

  /// 从 [parent] 节点局面出发，把一条着法线（含递归分支）构建到棋谱树。
  ///
  /// [coords] 为 [NotationReplay.resolve] 预先解析校验过的坐标树，
  /// 与 [line] 一一对应。分两阶段：先构建整条主线（保证主线续着总是各
  /// 节点的第 0 个孩子），再回到各步节点递归挂变着线，避免分支先于
  /// 主线续着插入而抢占前进指针。
  void _buildLine(
    NotationNode parent,
    List<ParsedMove> line,
    List<ReplayMove> coords,
    String where,
  ) {
    final created = <(NotationNode, ParsedMove, ReplayMove)>[];
    var node = parent;
    // 阶段一：主线
    for (var i = 0; i < line.length; i++) {
      // 分支递归会推进内部状态，每步前恢复到本步的出发点局面
      _current = node;
      _restoreStateFromCurrent();
      final coord = coords[i];
      if (!_applyAndRecord(coord.from, coord.to, selectAsMain: false)) {
        // 理论上不会发生（resolve 已验证），这里做防御性兜底
        throw NotationParseException(
          '$where第 ${i + 1} 步着法不符合规则：${line[i].moveText}',
        );
      }
      final child = _current;
      final comment = line[i].comment;
      if (comment != null && comment.isNotEmpty) {
        child.move?.comment = comment;
      }
      created.add((child, line[i], coord));
      node = child;
    }
    // 阶段二：在各步走完后的节点上递归构建变着线
    for (var i = 0; i < created.length; i++) {
      final (child, parsed, coord) = created[i];
      for (var k = 0; k < parsed.branches.length; k++) {
        _buildLine(
          child,
          parsed.branches[k],
          coord.branches[k],
          '$where第 ${i + 1} 步变着 ${k + 1}',
        );
      }
    }
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
    _moveAnim = null;
    _sourceFilePath = null;
    _gameInfo = const GameInfo();
    // 载入残局局面 = 一局新游戏
    _ai.notifyNewGame();
    boardChange.emit();
    if (notify) notifyListeners();
    _restartAnalysisForNewPosition();
  }

  /// 把当前整棵棋谱树（含全部分支与注释）导出为 [ParsedGame]，供保存。
  ///
  /// - 起始 FEN 取根节点盘面；首步走子方取根节点行棋方；
  /// - 主线沿各节点 mainChild 指针，其余孩子作为同位变着递归导出；
  /// - 每步同时输出 UCI 坐标与中文记谱；
  /// - 根节点 [NotationNode.comment] 作为开局评注；
  /// - 结果取主线末梢节点的胜负状态（进行中时保留载入时的原结果）。
  ParsedGame exportParsedGame() {
    final startFen = Fen.fromBoard(_root.board, _root.sideToMove);

    String? result;
    switch (_root.mainLine().last.result.status) {
      case GameResultStatus.redWins:
        result = '1-0';
      case GameResultStatus.blackWins:
        result = '0-1';
      case GameResultStatus.draw:
        result = '1/2-1/2';
      case GameResultStatus.ongoing:
        result = _gameInfo.result;
    }

    final orderedRoot = _orderedChildren(_root);
    final moves = orderedRoot.isEmpty
        ? <ParsedMove>[]
        : _exportLine(orderedRoot.first);
    final rootBranches =
        orderedRoot.skip(1).map((n) => _exportLine(n)).toList();

    return ParsedGame(
      info: GameInfo(
        event: _gameInfo.event,
        site: _gameInfo.site,
        date: _gameInfo.date,
        red: _gameInfo.red,
        black: _gameInfo.black,
        result: result,
        opening: _gameInfo.opening,
        note: _gameInfo.note,
      ),
      startingFen: startFen,
      startingSide: _root.sideToMove,
      rootComment: _root.comment,
      moves: moves,
      rootBranches: rootBranches,
    );
  }

  /// 节点的续着列表：当前主线孩子排首位，其余分支按原顺序在后。
  List<NotationNode> _orderedChildren(NotationNode node) {
    if (node.children.isEmpty) return const [];
    final mi = node.mainChildIndex.clamp(0, node.children.length - 1);
    final main = node.children[mi];
    return [
      main,
      ...node.children.where((n) => !identical(n, main)),
    ];
  }

  /// 从某着法节点起导出一条着法线（主线续着在前，分支挂在各步上）。
  List<ParsedMove> _exportLine(NotationNode first) {
    final rec = first.move!;
    final children = _orderedChildren(first);
    final branches =
        children.skip(1).map((sib) => _exportLine(sib)).toList();
    final pm = ParsedMove(
      moveText: Fen.moveToUci(rec.from, rec.to),
      side: rec.side,
      notation: rec.notation,
      comment: rec.comment,
      branches: branches,
    );
    if (children.isEmpty) return [pm];
    return [pm, ..._exportLine(children.first)];
  }

  /// 后退一步：回到上一节点并恢复盘面。导航操作不触发 AI。
  /// 单步后退播放与前进方向相反的移动动画。
  void goBack() => _jumpTo(_current.parent, animate: true, animForward: false);

  /// 前进一步：沿当前续着指针前进。单步前进播放移动动画。
  void goForward() => _jumpTo(_current.mainChild, animate: true);

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

  // ---- 棋谱编辑：删除着法 / 分支排序 ----

  /// 判断 [node] 是否为 [ancestor] 的后代（或自身）。
  bool _isDescendant(NotationNode node, NotationNode ancestor) {
    NotationNode? n = node;
    while (n != null) {
      if (identical(n, ancestor)) return true;
      n = n.parent;
    }
    return false;
  }

  /// 从父节点的 children 列表中移除 [child]，并修正 mainChildIndex。
  ///
  /// 若 [child] 是当前节点或其祖先，先把当前节点跳回 [parent]。
  /// 返回是否成功移除。
  bool _removeChild(NotationNode parent, NotationNode child) {
    final idx = parent.children.indexOf(child);
    if (idx < 0) return false;
    if (_isDescendant(_current, child)) {
      _current = parent;
      _restoreStateFromCurrent();
    }
    parent.children.removeAt(idx);
    _fixMainChildIndex(parent, removedIndex: idx);
    return true;
  }

  /// 修正父节点的 [NotationNode.mainChildIndex]：删除下标 [removedIndex]
  /// 后，若主续着在被删项之后则下标减一；主续着被删则夹紧到有效范围。
  void _fixMainChildIndex(NotationNode parent, {required int removedIndex}) {
    if (parent.children.isEmpty) {
      parent.mainChildIndex = 0;
      return;
    }
    if (removedIndex < parent.mainChildIndex) {
      parent.mainChildIndex--;
    } else if (removedIndex == parent.mainChildIndex) {
      parent.mainChildIndex =
          parent.mainChildIndex.clamp(0, parent.children.length - 1);
    }
  }

  /// 删除一着棋及其全部后代（主线续着与所有分支一起删除）。
  ///
  /// 根节点不可删。删除后若当前浏览节点落在被删子树中，自动回到
  /// 该着法的父节点局面。返回是否实际执行了删除。
  bool deleteMove(NotationNode node) {
    if (node.isRoot) return false;
    final parent = node.parent!;
    if (!_removeChild(parent, node)) return false;
    _afterTreeEdit();
    return true;
  }

  /// 删除 [parent] 的第 [index] 条续着及其全部后代（分支或主线续着）。
  ///
  /// 返回是否实际执行了删除。
  bool deleteBranch(NotationNode parent, int index) {
    if (index < 0 || index >= parent.children.length) return false;
    final child = parent.children[index];
    if (!_removeChild(parent, child)) return false;
    _afterTreeEdit();
    return true;
  }

  /// 把 [parent] 的第 [index] 条续着上移一位（与前一条交换）。
  void moveBranchUp(NotationNode parent, int index) {
    if (index <= 0 || index >= parent.children.length) return;
    _swapChildren(parent, index, index - 1);
    notifyListeners();
  }

  /// 把 [parent] 的第 [index] 条续着下移一位（与后一条交换）。
  void moveBranchDown(NotationNode parent, int index) {
    if (index < 0 || index >= parent.children.length - 1) return;
    _swapChildren(parent, index, index + 1);
    notifyListeners();
  }

  /// 交换父节点 children 列表中两项。
  ///
  /// 交换后把 [NotationNode.mainChildIndex] 置为 0：排序后排在最前的
  /// 续着即为主线，导出保存时也按此顺序输出，重新载入后顺序保持一致。
  void _swapChildren(NotationNode parent, int i, int j) {
    final tmp = parent.children[i];
    parent.children[i] = parent.children[j];
    parent.children[j] = tmp;
    parent.mainChildIndex = 0;
  }

  /// 棋谱树结构变更后的统一收尾：清提示/动画、广播局面变化、重启分析。
  void _afterTreeEdit() {
    _hintMark = null;
    _moveAnim = null;
    boardChange.emit();
    notifyListeners();
    _restartAnalysisForNewPosition();
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

  void _jumpTo(
    NotationNode? target, {
    bool animate = false,
    bool animForward = true,
  }) {
    if (target == null || _aiThinking || identical(target, _current)) return;
    final prev = _current;
    _current = target;
    _restoreStateFromCurrent();
    _hintMark = null; // 跳转后清除提示标记
    if (animate) {
      // 单步移动动画：前进播目标步（from→to），后退播被撤销步
      // （to→from，方向与前进相反）。棋子取动画结束局面中落在
      // 终点格的棋子。
      final rec = animForward ? target.move : prev.move;
      if (rec != null) {
        final landPos = animForward ? rec.to : rec.from;
        final piece = _state.board.pieceAt(landPos);
        if (piece != null) {
          _moveAnim = MoveAnimEvent(
            piece: piece,
            from: rec.from,
            to: rec.to,
            forward: animForward,
          );
        }
      }
    } else {
      // 跳跃跳转不播动画，并打断进行中的动画
      _moveAnim = null;
    }
    // 前进/后退/分支跳转时播放走子音效
    SoundService.playMove();
    // 跳转后走棋方恢复为目标节点的行棋方（可能已改变）
    boardChange.emit();
    notifyListeners();
    // 前进/后退/选点导致局面变化：分析模式下重新分析新局面。
    _restartAnalysisForNewPosition();
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

  /// 杀线走子前的停顿：保证走前至少停 300ms（模拟思考节奏）；
  /// 若上一个走子动画还没播完，则等它播完再走，使连续杀线走子的
  /// 动画依次完整播放、互不覆盖。
  Future<void> _pauseBeforeWinLineMove() async {
    var wait = const Duration(milliseconds: 300);
    final remain = _animEndTime.difference(DateTime.now());
    if (remain > wait) wait = remain;
    await Future.delayed(wait);
  }

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
    var evalInstalled = false;
    try {
      final result = await _ai.bestMove(_enginePosition(), moveTimeMs: 500);
      final uci = result.move;
      if (uci == '(none)' || uci.isEmpty) return;

      final (from, to) = Fen.parseUciMove(uci);
      if (autoMove) {
        // _applyAndRecord 内部已清除提示标记；AI 走子播放移动动画
        moveApplied = _applyAndRecord(from, to, animate: true);
      } else {
        _hintMark = (from, to);
        notifyListeners();
      }
    } on EvalFileMissingException {
      evalInstalled = await _promptEvalFile();
    } catch (e) {
      debugPrint('提示请求失败: $e');
    } finally {
      _aiThinking = false;
      notifyListeners();
      // 先复位 _aiThinking 再触发后续处理，否则 _maybeTriggerAiMove
      // 会因思考标志被拦。仅在确实走子成功后继续。
      if (moveApplied) {
        await _afterMoveApplied();
      } else if (_analysisOn && !evalInstalled) {
        // 未走子（仅标记/无结果）：恢复对当前局面的无限分析。
        await _startAnalysis();
      }
    }
    // 权重刚安装好且分析开启：在当前局面恢复分析（提示不自动补走）
    if (evalInstalled && _analysisOn) {
      await _startAnalysis();
    }
  }

  // ---- 无限分析 / 出招 / 分支 / 翻转 ----

  /// 分析模式下 PV1 前两步的箭头数据：(from, to, 走子方)。
  ///
  /// 最多两支：第 1 支为当前走子方，第 2 支为对方；UI 按红/黑着色。
  /// 仅当引擎快照对应的 FEN 与当前局面一致时才返回，防止异步错位。
  List<(Position, Position, Side)> get analysisArrows {
    if (!_analysisOn) return const [];
    final info = _engineInfo;
    if (info == null) return const [];
    final fen = Fen.fromBoard(_state.board, currentSide);
    if (info.fen != fen) return const [];
    final pv = info.bestLine?.moves;
    if (pv == null || pv.isEmpty) return const [];

    final arrows = <(Position, Position, Side)>[];
    final n = pv.length < 2 ? pv.length : 2;
    for (var i = 0; i < n; i++) {
      try {
        final (from, to) = Fen.parseUciMove(pv[i]);
        final side = i % 2 == 0 ? info.sideToMove : _opposite(info.sideToMove);
        arrows.add((from, to, side));
      } catch (_) {
        break; // 尾招非法（截断的 PV）时停止
      }
    }
    return arrows;
  }

  static Side _opposite(Side s) => s == Side.red ? Side.black : Side.red;

  /// 构造发给引擎的局面描述：初始局面（棋谱树根）FEN + 从根到当前
  /// 节点的全部历史着法（UCI）。
  ///
  /// 有历史着法时引擎据此正确处理重复局面与棋规；浏览到根节点时
  /// 着法列表为空，退化为只发当前局面 FEN。
  EnginePosition _enginePosition() {
    final path = _current.pathFromRoot(); // 含根节点
    final moves = <String>[];
    for (var i = 1; i < path.length; i++) {
      final rec = path[i].move;
      if (rec != null) {
        moves.add(Fen.moveToUci(rec.from, rec.to));
      }
    }
    return EnginePosition(
      startFen: Fen.fromBoard(_root.board, _root.sideToMove),
      currentFen: Fen.fromBoard(_state.board, currentSide),
      moves: moves,
    );
  }

  /// 切换无限分析开关。
  Future<void> setAnalysis(bool on) async {
    if (_analysisOn == on) return;
    _analysisOn = on;
    notifyListeners();
    if (on) {
      await _startAnalysis();
    } else {
      _bannedMoves.clear();
      await _ai.stopAnalysis();
    }
  }

  /// 权重文件缺失时弹出全局引导对话框；返回用户是否已成功安装。
  Future<bool> _promptEvalFile() async {
    final context = appNavigatorKey.currentContext;
    if (context == null) return false;
    return EvalFileGuideDialog.show(context);
  }

  /// 用当前局面 FEN 启动（或重启）无限分析；终局不分析。
  ///
  /// 权重文件缺失时弹出引导对话框，用户安装成功后自动重试一次。
  Future<void> _startAnalysis() async {
    if (!_analysisOn) return;
    if (isOver) {
      await _ai.stopAnalysis();
      return;
    }
    final position = _enginePosition();
    try {
      await _ai.startAnalysis(position, banMoves: _bannedMoves);
    } on EvalFileMissingException {
      if (await _promptEvalFile()) {
        try {
          await _ai.startAnalysis(position, banMoves: _bannedMoves);
        } catch (e) {
          debugPrint('权重安装后分析仍启动失败: $e');
        }
      }
    }
  }

  /// 局面变化后重启分析：清空禁着列表并用新 FEN 重新 `go infinite`。
  void _restartAnalysisForNewPosition() {
    if (!_analysisOn) return;
    _bannedMoves.clear();
    _startAnalysis();
  }

  /// 出招：让引擎立即给出 bestmove 并在棋盘上走出。
  ///
  /// 分析开启时直接 `stop` 当前无限分析（bestmove 即当前分析结论）；
  /// 未开启时发一次限时搜索。走子后分析会在新局面上自动重启。
  Future<void> playBestMove() async {
    if (isOver || _aiThinking || !atTip) return;

    _aiThinking = true;
    notifyListeners();
    var moveApplied = false;
    var evalInstalled = false;
    try {
      final uci = _analysisOn
          ? await _ai.stopAnalysis()
          : (await _ai.bestMove(_enginePosition(), moveTimeMs: 500)).move;
      if (uci == '(none)' || uci.isEmpty) {
        // 分析仍需继续（停在了当前局面）
        if (_analysisOn) await _startAnalysis();
        return;
      }
      final (from, to) = Fen.parseUciMove(uci);
      // 出招按钮的 AI 走子同样播放移动动画
      moveApplied = _applyAndRecord(from, to, animate: true);
      notifyListeners();
    } on EvalFileMissingException {
      evalInstalled = await _promptEvalFile();
    } catch (e) {
      debugPrint('出招失败: $e');
    } finally {
      _aiThinking = false;
      notifyListeners();
      if (moveApplied) {
        await _afterMoveApplied();
      } else if (_analysisOn && !evalInstalled) {
        // 走子失败：在原局面恢复分析
        await _startAnalysis();
      }
    }
    // 权重刚安装好：在当前局面恢复分析（出招不自动补走）
    if (evalInstalled && _analysisOn) {
      await _startAnalysis();
    }
  }

  /// 分支：不改变局面，停止当前搜索后把 bestmove 加入禁着列表，
  /// 重新 `go infinite banmoves ...` 让引擎给出下一手候选。
  Future<void> searchBranch() async {
    if (isOver || _aiThinking) return;
    if (!_analysisOn) {
      // 未开启分析时直接开启（首次无禁着）
      _analysisOn = true;
      notifyListeners();
    }
    // 权重尚未就绪：直接走分析启动流程（内含引导弹窗与安装后重启），
    // 避免对根本没启动的引擎空发 stop 而等待超时。
    if (!EvalFileService.isReady) {
      await _startAnalysis();
      return;
    }
    final best = await _ai.stopAnalysis();
    if (best != '(none)' &&
        best.isNotEmpty &&
        !_bannedMoves.contains(best)) {
      _bannedMoves.add(best);
    }
    await _startAnalysis();
  }

  /// 反转棋盘：红黑双方上下方向互换。
  void toggleBoardFlip() {
    _boardFlipped = !_boardFlipped;
    notifyListeners();
  }

  /// 直接设置棋盘反转状态（check button 回调用）。
  void setBoardFlipped(bool v) {
    if (_boardFlipped == v) return;
    toggleBoardFlip();
  }

  /// 从外部（如云库面板点击着法）尝试在当前局面走 from → to。
  ///
  /// 与人类点击走子等价：合法性校验、写入棋谱树、触发后续
  /// （AI 应手 / 胜线传播）。返回 true 表示走子成功。
  bool applyMove(Position from, Position to) {
    if (isOver) return false;
    if (_aiThinking) return false;
    if (_isAiSide(currentSide)) return false;
    // 与人类点击走子等价，播放移动动画
    if (!_applyAndRecord(from, to, animate: true)) return false;
    notifyListeners();
    _afterMoveApplied();
    return true;
  }

  /// 执行走法并写入棋谱树。
  ///
  /// 若当前节点已有续着（后退后另走），新走法作为分支加入，
  /// 且前进指针自动指向新分支。
  bool _applyAndRecord(Position from, Position to,
      {bool animate = false, bool selectAsMain = true}) {
    final before = _state.board.clone();
    final moving = before.pieceAt(from);
    if (moving == null) return false;

    // 记谱必须基于走子前盘面（同列多子消歧等）
    final notation = NotationText.describe(before, from, to);
    final captured = before.pieceAt(to);

    if (!_engine.tryMove(from, to)) return false;

    _hintMark = null; // 走子后清除提示标记

    // 若当前节点已存在相同起终点的续着分支，则复用已有节点，不重复添加。
    // 这样用户走出与某分支相同的着法时，直接进入该分支的既有局面，
    // 棋谱树不会出现重复节点。
    final existing = _current.children.where((c) {
      final m = c.move;
      return m != null && m.from == from && m.to == to;
    }).firstOrNull;
    if (existing != null) {
      if (selectAsMain) {
        _current.mainChildIndex = _current.children.indexOf(existing);
      }
      _current = existing;
      _restoreStateFromCurrent();
      if (animate) {
        _moveAnim = MoveAnimEvent(
          piece: moving, from: from, to: to, forward: true,
        );
        _animEndTime = DateTime.now()
            .add(kMoveAnimDuration)
            .add(kMoveAnimFrameSlack);
      }
      // 复用已有节点：终局计数不重复增加（该节点早已记录过结果）
      _playMoveSound(captured);
      boardChange.emit();
      return true;
    }

    if (animate) {
      // 单步走子动画：棋子从起点滑向终点（仅用户走子时播放，
      // AI 走子与批量回放不播）
      _moveAnim = MoveAnimEvent(piece: moving, from: from, to: to, forward: true);
      // 记录动画预计结束时刻，供杀线连续走子时依次衔接动画
      _animEndTime =
          DateTime.now().add(kMoveAnimDuration).add(kMoveAnimFrameSlack);
    }
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
      // 载入棋谱时传 false：先建主线后建分支，前进指针始终沿主线
      selectAsMain: selectAsMain,
    );
    if (_state.isOver) _resultTick++;
    _playMoveSound(captured);
    // 走子完成 = 走棋方改变（loadParsedGame 批量回放时的连续通知
    // 由订阅方的 FEN 门控与防抖自然合并）
    boardChange.emit();
    return true;
  }

  /// 根据走子结果播放对应音效：终局 > 将军 > 吃子 > 普通走子。
  void _playMoveSound(Piece? captured) {
    if (_state.isOver) {
      SoundService.playWin();
    } else if (_engine.isInCheck(_state.currentSide)) {
      // 走子后新的行棋方被将军
      SoundService.playCheck();
    } else if (captured != null) {
      SoundService.playEat();
    } else {
      SoundService.playMove();
    }
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
    // 局面已变化：分析模式下立即用新 FEN 重启无限搜索（清空禁着）。
    _restartAnalysisForNewPosition();
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
          if (reply.moving.side == matched.winner) {
            // 胜方应手不请求引擎：走棋前停顿 300ms（并等上一个走子
            // 动画播完），模拟思考节奏
            await _pauseBeforeWinLineMove();
            // 停顿期间局面可能已变（重开/跳转/终局），重新校验后再走
            if (isOver || !atTip) return;
            if (_applyAndRecord(reply.from, reply.to, animate: true)) {
              notifyListeners();
              await _afterMoveApplied();
              return;
            }
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
    // 分析模式下引擎被无限分析占用，AI 自动走子暂停（出招/手动仍可用）。
    if (_analysisOn) return;
    if (!_isAiSide(currentSide)) return;

    // AI 跟线（胜方应手或败方首招）：直接按线走，免请求引擎
    final follow = _followLineFor(currentSide);
    if (follow != null) {
      final m = follow.moves.first;
      // 跟线走棋不请求引擎：走棋前停顿 300ms（并等上一个走子
      // 动画播完），模拟思考节奏
      await _pauseBeforeWinLineMove();
      // 停顿期间局面可能已变（重开/跳转/终局），重新校验后再走
      if (isOver || _aiThinking || !atTip || _analysisOn ||
          !_isAiSide(currentSide)) {
        return;
      }
      if (_applyAndRecord(m.from, m.to, animate: true)) {
        notifyListeners();
        await _afterMoveApplied();
      }
      return;
    }

    _aiThinking = true;
    _engineInfo = null; // 新一次思考：清空上一次的搜索信息
    notifyListeners();
    var moveApplied = false;
    var evalInstalled = false;
    try {
      final aiSide = currentSide;
      final position = _enginePosition();
      final result =
          await _ai.bestMove(position, moveTimeMs: 500);
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
      // AI 引擎走子播放移动动画
      if (_applyAndRecord(from, to, animate: true)) {
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
        debugPrint(
            'AI 走法被本地规则拒绝: $uci, $from, $to, fen=${position.currentFen}');
      }
    } on EvalFileMissingException {
      // 权重缺失：弹窗引导用户安装，成功后继续本次自动走子
      evalInstalled = await _promptEvalFile();
    } catch (e) {
      debugPrint('AI 走子失败: $e');
    } finally {
      _aiThinking = false;
      notifyListeners();
      // 仅在确实走子成功后，才继续后续自动处理（胜线传播/另一方 AI）
      if (moveApplied) await _afterMoveApplied();
    }
    // 此时 _aiThinking 已在 finally 复位，递归不会被思考标志拦
    if (evalInstalled) await _maybeTriggerAiMove();
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
