import '../../engine/fen.dart';
import '../../game/game_engine.dart';
import '../../game/game_result.dart';
import '../../game/game_state.dart';
import '../../models/board.dart';
import '../../models/piece.dart';
import '../../models/position.dart';
import '../chinese_notation.dart';
import 'notation_exception.dart';
import 'parsed_game.dart';

/// 棋谱回放结果：起始局面、首步走子方、以及解析出的每步坐标。
class ReplayData {
  const ReplayData({
    required this.startBoard,
    required this.startSide,
    required this.moves,
  });

  final Board startBoard;
  final Side startSide;
  final List<(Position, Position)> moves;
}

/// 棋谱回放器：把 [ParsedGame] 在内存中逐步走一遍。
///
/// 纯领域层逻辑（不依赖 Flutter / UI），供两处复用：
/// - 首页选择棋谱后**先验证**：任一步无法解析或不符合规则即抛
///   [NotationParseException]，此时不跳转到打谱页；
/// - [GameController.loadParsedGame] 载入时复用解析结果构建棋谱树。
class NotationReplay {
  NotationReplay._();

  static final RegExp _uciReg = RegExp(r'^[a-i]\d[a-i]\d$');

  /// 解析起始局面并把所有着法走一遍进行校验。
  ///
  /// 失败时抛 [NotationParseException]，message 可直接展示给用户。
  static ReplayData resolve(ParsedGame game) {
    // 1. 起始局面
    final Board startBoard;
    final Side startSide;
    final fen = game.startingFen?.trim();
    if (fen != null && fen.isNotEmpty) {
      try {
        final (b, s) = Fen.toBoard(fen);
        startBoard = b;
        startSide = s;
      } on FormatException catch (e) {
        throw NotationParseException('起始 FEN 无效：${e.message}');
      }
    } else {
      startBoard = Board()..resetToInitial();
      startSide = game.startingSide;
    }

    // 2. 在临时状态上逐步回放
    final state = GameState();
    final engine = GameEngine(state);
    state.restoreFrom(
      board: startBoard,
      sideToMove: startSide,
      result: const GameResult(status: GameResultStatus.ongoing),
      history: const [],
    );

    final coords = <(Position, Position)>[];
    for (var i = 0; i < game.moves.length; i++) {
      final text = game.moves[i].moveText;

      // 回合标记声明的走子方应与当前实际轮次一致；不一致说明回合结构错乱
      final markedSide = game.moves[i].side;
      if (markedSide != null && markedSide != state.currentSide) {
        throw NotationParseException(
          '第 ${i + 1} 步「$text」回合标记为${markedSide == Side.red ? "红方" : "黑方"}，'
          '但当前应轮到${state.currentSide == Side.red ? "红方" : "黑方"}，回合结构不正确',
        );
      }

      Position from;
      Position to;
      try {
        if (_uciReg.hasMatch(text)) {
          (from, to) = Fen.parseUciMove(text);
        } else {
          (from, to) =
              ChineseNotation.parse(state.board, state.currentSide, text);
        }
      } on FormatException catch (e) {
        throw NotationParseException(
          '第 ${i + 1} 步「$text」解析失败：${e.message}',
        );
      }
      if (!engine.tryMove(from, to)) {
        throw NotationParseException(
          '第 ${i + 1} 步着法不符合规则：$text（$from → $to）',
          cause: 'step=$i, move=$text',
        );
      }
      coords.add((from, to));
    }

    return ReplayData(
      startBoard: startBoard,
      startSide: startSide,
      moves: coords,
    );
  }
}
