import '../models/piece.dart';

/// 引擎一条候选变化（MultiPV 中的一路）。
class EnginePvLine {
  const EnginePvLine({
    required this.multipv,
    required this.moves,
    this.cp,
    this.mate,
  });

  /// 候选序号（1-based，1 为引擎首选）。
  final int multipv;

  /// 该路评分（厘兵值，centipawn），以搜索时走子方视角；
  /// 正值对走子方有利。mate 非 null 时无效。
  final int? cp;

  /// 杀棋步数，以搜索时走子方视角：正数 = 走子方 N 步内将杀对手，
  /// 负数 = 被将杀；普通评分时为 null。
  final int? mate;

  /// 该路 PV 的 UCI 招法列表。
  final List<String> moves;
}

/// 引擎一次搜索过程中的 info 快照（每条含 pv 的 info 行产生一个）。
class EngineSearchInfo {
  const EngineSearchInfo({
    required this.depth,
    required this.seldepth,
    required this.nps,
    required this.timeMs,
    required this.sideToMove,
    required this.fen,
    required this.lines,
  });

  final int depth;
  final int seldepth;

  /// 每秒节点数。
  final int nps;

  /// 已用搜索时间（毫秒）。
  final int timeMs;

  /// 搜索局面轮到的走子方（评分均以该方视角给出）。
  final Side sideToMove;

  /// 搜索时的起始 FEN（PV 回放/中文记谱需要根局面）。
  final String fen;

  /// 当前各路候选（按 multipv 排序，至少 1 路）。
  final List<EnginePvLine> lines;

  /// 首选变化（multipv 1）；无线路时返回 null。
  EnginePvLine? get bestLine =>
      lines.isEmpty ? null : lines.firstWhere((l) => l.multipv == 1);
}
