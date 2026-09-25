import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../domain/engine/engine_info.dart';
import '../../../../domain/engine/fen.dart';
import '../../../../domain/game/game_engine.dart';
import '../../../../domain/game/game_result.dart';
import '../../../../domain/game/game_state.dart';
import '../../../../domain/models/piece.dart';
import '../../../../domain/notation/notation_text.dart';

/// 一路 PV 中已转成中文记谱的一招。
typedef PvMove = ({Side side, String text});

/// PV 步数对控件：显示一对（红方一招 + 黑方一招，或反之）中文招法，
/// 红方文字红色、黑方文字黑色。
///
/// 哪一方在前由 [first] 自带的走子方决定——PV 首招方恒为当前行棋方，
/// 因此偶数对从当前行棋方开始，奇数对从对方开始。若该 PV 总步数为奇数，
/// 最后一对只有 [first]、[second] 为 null。
class PvPairView extends StatelessWidget {
  const PvPairView({super.key, required this.first, this.second});

  final PvMove first;
  final PvMove? second;

  Color _colorOf(Side side) =>
      side == Side.red ? AppTheme.redPiece : AppTheme.blackPiece;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: const Color(0xFFD8C69A), width: 0.6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            first.text,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: _colorOf(first.side),
            ),
          ),
          if (second != null) ...[
            const SizedBox(width: 8),
            Text(
              second!.text,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: _colorOf(second!.side),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// 引擎全部 PV 路线展示：每一路单独占一行（自动换行排列步数对），
/// 行首标注该路的 multipv 序号。
class PvLinesView extends StatelessWidget {
  const PvLinesView({super.key, required this.info});

  final EngineSearchInfo info;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final line in info.lines)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 候选序号
                  SizedBox(
                    width: 18,
                    child: Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        '${line.multipv}',
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFFB0A48A),
                        ),
                      ),
                    ),
                  ),
                  Expanded(child: _buildLine(line)),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildLine(EnginePvLine line) {
    final decoded = _decodePv(info.fen, line.moves);
    if (decoded.isEmpty) {
      // 中文回放失败的兜底：直接显示 UCI 原文
      return Text(
        line.moves.join(' '),
        style: const TextStyle(fontSize: 12, color: Color(0xFFB0A48A)),
      );
    }
    final pairs = <Widget>[];
    for (var i = 0; i < decoded.length; i += 2) {
      pairs.add(PvPairView(
        first: decoded[i],
        second: i + 1 < decoded.length ? decoded[i + 1] : null,
      ));
    }
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: pairs,
    );
  }
}

/// 从根 FEN 起按本地规则回放 UCI 招法，逐招生成中文记谱。
/// 任一招不合法即截断（引擎 PV 偶发的非法尾招不影响前面展示）。
List<PvMove> _decodePv(String fen, List<String> uciMoves) {
  final (board, startSide) = Fen.toBoard(fen);
  final state = GameState();
  state.restoreFrom(
    board: board,
    sideToMove: startSide,
    result: const GameResult(status: GameResultStatus.ongoing),
    history: const [],
  );
  final engine = GameEngine(state);

  final out = <PvMove>[];
  var side = startSide;
  for (final uci in uciMoves) {
    if (uci.length < 4) break;
    final (from, to) = Fen.parseUciMove(uci);
    final piece = state.board.pieceAt(from);
    if (piece == null || piece.side != state.currentSide) break;
    // 记谱基于走子前盘面（describe 只读，tryMove 之后盘面才改变）
    final text = NotationText.describe(state.board, from, to);
    if (!engine.tryMove(from, to)) break;
    out.add((side: side, text: text));
    side = side == Side.red ? Side.black : Side.red;
  }
  return out;
}
