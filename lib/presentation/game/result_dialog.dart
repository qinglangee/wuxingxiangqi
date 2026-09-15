import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../domain/game/game_result.dart';

/// 游戏结束弹窗：显示胜负结果，提供"再来一局"按钮。
class ResultDialog extends StatelessWidget {
  const ResultDialog({super.key, required this.result, required this.onRestart});

  final GameResult result;
  final VoidCallback onRestart;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('对局结束'),
      content: Text(
        result.toString(),
        style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
      ),
      actionsAlignment: MainAxisAlignment.center,
      actions: [
        FilledButton.icon(
          onPressed: () {
            Navigator.of(context).pop();
            onRestart();
          },
          style: FilledButton.styleFrom(
            backgroundColor: AppTheme.boardLine,
          ),
          icon: const Icon(Icons.refresh),
          label: const Text('再来一局'),
        ),
      ],
    );
  }
}
