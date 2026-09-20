import '../models/piece.dart';
import '../models/position.dart';

/// 一步棋的完整记录（棋谱树边上的数据）。
///
/// 不可变部分描述走法本身；[comment]、[extras] 可变，供后续注释、
/// 评注、标记（好棋/坏棋）、引擎评分等功能扩展。
class MoveRecord {
  MoveRecord({
    required this.from,
    required this.to,
    required this.moving,
    required this.side,
    required this.notation,
    this.captured,
    this.comment,
    Map<String, Object?>? extras,
  }) : extras = extras ?? <String, Object?>{};

  /// 起点。
  final Position from;

  /// 终点。
  final Position to;

  /// 走动的棋子。
  final Piece moving;

  /// 走子方。
  final Side side;

  /// 中文记谱文本，如「炮二平五」「马8进7」。
  final String notation;

  /// 被吃掉的棋子（若有）。
  final Piece? captured;

  /// 该步棋的文字注释（可后续编辑）。
  String? comment;

  /// 其它扩展信息：引擎评分、着法标记（!/??）、变例名称等。
  final Map<String, Object?> extras;

  bool get isCapture => captured != null;

  @override
  String toString() => notation;
}
