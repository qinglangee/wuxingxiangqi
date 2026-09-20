import '../../../../domain/models/position.dart';

/// 分支标记：在棋盘上可视化一个候选分支的走法。
///
/// 在分支点（一个局面有多条续着）时，给每条候选分支配一个 [label]，
/// 在棋盘上把 [from] → [to] 连成一线，并在两端绘制带数字的圆点。
class BranchMarker {
  const BranchMarker({
    required this.from,
    required this.to,
    required this.label,
  });

  /// 该分支走法的起点。
  final Position from;

  /// 该分支走法的终点。
  final Position to;

  /// 显示在标记上的数字（1-based）。
  final int label;
}
