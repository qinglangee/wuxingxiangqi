import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../domain/game/game_state.dart';
import '../../../domain/models/piece.dart';

/// 状态栏：显示当前轮次、被吃棋子。
class StatusBar extends StatelessWidget {
  const StatusBar({
    super.key,
    required this.state,
    required this.onRestart,
  });

  final GameState state;
  final VoidCallback onRestart;

  @override
  Widget build(BuildContext context) {
    final sideLabel = state.currentSide == Side.red ? '红方' : '黑方';
    final sideColor =
        state.currentSide == Side.red ? AppTheme.redPiece : AppTheme.blackPiece;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: AppTheme.boardLine.withValues(alpha: 0.05),
      child: Row(
        children: [
          Icon(Icons.circle, color: sideColor, size: 16),
          const SizedBox(width: 8),
          Text(
            state.isOver ? state.result.toString() : '$sideLabel 走棋',
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
          ),
          const Spacer(),
          TextButton.icon(
            onPressed: onRestart,
            icon: const Icon(Icons.refresh, size: 18),
            label: const Text('重开'),
          ),
        ],
      ),
    );
  }
}
