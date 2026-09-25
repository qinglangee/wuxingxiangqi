import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';

/// 通用选择按钮（check button）：图标在上、文字在下，文字可整体隐藏。
///
/// - [checked] 为 null 时按普通按钮渲染（无选中态）；
/// - [checked] 非 null 时作为选择按钮使用，选中时显示高亮底框；
/// - [showLabel] 为 false 时只显示图标，按钮更紧凑。
///
/// 典型用法：打谱页顶部的「红方电脑 / 黑方电脑」开关。
class IconCheckButton extends StatelessWidget {
  const IconCheckButton({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
    this.checked,
    this.enabled = true,
    this.showLabel = true,
    this.iconColor,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  /// 选中态；null 表示普通按钮（不参与选中高亮）。
  final bool? checked;

  final bool enabled;

  /// 是否显示文字；false 时仅显示图标。
  final bool showLabel;

  /// 图标颜色；null 时使用主题默认色。禁用时始终为灰色。
  final Color? iconColor;

  @override
  Widget build(BuildContext context) {
    final isChecked = checked ?? false;
    final effectiveIconColor = enabled
        ? (iconColor ?? AppTheme.boardLine)
        : const Color(0xFFD0C4A8);
    final labelColor =
        enabled ? const Color(0xFF8B6B3D) : const Color(0xFFD0C4A8);

    return InkWell(
      onTap: enabled ? onTap : null,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 4),
        decoration: isChecked
            ? BoxDecoration(
                color: AppTheme.boardLine.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: AppTheme.boardLine.withValues(alpha: 0.55),
                  width: 0.9,
                ),
              )
            : null,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 26, color: effectiveIconColor),
            if (showLabel) ...[
              const SizedBox(height: 2),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: isChecked ? FontWeight.w700 : FontWeight.w400,
                  color: labelColor,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
