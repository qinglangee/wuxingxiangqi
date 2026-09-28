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

/// 棋谱回放结果：起始局面、首步走子方、以及解析出的着法树坐标。
class ReplayData {
  const ReplayData({
    required this.startBoard,
    required this.startSide,
    required this.moves,
    this.rootBranches = const [],
  });

  final Board startBoard;
  final Side startSide;

  /// 主线着法坐标（与 [ParsedGame.moves] 一一对应）。
  final List<ReplayMove> moves;

  /// 起始局面的变着线坐标（与 [ParsedGame.rootBranches] 一一对应）。
  final List<List<ReplayMove>> rootBranches;
}

/// 一步回放后的着法坐标（带分支）。
class ReplayMove {
  const ReplayMove({
    required this.from,
    required this.to,
    this.branches = const [],
  });

  final Position from;
  final Position to;

  /// 从本步走完后的局面分叉出的变着线坐标（与 [ParsedMove.branches]
  /// 一一对应），递归成树。
  final List<List<ReplayMove>> branches;
}

/// 棋谱回放器：把 [ParsedGame] 在内存中逐步走一遍。
///
/// 纯领域层逻辑（不依赖 Flutter / UI），供两处复用：
/// - 首页选择棋谱后**先验证**：任一步（含分支中的着法）无法解析或不
///   符合规则即抛 [NotationParseException]，此时不跳转到打谱页；
/// - [GameController.loadParsedGame] 载入时复用解析结果构建棋谱树。
class NotationReplay {
  NotationReplay._();

  static final RegExp _uciReg = RegExp(r'^[a-i]\d[a-i]\d$');

  /// 解析起始局面并把所有着法（主线 + 全部分支线）走一遍进行校验。
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

    // 2. 递归回放主线与全部分支（分支在独立克隆的状态上校验，
    //    不影响主线进度）
    final moves = _resolveLine(game.moves, startBoard, startSide, '主线');
    final rootBranches = [
      for (var i = 0; i < game.rootBranches.length; i++)
        _resolveLine(game.rootBranches[i], startBoard, startSide, '根变着 ${i + 1}'),
    ];

    return ReplayData(
      startBoard: startBoard,
      startSide: startSide,
      moves: moves,
      rootBranches: rootBranches,
    );
  }

  /// 在 [board]/[side] 给定的局面（会被克隆，不污染调用方）上回放一条
  /// 着法线，返回每步的坐标与递归解析的分支。
  static List<ReplayMove> _resolveLine(
    List<ParsedMove> line,
    Board board,
    Side side,
    String where,
  ) {
    final state = GameState();
    final engine = GameEngine(state);
    state.restoreFrom(
      board: board.clone(),
      sideToMove: side,
      result: const GameResult(status: GameResultStatus.ongoing),
      history: const [],
    );

    final out = <ReplayMove>[];
    for (var i = 0; i < line.length; i++) {
      final text = line[i].moveText;

      // 回合标记声明的走子方应与当前实际轮次一致；不一致说明回合结构错乱
      final markedSide = line[i].side;
      if (markedSide != null && markedSide != state.currentSide) {
        throw NotationParseException(
          '$where第 ${i + 1} 步「$text」回合标记为'
          '${markedSide == Side.red ? "红方" : "黑方"}，'
          '但当前应轮到${state.currentSide == Side.red ? "红方" : "黑方"}，'
          '回合结构不正确',
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
          '$where第 ${i + 1} 步「$text」解析失败：${e.message}',
        );
      }
      if (!engine.tryMove(from, to)) {
        throw NotationParseException(
          '$where第 ${i + 1} 步着法不符合规则：$text（$from → $to）',
          cause: 'where=$where, step=$i, move=$text',
        );
      }

      // 分支从「本步走完后的局面」分叉；在克隆状态上递归校验，
      // 不影响主线继续回放
      final branches = [
        for (var k = 0; k < line[i].branches.length; k++)
          _resolveLine(
            line[i].branches[k],
            state.board,
            state.currentSide,
            '$where第 ${i + 1} 步变着 ${k + 1}',
          ),
      ];

      out.add(ReplayMove(from: from, to: to, branches: branches));
    }
    return out;
  }
}
