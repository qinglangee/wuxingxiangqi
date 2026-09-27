import '../../../domain/models/piece.dart';
import '../../../domain/models/position.dart';

/// 单步走子动画时长。
const Duration kMoveAnimDuration = Duration(milliseconds: 300);

/// 帧调度余量：动画事件发出后要到下一帧才真正开始播放，
/// 控制器据此推算动画的实际结束时刻。
const Duration kMoveAnimFrameSlack = Duration(milliseconds: 20);

/// 棋盘单步走子动画事件。
///
/// 由控制器在单步前进/后退/用户走子时创建；棋盘组件检测到新事件
/// 后播放 300ms 的直线移动动画。跳跃式跳转（点选任意棋谱节点、
/// 分支跳转等）不产生该事件。
class MoveAnimEvent {
  MoveAnimEvent({
    required this.piece,
    required this.from,
    required this.to,
    required this.forward,
  });

  /// 移动的棋子（取自动画结束局面中落在终点格的棋子）。
  final Piece piece;

  /// 该步棋的起点。
  final Position from;

  /// 该步棋的终点。
  final Position to;

  /// true=前进：棋子从 from 滑到 to；false=后退：棋子从 to 滑回 from
  /// （与前进方向相反）。
  final bool forward;
}
