import 'package:flutter/material.dart';

import '../../../../domain/engine/engine_info.dart';
import '../../../../domain/models/piece.dart';
import '../../../controllers/game_controller.dart';
import '../engine_status_bar.dart';
import '../pv_view.dart';

// ---------------------------------------------------------------------------
// 引擎标签
// ---------------------------------------------------------------------------

/// 引擎面板：引擎状态条 + 将军信息条（仅有将军时显示）+ PV 区域。
class EngineTab extends StatelessWidget {
  const EngineTab({super.key, required this.controller});

  final GameController controller;

  /// 把引擎首选线评分（走子方视角）换算为状态条需要的红方视角数据。
  EngineStatusData _toStatusData(EngineSearchInfo? info) {
    if (info == null) return const EngineStatusData();
    final best = info.bestLine;
    if (best == null) {
      return EngineStatusData(
        depth: info.depth,
        nps: info.nps,
        timeMs: info.timeMs,
      );
    }
    final side = info.sideToMove;
    final cp = best.cp;
    final mate = best.mate;
    return EngineStatusData(
      depth: info.depth,
      nps: info.nps,
      timeMs: info.timeMs,
      // 走子方为黑时，其视角评分取反即为红方视角
      cpRed: cp == null ? null : (side == Side.red ? cp : -cp),
      mateInRed: mate == null ? null : (side == Side.red ? mate : -mate),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final info = controller.engineInfo;
        return Column(
          children: [
            // 1. 引擎状态条
            EngineStatusBar(data: _toStatusData(info)),
            // 2. 将军信息条：仅当前走子方被将军时出现
            if (controller.currentInCheck) const _CheckInfoBar(),
            // 3. PV 区域
            Expanded(
              child: info == null
                  ? const Center(
                      child: Text(
                        '开启「红方电脑/黑方电脑」后，行棋时在此显示引擎分析',
                        style: TextStyle(
                          fontSize: 13,
                          color: Color(0xFFB0A48A),
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                    )
                  : PvLinesView(info: info),
            ),
          ],
        );
      },
    );
  }
}

/// 将军信息状态条：醒目橙底白字。
class _CheckInfoBar extends StatelessWidget {
  const _CheckInfoBar();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      height: 26,
      color: const Color(0xFFD84315),
      alignment: Alignment.center,
      child: const Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.warning, size: 16, color: Colors.white),
          SizedBox(width: 6),
          Text(
            '将军！',
            style: TextStyle(
              color: Colors.white,
              fontSize: 13,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// 占位标签
// ---------------------------------------------------------------------------
