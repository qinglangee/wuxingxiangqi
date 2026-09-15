import 'piece.dart';
import 'position.dart';

/// 一步走法：起点、终点、被吃棋子(若有)。
class Move {
  const Move({
    required this.from,
    required this.to,
    required this.moving,
    this.captured,
  });

  final Position from;
  final Position to;
  final Piece moving;
  final Piece? captured;

  bool get isCapture => captured != null;

  @override
  String toString() => '$moving $from → $to${captured != null ? " 吃$captured" : ""}';
}
