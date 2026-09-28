import '../models/piece.dart';

/// 一步局面评估（复盘分析数据）。
///
/// 每个节点（含根节点 = 起始局面）对应一条评估记录。
/// 评分均以**红方视角**归一化：正值红优，负值黑优。
class MoveEvaluation {
  const MoveEvaluation({
    required this.index,
    required this.sideToMove,
    this.cp,
    this.mate,
    required this.depth,
    this.bestMoveUci,
  });

  /// 在主线中的序号：0 = 起始局面，1 = 第一步走完后，依此类推。
  final int index;

  /// 该局面轮到的走子方。
  final Side sideToMove;

  /// 引擎评分（厘兵），红方视角：正值红优，负值黑优。
  /// 与 [mate] 互斥（有 mate 时 cp 为 null）。
  final int? cp;

  /// 杀棋步数，红方视角：正数 = 红方 N 步内将杀黑方，
  /// 负数 = 红方被将杀。普通评分时为 null。
  final int? mate;

  /// 搜索深度。
  final int depth;

  /// 引擎推荐的最佳着法（UCI），即该局面的「正着」。
  final String? bestMoveUci;

  /// 从红方视角的数值评分（用于折线图）。
  /// cp 存在时返回 cp；mate 正数返回 +100000，负数返回 -100000。
  int get redPerspectiveScore {
    if (mate != null) {
      return mate! > 0 ? 100000 : -100000;
    }
    return cp ?? 0;
  }

  /// 转为 JSON（用于 session 持久化）。
  Map<String, dynamic> toJson() => {
        'i': index,
        's': sideToMove == Side.red ? 'r' : 'b',
        if (cp != null) 'cp': cp,
        if (mate != null) 'mt': mate,
        'd': depth,
        if (bestMoveUci != null) 'bm': bestMoveUci,
      };

  factory MoveEvaluation.fromJson(Map<String, dynamic> j) => MoveEvaluation(
        index: j['i'] as int,
        sideToMove: (j['s'] as String) == 'r' ? Side.red : Side.black,
        cp: j['cp'] as int?,
        mate: j['mt'] as int?,
        depth: j['d'] as int,
        bestMoveUci: j['bm'] as String?,
      );
}

/// 一次失误着法记录。
class MoveMistake {
  const MoveMistake({
    required this.moveIndex,
    required this.side,
    required this.moveUci,
    required this.scoreBefore,
    required this.scoreAfter,
    required this.scoreLoss,
    this.bestMoveUci,
  });

  /// 失误着的序号（走完后的节点序号）。
  final int moveIndex;

  /// 失误方。
  final Side side;

  /// 失误着法 UCI。
  final String moveUci;

  /// 失误前红方视角评分。
  final int scoreBefore;

  /// 失术后红方视角评分。
  final int scoreAfter;

  /// 因失误丢的分（红方视角，正值表示红方丢分，负值表示黑方丢分）。
  final int scoreLoss;

  /// 引擎推荐的正着 UCI。
  final String? bestMoveUci;

  Map<String, dynamic> toJson() => {
        'mi': moveIndex,
        's': side == Side.red ? 'r' : 'b',
        'mu': moveUci,
        'sb': scoreBefore,
        'sa': scoreAfter,
        'sl': scoreLoss,
        if (bestMoveUci != null) 'bm': bestMoveUci,
      };

  factory MoveMistake.fromJson(Map<String, dynamic> j) => MoveMistake(
        moveIndex: j['mi'] as int,
        side: (j['s'] as String) == 'r' ? Side.red : Side.black,
        moveUci: j['mu'] as String,
        scoreBefore: j['sb'] as int,
        scoreAfter: j['sa'] as int,
        scoreLoss: j['sl'] as int,
        bestMoveUci: j['bm'] as String?,
      );
}

/// 复盘分析结果：逐局面评分 + 失误列表 + 汇总统计。
class ReviewAnalysis {
  const ReviewAnalysis({
    required this.evaluations,
    this.mistakes = const [],
    this.redOpeningScore,
    this.redMiddleScore,
    this.redEndgameScore,
    this.blackOpeningScore,
    this.blackMiddleScore,
    this.blackEndgameScore,
    this.redMissedMates = 0,
    this.blackMissedMates = 0,
    this.redMistakes = 0,
    this.blackMistakes = 0,
  });

  /// 每个局面的评估（序号 0 = 起始局面）。
  final List<MoveEvaluation> evaluations;

  /// 检测到的失误着法。
  final List<MoveMistake> mistakes;

  // ---- 汇总统计（均以红方视角；正=红优）----

  final int? redOpeningScore;
  final int? redMiddleScore;
  final int? redEndgameScore;
  final int? blackOpeningScore;
  final int? blackMiddleScore;
  final int? blackEndgameScore;
  final int redMissedMates;
  final int blackMissedMates;
  final int redMistakes;
  final int blackMistakes;

  /// 转为 JSON（用于 session 持久化）。
  Map<String, dynamic> toJson() => {
        'evals': evaluations.map((e) => e.toJson()).toList(),
        'mistakes': mistakes.map((m) => m.toJson()).toList(),
        'ro': redOpeningScore,
        'rm': redMiddleScore,
        're': redEndgameScore,
        'bo': blackOpeningScore,
        'bm': blackMiddleScore,
        'be': blackEndgameScore,
        'rmm': redMissedMates,
        'bmm': blackMissedMates,
        'rmk': redMistakes,
        'bmk': blackMistakes,
      };

  factory ReviewAnalysis.fromJson(Map<String, dynamic> j) => ReviewAnalysis(
        evaluations: (j['evals'] as List<dynamic>)
            .map((e) => MoveEvaluation.fromJson(e as Map<String, dynamic>))
            .toList(),
        mistakes: (j['mistakes'] as List<dynamic>?)
                ?.map((m) => MoveMistake.fromJson(m as Map<String, dynamic>))
                .toList() ??
            const [],
        redOpeningScore: j['ro'] as int?,
        redMiddleScore: j['rm'] as int?,
        redEndgameScore: j['re'] as int?,
        blackOpeningScore: j['bo'] as int?,
        blackMiddleScore: j['bm'] as int?,
        blackEndgameScore: j['be'] as int?,
        redMissedMates: j['rmm'] as int? ?? 0,
        blackMissedMates: j['bmm'] as int? ?? 0,
        redMistakes: j['rmk'] as int? ?? 0,
        blackMistakes: j['bmk'] as int? ?? 0,
      );
}
