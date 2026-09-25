import 'dart:math' as math;

import 'package:flutter/material.dart';

/// 引擎状态条所需的数据（与具体引擎无关的通用结构）。
///
/// 评分统一换算为**红方视角**：
/// - [cpRed]：厘兵值（centipawn），正值红优、负值黑优；杀棋时为 null；
/// - [mateInRed]：杀棋步数，正数 = 红方 N 步内将杀，负数 = 黑方将杀。
class EngineStatusData {
  const EngineStatusData({
    this.depth = 0,
    this.nps = 0,
    this.timeMs = 0,
    this.cpRed,
    this.mateInRed,
  });

  final int depth;
  final int nps;
  final int timeMs;
  final int? cpRed;
  final int? mateInRed;
}

/// 通用引擎状态条。
///
/// - 背景为红黑两色并列，红/黑占比随局面评分（logistic 映射）变化：
///   红优则红色占大部分，黑优则黑色占大部分；
/// - 左侧显示深度、nps、用时；右侧显示局面评分（兵值或杀棋步数）。
class EngineStatusBar extends StatelessWidget {
  const EngineStatusBar({super.key, required this.data});

  final EngineStatusData data;

  static const Color _red = Color(0xFFB71C1C);
  static const Color _black = Color(0xFF212121);

  /// 红方背景占比（0..1）。
  double get _redFraction {
    final mate = data.mateInRed;
    if (mate != null) return mate > 0 ? 0.97 : 0.03;
    final cp = data.cpRed;
    if (cp == null) return 0.5;
    // 与国际象棋通用胜率换算一致：400 厘兵 = 1 兵 ≈ 83% 占比
    return 1 / (1 + math.pow(10, -cp / 400));
  }

  String get _npsText {
    final n = data.nps;
    if (n >= 10000) return '${(n / 10000).toStringAsFixed(1)}万 nps';
    return '$n nps';
  }

  String get _timeText => '${(data.timeMs / 1000).toStringAsFixed(1)}秒';

  /// 右侧评分文本（红方视角）。
  String get _scoreText {
    final mate = data.mateInRed;
    if (mate != null) return mate > 0 ? '红杀 $mate' : '黑杀 ${-mate}';
    final cp = data.cpRed;
    if (cp == null) return '--';
    final pawns = cp / 100;
    final sign = pawns > 0 ? '+' : '';
    return '$sign${pawns.toStringAsFixed(2)}';
  }

  @override
  Widget build(BuildContext context) {
    final redF = _redFraction.clamp(0.02, 0.98);
    final redFlex = (redF * 1000).round();
    final hasInfo = data.depth > 0;

    final infoStyle = const TextStyle(
      color: Colors.white,
      fontSize: 12,
      fontWeight: FontWeight.w600,
      shadows: [Shadow(color: Colors.black54, blurRadius: 2)],
    );

    return SizedBox(
      height: 34,
      child: Stack(
        children: [
          // 红黑并列背景：宽度随评分变化
          Row(
            children: [
              Expanded(
                flex: redFlex,
                child: Container(color: _red.withValues(alpha: 0.92)),
              ),
              Expanded(
                flex: 1000 - redFlex,
                child: Container(color: _black.withValues(alpha: 0.92)),
              ),
            ],
          ),
          // 内容层：左信息、右评分
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: Row(
              children: [
                Text(hasInfo ? '深度 ${data.depth}' : '深度 -',
                    style: infoStyle),
                const SizedBox(width: 12),
                Text(hasInfo ? _npsText : 'nps -', style: infoStyle),
                const SizedBox(width: 12),
                Text(hasInfo ? _timeText : '时间 -', style: infoStyle),
                const Spacer(),
                Text(
                  _scoreText,
                  style: infoStyle.copyWith(fontSize: 14),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
