import '../game/game_result.dart';
import '../models/board.dart';
import '../models/piece.dart';
import 'move_record.dart';

/// 棋谱树节点：表示一个「局面」。
///
/// - 根节点 [move] 为 null，保存初始局面。
/// - 每个子节点对应一步棋（[move]）以及走完之后的盘面快照 [board]。
/// - 同一局面下的多个 [children] 即「分支/变例」；[mainChildIndex]
///   指向当前选中的续着（前进按钮沿此索引走）。
/// - [comment] 为局面注释，步注释保存在 [MoveRecord.comment]。
///
/// 树结构让「后退后另走一步」自然形成新分支，后续可扩展分支切换 UI。
class NotationNode {
  NotationNode._({
    required this.parent,
    required this.board,
    required this.sideToMove,
    required this.result,
    this.move,
  });

  /// 创建根节点（初始局面，红先，对局进行中）。
  factory NotationNode.root(Board board) => NotationNode._(
        parent: null,
        board: board,
        sideToMove: Side.red,
        result: const GameResult(status: GameResultStatus.ongoing),
      );

  /// 到达该节点的那步棋；根节点为 null。
  final MoveRecord? move;

  /// 父节点；根节点为 null。
  final NotationNode? parent;

  /// 该节点对应的盘面快照（走子后的局面）。
  final Board board;

  /// 该局面轮到的走子方。
  final Side sideToMove;

  /// 该局面下的对局结果（终局节点记录胜负，其余为进行中）。
  final GameResult result;

  /// 后续着法（第一个通常为主变）。
  final List<NotationNode> children = [];

  /// 当前选用的续着索引，前进时沿它走；新分支产生时指向新分支。
  int mainChildIndex = 0;

  /// 局面注释（本节点局面的评注）。
  String? comment;

  bool get isRoot => parent == null;

  /// 是否为当前棋谱的末梢（没有任何续着）。
  bool get isTip => children.isEmpty;

  /// 当前选用的续着节点；无续着返回 null。
  NotationNode? get mainChild =>
      children.isEmpty ? null : children[mainChildIndex.clamp(0, children.length - 1)];

  /// 根节点为 0，每走一层 +1。红方走子的节点 depth 为奇数。
  int get depth {
    var d = 0;
    var n = this;
    while (n.parent != null) {
      d++;
      n = n.parent!;
    }
    return d;
  }

  /// 该节点对应的回合序号（红方走子为新回合），根节点为 0。
  int get moveNumber => (depth + 1) ~/ 2;

  /// 追加一个续着子节点。
  ///
  /// [selectAsMain] 为 true 时（默认），父节点的前进指针指向新分支，
  /// 这符合打谱软件「后退后另走即沿新分支前进」的习惯。
  NotationNode addChild({
    required MoveRecord move,
    required Board board,
    required Side sideToMove,
    required GameResult result,
    bool selectAsMain = true,
  }) {
    final node = NotationNode._(
      parent: this,
      move: move,
      board: board,
      sideToMove: sideToMove,
      result: result,
    );
    children.add(node);
    if (selectAsMain) mainChildIndex = children.length - 1;
    return node;
  }

  /// 从根沿「当前续着指针」到本节点的路径（含根与本节点）。
  List<NotationNode> pathFromRoot() {
    final path = <NotationNode>[];
    NotationNode? n = this;
    while (n != null) {
      path.add(n);
      n = n.parent;
    }
    return path.reversed.toList();
  }

  /// 从根沿主指针到末梢的主线节点列表（含根）。
  List<NotationNode> mainLine() {
    final line = <NotationNode>[];
    var n = root;
    line.add(n);
    while (!n.isTip) {
      n = n.mainChild!;
      line.add(n);
    }
    return line;
  }

  NotationNode get root {
    var n = this;
    while (n.parent != null) {
      n = n.parent!;
    }
    return n;
  }
}
