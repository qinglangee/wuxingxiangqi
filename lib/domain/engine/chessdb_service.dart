import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../engine/fen.dart';
import '../models/position.dart';
import '../notation/notation_text.dart';

/// 云库（ChessDB）返回的一条候选着法。
class CloudMove {
  const CloudMove({
    required this.uci,
    required this.score,
    required this.winRate,
    required this.rank,
  });

  /// UCI 着法（如 "h2e2"）。
  final String uci;

  /// 评分（与红方视角无关，ChessDB 返回原始值；通常为千分比或概率 ×100）。
  final int score;

  /// 胜率（ChessDB 返回的百分比，0..100 或 0..1）。
  final double winRate;

  /// 云库中的排名（1-based，越小越优）。
  final int rank;
}

/// 解析后的云库结果：已按评分排序，并已转成中文记谱。
class CloudResult {
  const CloudResult({
    required this.moves,
    required this.isTerminal,
    required this.message,
  });

  /// 候选着法列表，按评分降序。
  final List<CloudMove> moves;

  /// 是否为终局（unknown / nobestmove / draw / win / loss）。
  final bool isTerminal;

  /// 附加说明文本（如 "invalid board"）。
  final String? message;
}

/// ChessDB 象棋云库服务。
///
/// 通过 `queryall` 接口查询当前局面的候选着法、评分与胜率。
/// 评分以走子方视角返回，已按评分降序排列。
class ChessDbService {
  ChessDbService._();

  static const String _base = 'https://www.chessdb.cn/chessdb.php?action=queryall';

  /// 请求云库。返回 null 表示网络错误或服务不可用。
  static Future<CloudResult?> query(String fen) async {
    try {
      // 保留 _base 中原有的 action=queryall，再追加 board 参数
      final uri = Uri.parse(_base).replace(queryParameters: {
        ...Uri.parse(_base).queryParameters,
        'board': fen,
      });
      final client = HttpClient();
      client.connectionTimeout = const Duration(seconds: 8);
      final request = await client.getUrl(uri);
      final response = await request.close().timeout(
        const Duration(seconds: 12),
        onTimeout: () => throw TimeoutException('云库请求超时'),
      );
      final body = await response.transform(utf8.decoder).join();
      return _parseBody(body);
    } on Exception {
      return null;
    }
  }

  /// 解析 ChessDB 响应体。
  ///
  /// 正常返回（竖线分隔，字段顺序不定）：
  /// ```
  /// move:c3c4,score:1,rank:2,note:! (44-02),winrate:50.08|move:g3g4,score:1,rank:2,note:! (44-02),winrate:50.08
  /// ```
  /// 终局/异常：
  /// ```
  /// unknown          // 局面不在库中
  /// nobestmove       // 无合法着法
  /// draw             // 和棋
  /// win              // 当前走子方胜（将军杀）
  /// loss             // 当前走子方负
  /// invalid board    // FEN 非法
  /// ```
  static CloudResult _parseBody(String body) {
    final trimmed = body.trim();
    if (trimmed.isEmpty) {
      return const CloudResult(moves: [], isTerminal: false, message: null);
    }

    final lower = trimmed.toLowerCase();
    if (lower.startsWith('unknown')) {
      return const CloudResult(moves: [], isTerminal: true, message: '局面不在库中');
    }
    if (lower.startsWith('nobestmove')) {
      return const CloudResult(moves: [], isTerminal: true, message: '无合法着法');
    }
    if (lower.startsWith('draw')) {
      return const CloudResult(moves: [], isTerminal: true, message: '和棋');
    }
    if (lower.startsWith('win')) {
      return const CloudResult(moves: [], isTerminal: true, message: '当前走子方胜');
    }
    if (lower.startsWith('loss')) {
      return const CloudResult(moves: [], isTerminal: true, message: '当前走子方负');
    }
    if (lower.startsWith('invalid')) {
      return const CloudResult(moves: [], isTerminal: true, message: '局面非法');
    }

    // 正常候选着法：按竖线分隔
    final lines = trimmed.split('|');
    final moves = <CloudMove>[];
    for (final line in lines) {
      // 按字段名提取，兼容任意字段顺序和 note 中的特殊字符
      final moveMatch = RegExp(r'move:([a-i]\d[a-i]\d)').firstMatch(line);
      final scoreMatch = RegExp(r'score:(-?\d+)').firstMatch(line);
      final rankMatch = RegExp(r'rank:(\d+)').firstMatch(line);
      final winrateMatch = RegExp(r'winrate:([\d.]+)').firstMatch(line);
      if (moveMatch == null) continue;
      moves.add(CloudMove(
        uci: moveMatch.group(1)!,
        score: scoreMatch != null ? int.tryParse(scoreMatch.group(1)!) ?? 0 : 0,
        winRate: winrateMatch != null ? double.tryParse(winrateMatch.group(1)!) ?? 0 : 0,
        rank: rankMatch != null ? int.tryParse(rankMatch.group(1)!) ?? 0 : 0,
      ));
    }
    // 按云库排名升序（rank 1 最优）
    moves.sort((a, b) => b.rank.compareTo(a.rank));
    return CloudResult(moves: moves, isTerminal: false, message: null);
  }
}

/// 便捷函数：对每条云库着法生成中文记谱（每步独立计算，不推进局面）。
List<({String text, Position from, Position to})> describeCloudMoves(
  String fen,
  List<CloudMove> moves,
) {
  final (board, startSide) = Fen.toBoard(fen);
  final out = <({String text, Position from, Position to})>[];
  for (final m in moves) {
    if (m.uci.length < 4) continue;
    final (from, to) = Fen.parseUciMove(m.uci);
    final piece = board.pieceAt(from);
    if (piece == null || piece.side != startSide) continue;
    final text = NotationText.describe(board, from, to);
    out.add((text: text, from: from, to: to));
  }
  return out;
}
