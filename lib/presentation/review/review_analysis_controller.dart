import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../domain/engine/engine_info.dart';
import '../../../domain/engine/fen.dart';
import '../../../domain/engine/pikafish_engine.dart';
import '../../../domain/models/piece.dart';
import '../../../domain/notation/notation_node.dart';
import '../../../domain/review/review_analysis.dart';
import '../controllers/game_controller.dart';

/// 复盘分析控制器：遍历主线逐局面请求引擎评估，生成评分曲线与失误列表。
///
/// 分析流程：
/// 1. 遍历主线（根→末梢），对每个局面的 FEN 发送 `go depth N` 搜索；
/// 2. 把引擎返回的 cp/mate 归一化到红方视角（黑方走子时取反）；
/// 3. 比较相邻局面的评分变化，检测失误（分数下降超阈值）与漏杀
///    （从 mate 跌到非 mate 或 mate 步数增加）；
/// 4. 按局面序号划分开局/中局/残局阶段，汇总双各方统计。
class ReviewAnalysisController extends ChangeNotifier {
  ReviewAnalysisController(this._gc) {
    // 从 GameController 恢复上次保存的分析数据（session 恢复时设置）
    final saved = _gc.reviewAnalysis;
    if (saved != null) {
      _analysis = saved;
      _progress = 1;
      _statusText = '已加载历史分析';
    }
  }

  final GameController _gc;
  final PikafishEngine _engine = PikafishEngine.instance;

  /// 分析结果（分析完成后设置）。
  ReviewAnalysis? _analysis;
  ReviewAnalysis? get analysis => _analysis;

  /// 分析进度（0~1）。
  double _progress = 0;
  double get progress => _progress;

  /// 是否正在分析。
  bool _analyzing = false;
  bool get analyzing => _analyzing;

  /// 分析时的状态文本。
  String _statusText = '';
  String get statusText => _statusText;

  /// 失误判定阈值（厘兵）：相邻局面评分变化绝对值超过此值才算失误。
  static const int _mistakeThreshold = 100;

  /// 漏杀判定阈值：从必杀（mate）变为非必杀算漏杀。
  /// 即 scoreBefore 是 mate 且 scoreAfter 不是 mate（或 mate 步数变长）。

  /// 对当前棋谱主线逐局面进行分析。
  ///
  /// [depth] 控制搜索深度，默认 12（兼顾速度与质量）。
  /// [onProgress] 可选回调，每分析完一步调用。
  Future<void> runAnalysis({
    int depth = 12,
    void Function(int done, int total)? onProgress,
  }) async {
    if (_analyzing) return;

    final mainLine = _gc.mainLine;
    if (mainLine.isEmpty) return;

    _analyzing = true;
    _progress = 0;
    _statusText = '准备分析…';
    notifyListeners();

    final evaluations = <MoveEvaluation>[];
    final total = mainLine.length;

    // 构建历史着法列表，随遍历逐步增长
    final history = <String>[];
    final startFen = Fen.fromBoard(mainLine[0].board, mainLine[0].sideToMove);

    // 订阅 info 流，捕获每次搜索期间最后一条 info（含 cp 评分）
    EngineSearchInfo? lastInfo;
    final infoSub = _engine.infoStream.listen((info) {
      lastInfo = info;
    });

    for (var i = 0; i < total; i++) {
      if (!_analyzing) break; // 被取消

      final node = mainLine[i];
      _statusText = '分析第 ${i + 1}/$total 步…';
      lastInfo = null;

      try {
        final pos = EnginePosition(
          startFen: startFen,
          currentFen: Fen.fromBoard(node.board, node.sideToMove),
          moves: List.unmodifiable(history),
        );

        final best = await _engine.bestMove(pos, depth: depth);

        // 引擎评分以走子方视角给出，需归一化到红方视角
        final sideToMove = node.sideToMove;
        int? cp;
        int? mate;

        if (best.mate != null) {
          // mate: 走子方视角，正=走子方将杀；归一化到红方
          mate = sideToMove == Side.red ? best.mate! : -best.mate!;
        } else {
          // cp 从 info 快照取
          final info = lastInfo;
          if (info != null && info.bestLine != null) {
            final rawCp = info.bestLine!.cp ?? 0;
            cp = sideToMove == Side.red ? rawCp : -rawCp;
          } else {
            cp = 0;
          }
        }

        evaluations.add(MoveEvaluation(
          index: i,
          sideToMove: sideToMove,
          cp: cp,
          mate: mate,
          depth: depth,
          bestMoveUci: best.move != '(none)' ? best.move : null,
        ));
      } catch (e) {
        debugPrint('分析第 ${i + 1} 步失败: $e');
        evaluations.add(MoveEvaluation(
          index: i,
          sideToMove: node.sideToMove,
          cp: 0,
          depth: 0,
        ));
      }

      // 更新历史着法（当前节点的走法，供下一轮 position 命令使用）
      if (i < total - 1) {
        final next = mainLine[i + 1];
        final m = next.move;
        if (m != null) {
          history.add(Fen.moveToUci(m.from, m.to));
        }
      }

      _progress = (i + 1) / total;
      onProgress?.call(i + 1, total);
      notifyListeners();
    }

    await infoSub.cancel();

    // 被取消（或换局重置）时不产出半成品分析结果
    if (!_analyzing) return;

    // 检测失误与漏杀
    final mistakes = _detectMistakes(evaluations, mainLine);

    // 汇总统计（失误/漏杀从 mistakes 直接统计）
    final stats = _computeStats(evaluations, mistakes);

    _analysis = ReviewAnalysis(
      evaluations: evaluations,
      mistakes: mistakes,
      redOpeningScore: stats['redOpening'],
      redMiddleScore: stats['redMiddle'],
      redEndgameScore: stats['redEnd'],
      blackOpeningScore: stats['blackOpening'],
      blackMiddleScore: stats['blackMiddle'],
      blackEndgameScore: stats['blackEnd'],
      redMissedMates: stats['redMissedMates']!,
      blackMissedMates: stats['blackMissedMates']!,
      redMistakes: stats['redMistakes']!,
      blackMistakes: stats['blackMistakes']!,
    );

    _analyzing = false;
    _statusText = '分析完成';
    _progress = 1;
    // 同步到 GameController 以便会话保存时一并持久化
    _gc.reviewAnalysis = _analysis;
    notifyListeners();
  }

  /// 取消正在进行的分析。
  void cancel() {
    _analyzing = false;
    _engine.cancelSearch();
    _statusText = '已取消';
    notifyListeners();
  }

  /// 换局后重置：中止进行中的分析并清空旧棋谱的分析数据。
  ///
  /// 供「上一局/下一局/选棋」切换棋谱后调用——旧棋谱的评分曲线与
  /// 失误列表对新棋谱已失效，需要重新分析。
  void resetForNewGame() {
    if (_analyzing) {
      _analyzing = false;
      _engine.cancelSearch();
    }
    _analysis = null;
    _progress = 0;
    _statusText = '';
    notifyListeners();
  }

  /// 检测失误与漏杀。
  ///
  /// 失误：某方走完后，红方视角评分向不利方向变化超过 [_mistakeThreshold]。
  /// 漏杀：某方在 mate 态势下走完，结果不再是 mate 或 mate 步数变长。
  List<MoveMistake> _detectMistakes(
      List<MoveEvaluation> evals, List<NotationNode> mainLine) {
    final mistakes = <MoveMistake>[];

    for (var i = 1; i < evals.length; i++) {
      final before = evals[i - 1];
      final after = evals[i];
      final mover = before.sideToMove; // 谁走的这步

      final scoreBefore = before.redPerspectiveScore;
      final scoreAfter = after.redPerspectiveScore;
      final delta = scoreAfter - scoreBefore;

      // 漏杀：之前是 mate（对走子方有利），走完后不再是 mate 或步数变长
      if (before.mate != null && before.mate! > 0 && mover == before.sideToMove) {
        // 走子方有必杀，走完后
        if (after.mate == null || after.mate! <= 0) {
          // 从必杀跌到非必杀 = 漏杀
          mistakes.add(MoveMistake(
            moveIndex: i,
            side: mover,
            moveUci: _moveUciOf(mainLine, i),
            scoreBefore: scoreBefore,
            scoreAfter: scoreAfter,
            scoreLoss: (scoreBefore - scoreAfter).abs(),
            bestMoveUci: before.bestMoveUci,
          ));
          continue;
        }
      }

      // 普通失误：评分向不利方向变化超过阈值
      // 对红方来说不利 = delta < -threshold；对黑方来说不利 = delta > threshold
      final isBadForMover = mover == Side.red
          ? delta < -_mistakeThreshold
          : delta > _mistakeThreshold;

      if (isBadForMover) {
        mistakes.add(MoveMistake(
          moveIndex: i,
          side: mover,
          moveUci: _moveUciOf(mainLine, i),
          scoreBefore: scoreBefore,
          scoreAfter: scoreAfter,
          scoreLoss: delta.abs(),
          bestMoveUci: before.bestMoveUci,
        ));
      }
    }

    return mistakes;
  }

  /// 获取主线第 [index] 步的 UCI 着法。
  String _moveUciOf(List<NotationNode> mainLine, int index) {
    if (index >= mainLine.length) return '';
    final m = mainLine[index].move;
    if (m == null) return '';
    return Fen.moveToUci(m.from, m.to);
  }

  /// 按阶段汇总统计。
  ///
  /// 开局 = 前 1/3，中局 = 中 1/3，残局 = 后 1/3。
  /// 各阶段的平均评分（红方视角）。
  Map<String, dynamic> _computeStats(
      List<MoveEvaluation> evals, List<MoveMistake> mistakes) {
    if (evals.isEmpty) {
      return {
        'redOpening': null, 'redMiddle': null, 'redEnd': null,
        'blackOpening': null, 'blackMiddle': null, 'blackEnd': null,
        'redMissedMates': 0, 'blackMissedMates': 0,
        'redMistakes': 0, 'blackMistakes': 0,
      };
    }

    final n = evals.length;
    final oEnd = (n / 3).ceil();
    final mEnd = (n * 2 / 3).ceil();

    int redOSum = 0, redOCount = 0;
    int redMSum = 0, redMCount = 0;
    int redESum = 0, redECount = 0;
    int blackOSum = 0, blackOCount = 0;
    int blackMSum = 0, blackMCount = 0;
    int blackESum = 0, blackECount = 0;

    for (var i = 0; i < evals.length; i++) {
      final e = evals[i];
      final score = e.redPerspectiveScore;

      if (i < oEnd) {
        if (e.sideToMove == Side.red) {
          redOSum += score; redOCount++;
        } else {
          blackOSum -= score; blackOCount++;
        }
      } else if (i < mEnd) {
        if (e.sideToMove == Side.red) {
          redMSum += score; redMCount++;
        } else {
          blackMSum -= score; blackMCount++;
        }
      } else {
        if (e.sideToMove == Side.red) {
          redESum += score; redECount++;
        } else {
          blackESum -= score; blackECount++;
        }
      }
    }

    // 从 mistakes 统计漏杀和失误
    int redMissedMates = 0, blackMissedMates = 0;
    int redMistakes = 0, blackMistakes = 0;
    for (final m in mistakes) {
      // 漏杀 = 从 mate 跌到非 mate 的失误
      if (m.scoreBefore.abs() >= 100000 && m.scoreAfter.abs() < 100000) {
        if (m.side == Side.red) {
          redMissedMates++;
        } else {
          blackMissedMates++;
        }
      } else {
        if (m.side == Side.red) {
          redMistakes++;
        } else {
          blackMistakes++;
        }
      }
    }

    return {
      'redOpening': redOCount > 0 ? redOSum ~/ redOCount : null,
      'redMiddle': redMCount > 0 ? redMSum ~/ redMCount : null,
      'redEnd': redECount > 0 ? redESum ~/ redECount : null,
      'blackOpening': blackOCount > 0 ? blackOSum ~/ blackOCount : null,
      'blackMiddle': blackMCount > 0 ? blackMSum ~/ blackMCount : null,
      'blackEnd': blackECount > 0 ? blackESum ~/ blackECount : null,
      'redMissedMates': redMissedMates,
      'blackMissedMates': blackMissedMates,
      'redMistakes': redMistakes,
      'blackMistakes': blackMistakes,
    };
  }

  /// 设置已有分析结果（从 session 恢复时使用）。
  void setAnalysis(ReviewAnalysis data) {
    _analysis = data;
    _progress = 1;
    _analyzing = false;
    _statusText = '已加载历史分析';
    notifyListeners();
  }
}
