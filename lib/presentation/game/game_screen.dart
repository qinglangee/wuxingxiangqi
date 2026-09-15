import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../controllers/game_controller.dart';
import 'result_dialog.dart';
import 'widgets/board_widget.dart';
import 'widgets/status_bar.dart';

/// 主页面：拼装棋盘 + 状态栏 + 结束弹窗。
class GameScreen extends StatelessWidget {
  const GameScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<GameController>();
    final state = controller.state;
    return Scaffold(
      appBar: AppBar(title: const Text('中国象棋')),
      body: SafeArea(
        child: Column(
          children: [
            StatusBar(state: state, onRestart: controller.restart),
            Expanded(
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: BoardWidget(
                    board: state.board,
                    selected: state.selected,
                    hints: controller.selectedHints.toSet(),
                    onTap: controller.onTap,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
      // 监听结束态，触发弹窗
      floatingActionButton: const _ResultWatcher(),
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
  bool _shown = false;

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<GameController>();
    if (controller.isOver && !_shown) {
      _shown = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (_) => ResultDialog(
            result: controller.result,
            onRestart: () {
              controller.restart();
              _shown = false;
            },
          ),
        ).then((_) => _shown = false);
      });
    } else if (!controller.isOver) {
      _shown = false;
    }
    return const SizedBox.shrink();
  }
}
