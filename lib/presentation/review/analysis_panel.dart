import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../domain/models/piece.dart';
import '../../../domain/review/review_analysis.dart';
import '../controllers/game_controller.dart';
import 'review_analysis_controller.dart';
import 'score_chart.dart';

/// 复盘模块：局势 / 报告 / 失误 三个标签页。
///
/// 局势页：折线图展示每步评分，拖拽光标导航棋谱。
/// 报告页：双各方开局/中局/残局评分、漏杀与失误次数。
/// 失误页：失误着法列表，点击跳转到对应位置。
class AnalysisPanel extends StatefulWidget {
  const AnalysisPanel({
    super.key,
    required this.controller,
    required this.analysisController,
  });

  final GameController controller;
  final ReviewAnalysisController analysisController;

  @override
  State<AnalysisPanel> createState() => _AnalysisPanelState();
}

class _AnalysisPanelState extends State<AnalysisPanel>
    with SingleTickerProviderStateMixin {
  late final TabController _tab = TabController(length: 3, vsync: this);

  @override
  void dispose() {
    _tab.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.85),
        border: const Border(
          top: BorderSide(color: Color(0xFFC9B68C), width: 0.8),
        ),
      ),
      child: Column(
        children: [
          Material(
            color: const Color(0xFFF5E6C8),
            child: TabBar(
              controller: _tab,
              labelColor: AppTheme.boardLine,
              unselectedLabelColor: const Color(0xFF8B6B3D),
              indicatorColor: AppTheme.boardLine,
              indicatorSize: TabBarIndicatorSize.label,
              labelStyle:
                  const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
              tabs: const [
                Tab(text: '局势'),
                Tab(text: '报告'),
                Tab(text: '失误'),
              ],
            ),
          ),
          Expanded(
            child: TabBarView(
              controller: _tab,
              children: [
                _SituationTab(
                  controller: widget.controller,
                  analysisController: widget.analysisController,
                ),
                _ReportTab(analysis: widget.analysisController.analysis),
                _MistakesTab(
                  controller: widget.controller,
                  analysisController: widget.analysisController,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ---- 局势标签页 ----

class _SituationTab extends StatelessWidget {
  const _SituationTab({
    required this.controller,
    required this.analysisController,
  });

  final GameController controller;
  final ReviewAnalysisController analysisController;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: analysisController,
      builder: (context, _) {
        final analysis = analysisController.analysis;
        final analyzing = analysisController.analyzing;

        if (analyzing && analysis == null) {
          return _buildAnalyzingView();
        }

        if (analysis == null || analysis.evaluations.isEmpty) {
          return _buildEmptyView(context);
        }

        // 当前光标位置 = 棋谱当前节点在主线中的序号
        final mainLine = controller.mainLine;
        final currentIdx = controller.currentNode.depth;

        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 4, 8, 0),
              child: Row(
                children: [
                  Text(
                    '评分曲线',
                    style: TextStyle(
                        fontSize: 12, color: const Color(0xFF8B6B3D)),
                  ),
                  const Spacer(),
                  if (analyzing)
                    Text(
                      '${analysisController.statusText}'
                      ' (${(analysisController.progress * 100).toInt()}%)',
                      style: TextStyle(
                          fontSize: 11, color: const Color(0xFF8B6B3D)),
                    )
                  else
                    Text(
                      '深度 ${analysis.evaluations.first.depth}',
                      style: TextStyle(
                          fontSize: 11, color: const Color(0xFF8B6B3D)),
                    ),
                ],
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: ScoreChart(
                  evaluations: analysis.evaluations,
                  currentIndex: currentIdx.clamp(
                      0, analysis.evaluations.length - 1),
                  onCursorMoved: (idx) {
                    if (idx < mainLine.length) {
                      controller.jumpTo(mainLine[idx]);
                    }
                  },
                ),
              ),
            ),
            // 当前局面评分显示
            if (currentIdx < analysis.evaluations.length)
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 0, 8, 6),
                child: _ScoreBadge(
                  eval: analysis.evaluations[currentIdx],
                  moveNumber: (currentIdx + 1) ~/ 2,
                ),
              ),
          ],
        );
      },
    );
  }

  Widget _buildAnalyzingView() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const CircularProgressIndicator(strokeWidth: 3),
        const SizedBox(height: 12),
        Text(
          analysisController.statusText,
          style: const TextStyle(fontSize: 14, color: Color(0xFF8B6B3D)),
        ),
        const SizedBox(height: 8),
        LinearProgressIndicator(
          value: analysisController.progress,
          backgroundColor: const Color(0xFFE0D5B8),
          valueColor:
              const AlwaysStoppedAnimation<Color>(Color(0xFF5D4423)),
        ),
        const SizedBox(height: 16),
        OutlinedButton(
          onPressed: analysisController.cancel,
          child: const Text('取消'),
        ),
      ],
    );
  }

  Widget _buildEmptyView(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.analytics_outlined, size: 48,
              color: Color(0xFFD8C69A)),
          const SizedBox(height: 12),
          const Text('暂无分析数据',
              style: TextStyle(fontSize: 14, color: Color(0xFF8B6B3D))),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: () => analysisController.runAnalysis(),
            icon: const Icon(Icons.play_arrow),
            label: const Text('开始分析'),
          ),
        ],
      ),
    );
  }
}

/// 当前局面的评分标签。
class _ScoreBadge extends StatelessWidget {
  const _ScoreBadge({required this.eval, required this.moveNumber});

  final MoveEvaluation eval;
  final int moveNumber;

  @override
  Widget build(BuildContext context) {
    final score = eval.redPerspectiveScore;
    final isMate = eval.mate != null;
    final redAdvantage = score > 0;

    final text = isMate
        ? (eval.mate! > 0
            ? '红方${eval.mate!}步将杀'
            : '黑方${eval.mate!.abs()}步将杀')
        : (score >= 0 ? '+$score' : '$score');

    final color = redAdvantage
        ? const Color(0xFFC62828)
        : const Color(0xFF1A1A1A);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: const Color(0xFFF5E6C8),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '第 $moveNumber 回合  ',
            style: const TextStyle(fontSize: 11, color: Color(0xFF8B6B3D)),
          ),
          Text(
            text,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

// ---- 报告标签页 ----

class _ReportTab extends StatelessWidget {
  const _ReportTab({required this.analysis});

  final ReviewAnalysis? analysis;

  static const _redColor = Color(0xFFC62828);
  static const _blackColor = Color(0xFF1A1A1A);
  static const _labelColor = Color(0xFF8B6B3D);
  static const _headerColor = Color(0xFF5D4423);

  @override
  Widget build(BuildContext context) {
    if (analysis == null) {
      return const Center(child: Text('暂无报告数据',
          style: TextStyle(color: _labelColor)));
    }
    final a = analysis!;

    final rows = <TableRow>[
      // 表头
      TableRow(
        decoration: const BoxDecoration(color: Color(0xFFF5E6C8)),
        children: [
          _cell('', bold: true, color: _headerColor),
          _cell('红方', bold: true, color: _redColor, align: TextAlign.center),
          _cell('黑方', bold: true, color: _blackColor, align: TextAlign.center),
        ],
      ),
      _scoreRow('开局评分', a.redOpeningScore, a.blackOpeningScore),
      _scoreRow('中局评分', a.redMiddleScore, a.blackMiddleScore),
      _scoreRow('残局评分', a.redEndgameScore, a.blackEndgameScore),
      _countRow('漏杀次数', a.redMissedMates, a.blackMissedMates),
      _countRow('失误次数', a.redMistakes, a.blackMistakes),
    ];

    return SingleChildScrollView(
      padding: const EdgeInsets.all(12),
      child: Table(
        border: const TableBorder(
          horizontalInside: BorderSide(color: Color(0xFFE0D5B8), width: 0.5),
        ),
        columnWidths: const {
          0: FlexColumnWidth(2),
          1: FlexColumnWidth(1.5),
          2: FlexColumnWidth(1.5),
        },
        defaultVerticalAlignment: TableCellVerticalAlignment.middle,
        children: rows,
      ),
    );
  }

  /// 评分行：红方列正值标红，黑方列负值标黑（评分均为红方视角）。
  TableRow _scoreRow(String label, int? red, int? black) {
    return TableRow(
      children: [
        _cell(label, color: _labelColor),
        _cell(
          red == null ? '—' : (red >= 0 ? '+$red' : '$red'),
          align: TextAlign.center,
          color: red != null && red > 0 ? _redColor : _blackColor,
        ),
        _cell(
          black == null ? '—' : (black >= 0 ? '+$black' : '$black'),
          align: TextAlign.center,
          color: black != null && black < 0 ? _blackColor : _redColor,
        ),
      ],
    );
  }

  /// 计数行：红方列标红，黑方列标黑。
  TableRow _countRow(String label, int red, int black) {
    return TableRow(
      children: [
        _cell(label, color: _labelColor),
        _cell('$red', align: TextAlign.center, color: _redColor),
        _cell('$black', align: TextAlign.center, color: _blackColor),
      ],
    );
  }

  Widget _cell(
    String text, {
    Color color = _headerColor,
    bool bold = false,
    TextAlign align = TextAlign.left,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
      child: Text(
        text,
        textAlign: align,
        style: TextStyle(
          fontSize: 13,
          fontWeight: bold ? FontWeight.w700 : FontWeight.w600,
          color: color,
        ),
      ),
    );
  }
}

// ---- 失误标签页 ----

class _MistakesTab extends StatelessWidget {
  const _MistakesTab({
    required this.controller,
    required this.analysisController,
  });

  final GameController controller;
  final ReviewAnalysisController analysisController;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: analysisController,
      builder: (context, _) {
        final analysis = analysisController.analysis;
        if (analysis == null || analysis.mistakes.isEmpty) {
          return const Center(
            child: Text('暂无失误记录',
                style: TextStyle(color: Color(0xFF8B6B3D))),
          );
        }

        // 按失误方分组
        final redMistakes =
            analysis.mistakes.where((m) => m.side == Side.red).toList();
        final blackMistakes =
            analysis.mistakes.where((m) => m.side == Side.black).toList();

        return ListView(
          padding: const EdgeInsets.all(8),
          children: [
            if (redMistakes.isNotEmpty) ...[
              _buildMistakeGroup('红方失误', redMistakes, const Color(0xFFC62828)),
              const SizedBox(height: 8),
            ],
            if (blackMistakes.isNotEmpty)
              _buildMistakeGroup('黑方失误', blackMistakes, const Color(0xFF1A1A1A)),
          ],
        );
      },
    );
  }

  Widget _buildMistakeGroup(
      String title, List<MoveMistake> mistakes, Color color) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 4),
          child: Text(
            '$title（${mistakes.length}）',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
        ),
        for (final m in mistakes)
          _MistakeTile(
            mistake: m,
            color: color,
            onTap: () {
              final mainLine = controller.mainLine;
              if (m.moveIndex < mainLine.length) {
                controller.jumpTo(mainLine[m.moveIndex]);
              }
            },
          ),
      ],
    );
  }
}

class _MistakeTile extends StatelessWidget {
  const _MistakeTile({
    required this.mistake,
    required this.color,
    required this.onTap,
  });

  final MoveMistake mistake;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 2, horizontal: 0),
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Row(
            children: [
              Container(
                width: 4,
                height: 28,
                color: color,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '第 ${mistake.moveIndex} 步（${mistake.side == Side.red ? "红" : "黑"}）',
                      style: const TextStyle(
                          fontSize: 12, fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '失误：${mistake.moveUci}'
                      '${mistake.bestMoveUci != null ? "  正着：${mistake.bestMoveUci}" : ""}',
                      style: const TextStyle(
                          fontSize: 11, color: Color(0xFF8B6B3D)),
                    ),
                  ],
                ),
              ),
              // 丢分
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFF3E0),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '-${mistake.scoreLoss}',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: color,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
