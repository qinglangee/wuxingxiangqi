import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';

/// 在合法落点位置绘制的提示点。
class MoveHighlight extends StatelessWidget {
  const MoveHighlight({super.key, required this.size, required this.isCapture});

  final double size;
  final bool isCapture;

  @override
  Widget build(BuildContext context) {
    if (isCapture) {
      // 吃子提示：环形
      return SizedBox(
        width: size,
        height: size,
        child: DecoratedBox(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: AppTheme.moveHintDot, width: 4),
          ),
        ),
      );
    }
    // 移动提示：中心圆点
    return SizedBox(
      width: size,
      height: size,
      child: Center(
        child: Container(
          width: size * 0.3,
          height: size * 0.3,
          decoration: const BoxDecoration(
            color: AppTheme.moveHintDot,
            shape: BoxShape.circle,
          ),
        ),
      ),
    );
  }
}
