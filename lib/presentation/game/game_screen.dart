import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

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
class GameScreen extends StatelessWidget {
  const GameScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<GameController>();
    final state = controller.state;
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        title: const Text('打谱'),
      ),
      body: SafeArea(
        child: Column(
          children: [
            _AiConfigRow(
              controller: controller,
            ),
            StatusBar(state: state, onRestart: controller.restart),
            // 上半部分：棋盘（按宽度自适应高度，不抢占下半部分空间）
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
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
      floatingActionButton: Stack(
        children: const [
          _ResultWatcher(),
          _BranchDialogWatcher(),
        ],
      ),
    );
  }

  /// 在分支点为每条候选分支生成一个标记（带 1-based 序号）。
  List<BranchMarker> _buildBranchMarkers(GameController controller) {
    final options = controller.branchOptions;
    if (options.isEmpty) return const [];
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

/// 监听 controller 当前节点变化，到达分支点时弹出分支选择框。
///
/// 同一分支节点只弹一次（用 depth 记忆），避免热重载或重复 notify 时反复弹出。
class _BranchDialogWatcher extends StatefulWidget {
  const _BranchDialogWatcher();

  @override
  State<_BranchDialogWatcher> createState() => _BranchDialogWatcherState();
}

class _BranchDialogWatcherState extends State<_BranchDialogWatcher> {
  int? _lastBranchDepth;

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<GameController>();
    final atBranch = controller.atBranch;
    final depth = controller.currentNode.depth;

    if (atBranch && depth != _lastBranchDepth) {
      _lastBranchDepth = depth;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _showBranchDialog(context, controller);
      });
    } else if (!atBranch) {
      _lastBranchDepth = null;
    }
    return const SizedBox.shrink();
  }

  void _showBranchDialog(BuildContext context, GameController controller) {
    final options = controller.branchOptions;
    if (options.isEmpty) return;
    showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (ctx) {
        return AlertDialog(
          title: const Text('选择分支'),
          content: Wrap(
            spacing: 12,
            runSpacing: 12,
            alignment: WrapAlignment.center,
            children: [
              for (var i = 0; i < options.length; i++)
                _BranchNumberButton(
                  index: i + 1,
                  notation: options[i].move!.notation,
                  onPressed: () {
                    controller.selectBranch(i);
                    Navigator.of(ctx).pop();
                  },
                ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('取消'),
            ),
          ],
        );
      },
    );
  }
}

/// 分支选择数字按钮：圆形数字 + 下方着法文字。
class _BranchNumberButton extends StatelessWidget {
  const _BranchNumberButton({
    required this.index,
    required this.notation,
    required this.onPressed,
  });

  final int index;
  final String notation;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onPressed,
      child: SizedBox(
        width: 72,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primary,
                shape: BoxShape.circle,
              ),
              alignment: Alignment.center,
              child: Text(
                '$index',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              notation,
              style: const TextStyle(fontSize: 12),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
