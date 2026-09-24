import '../models/move.dart';
import '../models/piece.dart';

/// 一条「胜利招法线」（杀棋线路）。
///
/// 语义：从所在节点的局面开始，双方交替进行的招法序列 [moves]——
/// 第 0 招由该节点的当前轮次方走，最后一招为 [winner] 的将死招。
/// 沿此线行走必胜 [winner] 一方。
///
/// 典型消费方式（由 GameController 统一调度）：
/// - 招法命中线首招后，去掉首招的剩余线路会挂到后续节点，沿实际
///   招法持续传递；
/// - AI 无论是胜方还是败方都跟线：轮到 AI 且节点上有首招归本方的
///   线路时，直接按线走，不请求引擎；
/// - 人类永远不跟线：人类胜方需手动走出胜方应手，人类败方也手动
///   选择防守（线路只随实际招法传递记录，不替人走子）。
class WinLine {
  const WinLine({required this.winner, required this.moves});

  /// 本条线路的胜利方。
  final Side winner;

  /// 从挂载节点局面起交替进行的招法列表（末招为将死）。
  final List<Move> moves;
}
