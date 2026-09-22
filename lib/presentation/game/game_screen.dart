import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../canju/canju_controller.dart';
import '../controllers/game_controller.dart';
import 'result_dialog.dart';
import 'widgets/board_widget.dart';
import 'widgets/branch_marker.dart';
import 'widgets/review_panel.dart';
import 'widgets/status_bar.dart';

/// 主页面：拼装棋盘 + 状态栏 + 结束弹窗。
///
/// 布局：顶部 AI 配置 + 状态栏；中部上半为棋盘（约 1/2 高度），
/// 下半为打谱面板（棋谱注释 / 引擎 / 云库 三个标签）。
/// 残局模式下在 AI 配置行下方额外显示「上一局 / 下一局」切换条。
class GameScreen extends StatelessWidget {
  const GameScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<GameController>();
    final state = controller.state;
    // 残局模式下注入了 CanjuController；棋谱/空白模式下未注入，这里取不到。
    final canju = _tryWatchCanju(context);
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        title: Text(canju == null
            ? '打谱'
            : '${canju.library.name} · 第 ${canju.currentIndex + 1}/${canju.total} 局'),
      ),
      body: SafeArea(
        child: Column(
          children: [
            _AiConfigRow(
              controller: controller,
            ),
            if (canju != null) _CanjuBar(controller: canju),
            StatusBar(state: state, onRestart: controller.restart),
            // 上半部分：棋盘（按宽度自适应高度，不抢占下半部分空间）
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 0, vertical: 4),
              child: Center(
                child: BoardWidget(
                  board: state.board,
                  selected: state.selected,
                  hints: controller.selectedHints.toSet(),
                  onTap: controller.onTap,
                  branchMarkers: _buildBranchMarkers(controller),
                ),
              ),
            ),
            // 下半部分：三标签打谱面板（占据棋盘外剩余的全部空间）
            Expanded(
              child: ReviewPanel(controller: controller),
            ),
          ],
        ),
      ),
      // 监听结束态，触发弹窗
      floatingActionButton: const _ResultWatcher(),
    );
  }

  /// 取可选的 [CanjuController]：残局模式返回实例，其它模式返回 null。
  /// 用 try/catch 是因为 [Provider.of] 在未注册时会抛 ProviderNotFoundException。
  CanjuController? _tryWatchCanju(BuildContext context) {
    try {
      return Provider.of<CanjuController>(context, listen: true);
    } on ProviderNotFoundException {
      return null;
    }
  }

  /// 在分支点（多于一条候选续着）为每条候选分支生成一个标记（带 1-based 序号）。
  /// 单一续着或无续着时不显示任何标记。
  List<BranchMarker> _buildBranchMarkers(GameController controller) {
    final options = controller.branchOptions;
    if (options.length <= 1) return const [];
    return [
      for (var i = 0; i < options.length; i++)
        BranchMarker(
          from: options[i].move!.from,
          to: options[i].move!.to,
          label: i + 1,
        ),
    ];
  }
}

/// 残局切换条：显示当前局/总数，左右按钮切上一局/下一局。
class _CanjuBar extends StatelessWidget {
  const _CanjuBar({required this.controller});

  final CanjuController controller;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
      color: const Color(0xFFE8C988),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.skip_previous),
            onPressed: controller.canPrev ? controller.goPrev : null,
            tooltip: '上一局',
            visualDensity: VisualDensity.compact,
          ),
          Expanded(
            child: Text(
              '第 ${controller.currentIndex + 1} / ${controller.total} 局',
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: Color(0xFF5A3A1A),
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.skip_next),
            onPressed: controller.canNext ? controller.goNext : null,
            tooltip: '下一局',
            visualDensity: VisualDensity.compact,
          ),
        ],
      ),
    );
  }
}

/// AI 配置行：红方电脑 / 黑方电脑 两个 checkbox。
class _AiConfigRow extends StatelessWidget {
  const _AiConfigRow({required this.controller});

  final GameController controller;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      color: Colors.white.withValues(alpha: 0.6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Row(
            children: [
              Checkbox(
                value: controller.redIsAi,
                onChanged: (v) => controller.setRedAi(v ?? false),
              ),
              const Text('红方电脑'),
            ],
          ),
          const SizedBox(width: 16),
          Row(
            children: [
              Checkbox(
                value: controller.blackIsAi,
                onChanged: (v) => controller.setBlackAi(v ?? false),
              ),
              const Text('黑方电脑'),
            ],
          ),
          if (controller.aiThinking) ...[
            const SizedBox(width: 16),
            const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            const SizedBox(width: 6),
            const Text('电脑思考中...'),
          ],
        ],
      ),
    );
  }
}

/// 监听 controller 结束态并显示结果弹窗。
///
/// 自身不可见(返回 SizedBox.shrink)，仅用于副作用。
class _ResultWatcher extends StatefulWidget {
  const _ResultWatcher();

  @override
  State<_ResultWatcher> createState() => _ResultWatcherState();
}

class _ResultWatcherState extends State<_ResultWatcher> {
  int _lastTick = 0;

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<GameController>();
    final tick = controller.resultTick;
    if (tick != _lastTick) {
      _lastTick = tick;
      // 仅在「新走子将死」时弹窗；前进/后退浏览已记录的终局不弹
      if (controller.isOver) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          showDialog(
            context: context,
            barrierDismissible: false,
            builder: (_) => ResultDialog(
              result: controller.result,
              onRestart: () {
                controller.restart();
              },
            ),
          );
        });
      }
    }
    return const SizedBox.shrink();
  }
}
