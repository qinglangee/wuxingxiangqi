import 'dart:async';
import 'dart:math';

import '../../core/services/sound_service.dart';
import '../../domain/models/piece.dart';
import '../../domain/models/position.dart';
import '../../domain/notation/notation_node.dart';
import '../../domain/notation/parsers/parsed_game.dart';
import '../controllers/game_controller.dart';

/// 背谱阶段：选择执方 → 进行中 → 全树走完。
enum MemorizePhase { choosing, running, finished }

/// 背谱模式控制器：在 [GameController] 的棋谱树能力之上，实现「按谱背棋」。
///
/// 规则：
/// - 用户选择执红或执黑，另一方由程序控制；程序严格按棋谱树走，遇到
///   多条续着（分支）时在未走过的续着中随机选择，全部走过则任意续着；
/// - 用户走子必须与当前节点的某条棋谱续着一致，否则忽略该次走子并
///   播放 error.mp3；
/// - 走过的续着节点记入 [_walked]（棋盘上对已走过的分支打勾标记）；
/// - 走到叶节点（一条变例走完）后播放「干得不错」，随后自动回退到
///   最近的仍有未走续着的祖先节点继续；全树所有续着都走过后进入
///   [MemorizePhase.finished]，播放「恭喜」；
/// - 重开即清空进度、回到根节点，重新选择执方。
class MemorizeController extends GameController {
  MemorizeController(this._game) {
    // 背谱不使用引擎 AI：双方的程序走子都由本控制器按棋谱树驱动
    setRedAi(false, notify: false);
    setBlackAi(false, notify: false);
    // 先把棋谱载入树（停在根节点，等待用户选择执方）
    loadParsedGame(_game);
    _totalEdges = _countEdges(currentNode.root);
  }

  final ParsedGame _game;
  final Random _random = Random();

  MemorizePhase _phase = MemorizePhase.choosing;
  Side? _userSide;

  /// 已走过的续着节点集合（按对象身份区分）。
  final Set<NotationNode> _walked = Set<NotationNode>.identity();

  /// 棋谱树中续着（边）总数，用于进度展示。
  int _totalEdges = 0;

  /// 程序思考/叶末回退进行中：锁定用户输入，避免乱入。
  bool _busy = false;

  /// 控制器是否已销毁（延时回调守卫）。
  bool _disposed = false;

  /// 每走完一条叶路径（变例）自增，UI 据此播放「干得不错」。
  int _lineCompleteTick = 0;
  int get lineCompleteTick => _lineCompleteTick;

  /// 全部变例走完自增，UI 据此播放「恭喜」。
  int _allCompleteTick = 0;
  int get allCompleteTick => _allCompleteTick;

  MemorizePhase get phase => _phase;
  Side? get userSide => _userSide;
  bool get busy => _busy;

  /// 程序执棋方（未选择时为 null）。
  Side? get programSide => _userSide == null
      ? null
      : (_userSide == Side.red ? Side.black : Side.red);

  /// 当前是否轮到用户走棋。
  bool get isUserTurn =>
      _phase == MemorizePhase.running &&
      !_busy &&
      _userSide == state.currentSide;

  /// 已走续着数 / 总数。
  int get walkedCount => _walked.length;
  int get totalEdges => _totalEdges;

  /// 某续着节点是否已走过（供棋盘标记使用）。
  bool isWalked(NotationNode node) => _walked.contains(node);

  // ---- 生命周期 ----

  /// 选择执方并开始背谱。
  void start(Side side) {
    _userSide = side;
    _phase = MemorizePhase.running;
    _walked.clear();
    _busy = false;
    // 重新载入：保证从干净的根节点开始
    loadParsedGame(_game);
    notifyListeners();
    _scheduleProgramMove();
  }

  /// 重开：清空进度、回到根节点、重新提示选择执方。
  @override
  void restart() {
    _phase = MemorizePhase.choosing;
    _userSide = null;
    _walked.clear();
    _busy = false;
    loadParsedGame(_game);
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  // ---- 用户走子 ----

  /// 用户点击棋盘：仅在「进行中 + 用户回合 + 非忙」时响应。
  ///
  /// 选子/换选逻辑与对弈一致；但落点必须匹配棋谱树上的某条续着，
  /// 不匹配则取消选中并播放错误音效，盘面不发生任何变化。
  @override
  void onTap(Position pos) {
    if (_phase != MemorizePhase.running || _busy) return;
    if (state.isOver) return;
    if (_userSide != state.currentSide) return;

    final piece = state.board.pieceAt(pos);

    if (state.selected == null) {
      if (piece != null && piece.side == state.currentSide) {
        state.selected = pos;
        notifyListeners();
      }
      return;
    }
    final selected = state.selected!;
    if (selected == pos) return;
    if (piece != null && piece.side == state.currentSide) {
      state.selected = pos;
      notifyListeners();
      return;
    }

    final child = _matchChild(selected, pos);
    if (child == null) {
      // 与棋谱不一致：忽略走子、取消选中、错误提示音
      state.selected = null;
      SoundService.playError();
      notifyListeners();
      return;
    }
    state.selected = null;
    _walked.add(child);
    enterExistingChild(child);
    _afterTurn();
  }

  /// 在当前节点的续着中查找 [from]→[to] 完全一致的棋谱节点。
  NotationNode? _matchChild(Position from, Position to) {
    for (final c in currentNode.children) {
      final m = c.move;
      if (m != null && m.from == from && m.to == to) return c;
    }
    return null;
  }

  // ---- 程序走子与回退遍历 ----

  /// 一步走完后的统一推进：叶末则结束本变例，否则让程序继续应手。
  void _afterTurn() {
    if (currentNode.isTip) {
      _onLineComplete();
      return;
    }
    _scheduleProgramMove();
  }

  /// 若当前轮到程序且还有续着，延时后按棋谱随机走一步。
  void _scheduleProgramMove() {
    if (_phase != MemorizePhase.running || _disposed) return;
    if (currentNode.isTip) {
      _onLineComplete();
      return;
    }
    if (_userSide == state.currentSide) return; // 等用户走

    _busy = true;
    notifyListeners();
    Timer(const Duration(milliseconds: 450), () {
      if (_disposed || _phase != MemorizePhase.running) return;
      final node = currentNode;
      final unwalked =
          node.children.where((c) => !_walked.contains(c)).toList();
      // 优先未走过的续着；都走过（用户重走旧线时）则任意续着
      final pool = unwalked.isNotEmpty ? unwalked : node.children;
      final pick = pool[_random.nextInt(pool.length)];
      _busy = false;
      _walked.add(pick);
      enterExistingChild(pick);
      _afterTurn();
    });
  }

  /// 一条变例走到叶末：播放「干得不错」，延时后回退继续。
  void _onLineComplete() {
    _lineCompleteTick++;
    _busy = true;
    notifyListeners();
    Timer(const Duration(milliseconds: 2200), () {
      if (_disposed || _phase != MemorizePhase.running) return;
      final target = _nearestAncestorWithUnwalked(currentNode);
      if (target == null) {
        // 全树所有续着都已走过
        _phase = MemorizePhase.finished;
        _busy = false;
        state.selected = null;
        _allCompleteTick++;
        notifyListeners();
        return;
      }
      // 跳跃回退（无动画）到分支点，随后程序/用户继续
      jumpTo(target);
      _busy = false;
      notifyListeners();
      _scheduleProgramMove();
    });
  }

  /// 从 [from] 起（含自身）沿父链向上，找最近的「仍有未走过续着」的节点。
  /// 到根都没有则返回 null（全树遍历完成）。
  NotationNode? _nearestAncestorWithUnwalked(NotationNode from) {
    NotationNode? n = from;
    while (n != null) {
      for (final c in n.children) {
        if (!_walked.contains(c)) return n;
      }
      n = n.parent;
    }
    return null;
  }

  /// 统计树中续着（非根节点）总数。
  int _countEdges(NotationNode root) {
    var count = 0;
    void walk(NotationNode n) {
      count += n.children.length;
      for (final c in n.children) {
        walk(c);
      }
    }

    walk(root);
    return count;
  }
}
