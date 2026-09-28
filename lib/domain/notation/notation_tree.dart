import '../engine/fen.dart';
import '../game/game_engine.dart';
import '../game/game_result.dart';
import '../game/game_state.dart';
import 'move_record.dart';
import 'notation_node.dart';
import 'notation_text.dart';
import 'parsers/notation_replay.dart';
import 'parsers/parsed_game.dart';

/// 棋谱节点树（[NotationNode]）的构建、导出与合并工具（纯领域层）。
///
/// 合谱功能的核心：
/// - [build]：把一份 [ParsedGame]（经 [NotationReplay] 校验）构建成独立
///   的节点树，不依赖 GameController / UI；
/// - [merge]：把「新树」合并进「主树」——逐节点比对着法起终点，相同
///   着法复用已有节点（注释合并），不同着法整条子树作为新分支挂入；
/// - [export]：把合并后的节点树导出回 [ParsedGame] 供序列化保存。
class NotationTree {
  NotationTree._();

  /// 由 [ParsedGame] 构建一棵独立节点树（先走子为续着 0，即主线）。
  ///
  /// 构建前通过 [NotationReplay.resolve] 校验起始局面与每步合法性；
  /// 任一着法非法会抛 NotationParseException。已做过回放校验时可把
  /// [replay] 结果传入复用，避免重复回放。
  static NotationNode build(ParsedGame game, [ReplayData? replay]) {
    final data = replay ?? NotationReplay.resolve(game);
    final root = NotationNode.root(
      data.startBoard.clone(),
      sideToMove: data.startSide,
    );
    root.comment = game.rootComment;

    final mainState = GameState();
    mainState.restoreFrom(
      board: data.startBoard,
      sideToMove: data.startSide,
      result: const GameResult(status: GameResultStatus.ongoing),
      history: const [],
    );
    _buildLine(
      root,
      game.moves,
      data.moves,
      mainState,
      GameEngine(mainState),
    );

    // 起始局面的变着线：各自从初始局面克隆状态独立构建
    for (var i = 0; i < game.rootBranches.length; i++) {
      final s = GameState();
      s.restoreFrom(
        board: data.startBoard.clone(),
        sideToMove: data.startSide,
        result: const GameResult(status: GameResultStatus.ongoing),
        history: const [],
      );
      _buildLine(
        root,
        game.rootBranches[i],
        data.rootBranches[i],
        s,
        GameEngine(s),
      );
    }
    return root;
  }

  /// 把一条着法线（含递归分支）构建为 [parent] 的子树。
  ///
  /// 分两阶段：先沿 [state] 把整条主线走完（保证主线续着总是每个节点的
  /// 第 0 个孩子），再回到各步节点，从其局面快照克隆状态递归构建分支，
  /// 分支之间、分支与主线互不影响。
  static void _buildLine(
    NotationNode parent,
    List<ParsedMove> line,
    List<ReplayMove> coords,
    GameState state,
    GameEngine engine,
  ) {
    // 阶段一：构建主线，记录每个新建节点与其解析/坐标数据
    final built = <(NotationNode, ParsedMove, ReplayMove)>[];
    var node = parent;
    for (var i = 0; i < line.length; i++) {
      final coord = coords[i];
      final before = state.board.clone();
      final moving = before.pieceAt(coord.from);
      if (moving == null) {
        throw StateError('构建棋谱树时起点无棋子（回放校验应已拦截）');
      }
      final captured = before.pieceAt(coord.to);
      final notation = NotationText.describe(before, coord.from, coord.to);
      if (!engine.tryMove(coord.from, coord.to)) {
        throw StateError('构建棋谱树时走子失败（回放校验应已拦截）');
      }
      final child = node.addChild(
        move: MoveRecord(
          from: coord.from,
          to: coord.to,
          moving: moving,
          side: moving.side,
          notation: notation,
          captured: captured,
          comment: line[i].comment,
        ),
        board: state.board.clone(),
        sideToMove: state.currentSide,
        result: state.result,
        // 主线先行，续着 0 即主线；分支后挂不改变前进指针
        selectAsMain: false,
      );
      built.add((child, line[i], coord));
      node = child;
    }

    // 阶段二：在各步走完后的节点上递归挂变着线（从节点局面快照克隆）
    for (final (child, parsed, coord) in built) {
      for (var k = 0; k < parsed.branches.length; k++) {
        final s = GameState();
        s.restoreFrom(
          board: child.board.clone(),
          sideToMove: child.sideToMove,
          result: const GameResult(status: GameResultStatus.ongoing),
          history: const [],
        );
        _buildLine(
          child,
          parsed.branches[k],
          coord.branches[k],
          s,
          GameEngine(s),
        );
      }
    }
  }

  /// 把 [incoming] 新树合并进 [target] 主树。
  ///
  /// 对新树每个节点的续着，在主树同位节点的续着中查找起终点完全相同
  /// 的着法：找到则复用该节点（注释合并）并继续递归；找不到则把整条
  /// 子树深拷贝后作为新分支挂到主树上。两棵树的根局面必须相同
  /// （起始 FEN 一致），由调用方保证。
  static void merge(NotationNode target, NotationNode incoming) {
    target.comment = _mergeComment(target.comment, incoming.comment);
    for (final inChild in incoming.children) {
      final inMove = inChild.move;
      NotationNode? match;
      for (final c in target.children) {
        final m = c.move;
        if (m != null &&
            inMove != null &&
            m.from == inMove.from &&
            m.to == inMove.to) {
          match = c;
          break;
        }
      }
      if (match != null) {
        // 同一着法：步注释合并后继续向下合并
        match.move!.comment =
            _mergeComment(match.move!.comment, inChild.move!.comment);
        merge(match, inChild);
      } else {
        // 新着法：整条子树作为分支挂入（不改变主线指针）
        _copySubtree(target, inChild);
      }
    }
  }

  /// 把 [src] 节点（及其整棵子树）深拷贝为 [parent] 的新续着。
  static NotationNode _copySubtree(NotationNode parent, NotationNode src) {
    final rec = src.move;
    final node = parent.addChild(
      move: rec == null
          ? throw StateError('待拷贝的续着节点没有走子记录')
          : _copyRecord(rec),
      board: src.board.clone(),
      sideToMove: src.sideToMove,
      result: src.result,
      selectAsMain: false,
    );
    node.comment = src.comment;
    for (final c in src.children) {
      _copySubtree(node, c);
    }
    return node;
  }

  /// 复制走子记录（注释一并复制）。
  static MoveRecord _copyRecord(MoveRecord r) => MoveRecord(
        from: r.from,
        to: r.to,
        moving: r.moving,
        side: r.side,
        notation: r.notation,
        captured: r.captured,
        comment: r.comment,
      );

  /// 合并两段注释：任一为空取另一个；内容相同不重复；不同则换行拼接。
  static String? _mergeComment(String? a, String? b) {
    final ta = a?.trim();
    final tb = b?.trim();
    if (ta == null || ta.isEmpty) return tb?.isEmpty ?? true ? a : tb;
    if (tb == null || tb.isEmpty) return ta;
    if (ta == tb) return ta;
    return '$ta\n$tb';
  }

  /// 节点的续着列表：当前主线孩子排首位，其余分支按原顺序在后。
  static List<NotationNode> _orderedChildren(NotationNode node) {
    if (node.children.isEmpty) return const [];
    final mi = node.mainChildIndex.clamp(0, node.children.length - 1);
    final main = node.children[mi];
    return [
      main,
      ...node.children.where((n) => !identical(n, main)),
    ];
  }

  /// 把节点树导出为 [ParsedGame]（含全部分支与注释）。
  ///
  /// [info] 为棋局元信息；结果标记取主线末梢的胜负状态，进行中时
  /// 保留 [info] 中已有的结果。
  static ParsedGame export(
    NotationNode root, {
    GameInfo info = const GameInfo(),
  }) {
    final startFen = Fen.fromBoard(root.board, root.sideToMove);

    String? result;
    switch (root.mainLine().last.result.status) {
      case GameResultStatus.redWins:
        result = '1-0';
      case GameResultStatus.blackWins:
        result = '0-1';
      case GameResultStatus.draw:
        result = '1/2-1/2';
      case GameResultStatus.ongoing:
        result = info.result;
    }

    final ordered = _orderedChildren(root);
    final moves =
        ordered.isEmpty ? <ParsedMove>[] : _exportLine(ordered.first);
    final rootBranches =
        ordered.skip(1).map((n) => _exportLine(n)).toList();

    return ParsedGame(
      info: GameInfo(
        event: info.event,
        site: info.site,
        date: info.date,
        red: info.red,
        black: info.black,
        result: result,
        opening: info.opening,
        note: info.note,
      ),
      startingFen: startFen,
      startingSide: root.sideToMove,
      rootComment: root.comment,
      moves: moves,
      rootBranches: rootBranches,
    );
  }

  /// 从某着法节点起导出一条着法线（主线续着在前，分支挂在各步上）。
  static List<ParsedMove> _exportLine(NotationNode first) {
    final rec = first.move!;
    final children = _orderedChildren(first);
    final branches = children.skip(1).map((sib) => _exportLine(sib)).toList();
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
}
