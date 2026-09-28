import '../../models/piece.dart';

/// 解析后的棋局（与原文件格式无关的中间表示）。
///
/// 各格式解析器（PGN / XQF / ...）都把源文件转换成此结构，
/// 然后由 [GameController.loadParsedGame] 把每步着法「回放」到
/// 内部棋谱树（[NotationNode]），并按本地规则校验每步合法性。
class ParsedGame {
  ParsedGame({
    this.info = const GameInfo(),
    this.startingFen,
    this.startingSide = Side.red,
    required this.moves,
    this.rootBranches = const [],
    this.rootComment,
  });

  /// 棋局元信息（赛事、对弈方、结果等）。
  final GameInfo info;

  /// 起始局面的 FEN；为 null 表示使用标准开局。
  final String? startingFen;

  /// 起始走子方。绝大多数对局红先，但部分让子局可能黑先。
  /// 若 [startingFen] 中包含轮次，以 FEN 为准。
  final Side startingSide;

  /// 起始局面的注释（开局评注），载入后挂在棋谱树根节点的局面注释上。
  /// XQF 中第 0 步空着法承载的备注即此；PGN 中着法区开头的 `{…}` 即此。
  final String? rootComment;

  /// 起始局面的变着：替代首着的若干条线（XQF 中首着即有多个分支、
  /// PGN 中首着之后紧跟的 RAV 变着时出现）。
  /// 主线首着为 [moves] 的第一步。
  final List<List<ParsedMove>> rootBranches;

  /// 主线着法序列（按走子顺序）。
  ///
  ///
  /// 每个元素的文本可以是：
  /// - UCI 坐标串，如 `'e3e4'`；
  /// - 中文招法，如 `'炮二平五'`（结合走子前盘面解析）。
  ///
  /// 主线分支由各步的 [ParsedMove.branches] 携带（PGN/XQF 均解析）。
  final List<ParsedMove> moves;
}

/// 棋局元信息。
class GameInfo {
  const GameInfo({
    this.event,
    this.site,
    this.date,
    this.red,
    this.black,
    this.result,
    this.opening,
    this.note,
  });

  final String? event;
  final String? site;
  final String? date;
  final String? red;
  final String? black;
  final String? result;
  final String? opening;
  final String? note;

  @override
  String toString() {
    final parts = <String>[
      if (event != null) '赛事=$event',
      if (date != null) '日期=$date',
      if (red != null && black != null) '$red vs $black',
      if (result != null) '结果=$result',
    ];
    return parts.isEmpty ? '（无元信息）' : parts.join('  ');
  }
}

/// 一步解析后的着法。
class ParsedMove {
  const ParsedMove({
    required this.moveText,
    this.side,
    this.comment,
    this.branches = const [],
    this.notation,
  });

  /// 着法文本：UCI 坐标串（如 `'e3e4'`）或中文招法（如 `'炮二平五'`）。
  final String moveText;

  /// 该步的走子方。
  ///
  /// 由 PGN 回合标记（`N.` 红 / `N...` 黑）确定；为 null 时
  /// 回放按起始轮次与上一步自动交替推断。
  final Side? side;

  /// 该步附带的注释（可选）。
  final String? comment;

  /// 从本步走完后的局面分叉出的变着线（不含主线）。
  ///
  /// 每条变着是一条着法序列（第一条即该变着的首着），序列中每步
  /// 又可带自己的 [branches]，形成递归树。PGN/XQF 解析器均产生
  /// 此字段。
  final List<List<ParsedMove>> branches;

  /// 该步的中文记谱文本（如 `'炮二平五'`），可选。
  ///
  /// 由内部棋谱树导出时填充：写 PGN 优先使用中文招法，可读性更好；
  /// 坐标类格式（XQF）仍使用 [moveText] 中的 UCI 串。解析器不产生
  /// 此字段。
  final String? notation;

  @override
  String toString() =>
      '${side == Side.red ? "红" : side == Side.black ? "黑" : ""}$moveText'
      '${comment == null ? '' : '  {$comment}'}'
      '${branches.isEmpty ? '' : '  +${branches.length}变着'}';
}
