import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import 'cloud_base_controller.dart';

/// 云库面板：按评分排序的候选着法列表。
///
/// 用户点击条目即走子。数据多时支持滚动。
class CloudBasePanel extends StatelessWidget {
  const CloudBasePanel({super.key, required this.controller});

  final CloudBaseController controller;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        if (controller.loading) {
          return const Center(child: CircularProgressIndicator(strokeWidth: 2));
        }
        final error = controller.error;
        final moves = controller.moves;
        if (error != null && moves == null) {
          return Center(
            child: Text(
              error,
              style: const TextStyle(fontSize: 13, color: Color(0xFFB0A48A)),
            ),
          );
        }
        if (moves == null || moves.isEmpty) {
          return Center(
            child: Text(
              error ?? '暂无云库数据',
              style: const TextStyle(fontSize: 13, color: Color(0xFFB0A48A)),
            ),
          );
        }
        return Column(
          children: [
            // 固定表头：着法 / 分数 / 胜率 三等分
            const _CloudHeader(),
            const Divider(
              height: 1,
              color: Color(0xFFD8C69A),
            ),
            Expanded(
              child: ListView.separated(
                padding: const EdgeInsets.symmetric(vertical: 6),
                itemCount: moves.length,
                separatorBuilder: (_, _) => const Divider(
                  height: 1,
                  indent: 12,
                  endIndent: 12,
                  color: Color(0xFFE0D2B4),
                ),
                itemBuilder: (context, index) {
                  final m = moves[index];
                  return _CloudMoveTile(
                    entry: m,
                    rank: index + 1,
                    onTap: () => controller.applyMove(m),
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }
}

class _CloudHeader extends StatelessWidget {
  const _CloudHeader();

  @override
  Widget build(BuildContext context) {
    const style = TextStyle(
      fontSize: 12,
      fontWeight: FontWeight.w700,
      color: Color(0xFF8B6B3D),
    );
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      child: Row(
        children: [
          // 排名列占位（与条目对齐）
          const SizedBox(width: 22),
          const SizedBox(width: 10),
          Expanded(
            child: Text('着法', style: style, textAlign: TextAlign.center),
          ),
          Expanded(
            child: Text('分数', style: style, textAlign: TextAlign.center),
          ),
          Expanded(
            child: Text('胜率', style: style, textAlign: TextAlign.center),
          ),
        ],
      ),
    );
  }
}

class _CloudMoveTile extends StatelessWidget {
  const _CloudMoveTile({
    required this.entry,
    required this.rank,
    required this.onTap,
  });

  final CloudMoveEntry entry;
  final int rank;
  final VoidCallback onTap;

  Color get _rankColor {
    if (rank == 1) return const Color(0xFFD4AF37); // 金
    if (rank == 2) return const Color(0xFFC0C0C0); // 银
    if (rank == 3) return const Color(0xFFCD7F32); // 铜
    return const Color(0xFFB0A48A);
  }

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // 排名
            SizedBox(
              width: 22,
              child: Text(
                '$rank',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: _rankColor,
                ),
              ),
            ),
            const SizedBox(width: 10),
            // 中文招法（红方红字/黑方黑字——云库只返回一步，
            // 文字颜色按走子方决定）
            Expanded(
              child: Text(
                entry.text,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: _sideColorOfText(entry.text),
                ),
              ),
            ),
            // 评分
            Expanded(
              child: Text(
                entry.score.toString(),
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: Color(0xFF8B6B3D),
                ),
              ),
            ),
            // 胜率
            Expanded(
              child: Text(
                '${entry.winRate.toStringAsFixed(1)}%',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: _winRateColor(entry.winRate),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

Color _sideColorOfText(String text) {
  // 云库着法以当前行棋方为基准；
  // 首字符是棋子名，红方字为帅仕相兵马炮兵，黑方为将士象卒
  final first = text.isNotEmpty ? text[0] : '';
  const redChars = {'帅', '仕', '相', '马', '车', '炮', '兵'};
  const blackChars = {'将', '士', '象', '马', '车', '炮', '卒'};
  if (redChars.contains(first)) return AppTheme.redPiece;
  if (blackChars.contains(first)) return AppTheme.blackPiece;
  return const Color(0xFF8B6B3D);
}

Color _winRateColor(double rate) {
  if (rate >= 70) return const Color(0xFF2E7D32);
  if (rate >= 50) return const Color(0xFF8B6B3D);
  return const Color(0xFFB71C1C);
}
