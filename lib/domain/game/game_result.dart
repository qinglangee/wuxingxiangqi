import '../models/piece.dart';

/// 游戏结果。
enum GameResultStatus {
  ongoing,    // 进行中
  redWins,    // 红胜
  blackWins,  // 黑胜
  draw,       // 和棋
}

/// 不可变游戏结果。
class GameResult {
  const GameResult({required this.status, this.reason});

  final GameResultStatus status;
  final String? reason;

  bool get isOver => status != GameResultStatus.ongoing;

  @override
  String toString() {
    final who = switch (status) {
      GameResultStatus.redWins => '红方胜',
      GameResultStatus.blackWins => '黑方胜',
      GameResultStatus.draw => '和棋',
      GameResultStatus.ongoing => '进行中',
    };
    return '$who${reason != null ? "($reason)" : ""}';
  }

  /// 哪方获胜，返回阵营；进行中/和棋返回 null。
  Side? get winner => switch (status) {
        GameResultStatus.redWins => Side.red,
        GameResultStatus.blackWins => Side.black,
        _ => null,
      };
}
