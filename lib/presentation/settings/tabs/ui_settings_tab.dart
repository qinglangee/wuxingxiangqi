import 'package:flutter/material.dart';

import '../../../core/config/config_manager.dart';
import '../../../core/theme/app_theme.dart';

// ---------------------------------------------------------------------------
// 界面设置：按钮工具条文字的统一管理开关
// ---------------------------------------------------------------------------

class UiSettingsTab extends StatelessWidget {
  const UiSettingsTab({super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: ConfigManager.instance,
      builder: (context, _) {
        final ui = ConfigManager.instance.config.ui;
        final cm = ConfigManager.instance;
        return ListView(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          children: [
            const Text(
              '按钮工具条',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.bold,
                color: Color(0xFF5A3A1A),
              ),
            ),
            const SizedBox(height: 8),
            Container(
              decoration: BoxDecoration(
                color: const Color(0xFFFDF6E3),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFFC9B68C)),
              ),
              child: Column(
                children: [
                  SwitchListTile(
                    title: const Text(
                      '统一管理文字显示',
                      style: TextStyle(fontSize: 14, color: Color(0xFF5A3A1A)),
                    ),
                    subtitle: const Text(
                      '开启后，页面中所有按钮工具条统一按下方开关显示或隐藏文字',
                      style: TextStyle(fontSize: 12, color: Color(0xFF8B6B4A)),
                    ),
                    value: ui.unifiedButtonLabels,
                    activeThumbColor: AppTheme.boardLine,
                    onChanged: cm.setUnifiedButtonLabels,
                  ),
                  const Divider(height: 1, indent: 16, endIndent: 16),
                  SwitchListTile(
                    title: Text(
                      '显示按钮文字',
                      style: TextStyle(
                        fontSize: 14,
                        color: ui.unifiedButtonLabels
                            ? const Color(0xFF5A3A1A)
                            : const Color(0xFFB0A48A),
                      ),
                    ),
                    subtitle: Text(
                      ui.unifiedButtonLabels
                          ? '统一管理开启时，所有工具条都使用该设置'
                          : '统一管理已关闭：各工具条按自身设置显示',
                      style: const TextStyle(
                          fontSize: 12, color: Color(0xFF8B6B4A)),
                    ),
                    value: ui.globalShowButtonLabels,
                    activeThumbColor: AppTheme.boardLine,
                    // 仅在统一管理开启时该全局开关生效
                    onChanged: ui.unifiedButtonLabels
                        ? cm.setGlobalShowButtonLabels
                        : null,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFFFF4DC),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFFE0C486)),
              ),
              child: const Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.info_outline, size: 18, color: Color(0xFF8B6B3D)),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '说明：在任意一个按钮工具条中点击「显示文字」按钮单独设置'
                      '文字是否显示时，会自动关闭统一管理，之后各工具条按各自的'
                      '设置显示。',
                      style:
                          TextStyle(fontSize: 12.5, color: Color(0xFF6B4A28), height: 1.5),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              '浮动星星',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.bold,
                color: Color(0xFF5A3A1A),
              ),
            ),
            const SizedBox(height: 8),
            Container(
              decoration: BoxDecoration(
                color: const Color(0xFFFDF6E3),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFFC9B68C)),
              ),
              child: Column(
                children: [
                  SwitchListTile(
                    title: const Text(
                      '缩放星（黄色）',
                      style: TextStyle(fontSize: 14, color: Color(0xFF5A3A1A)),
                    ),
                    subtitle: const Text(
                      '棋盘下边缘的五角星，上下拖动可整体缩放棋盘',
                      style: TextStyle(fontSize: 12, color: Color(0xFF8B6B4A)),
                    ),
                    value: ui.showScaleStar,
                    activeThumbColor: AppTheme.boardLine,
                    onChanged: cm.setShowScaleStar,
                  ),
                  const Divider(height: 1, indent: 16, endIndent: 16),
                  SwitchListTile(
                    title: const Text(
                      '菜单星（红色）',
                      style: TextStyle(fontSize: 14, color: Color(0xFF5A3A1A)),
                    ),
                    subtitle: const Text(
                      '打谱页的五角星菜单，点击环形展开常驻按钮',
                      style: TextStyle(fontSize: 12, color: Color(0xFF8B6B4A)),
                    ),
                    value: ui.showMenuStar,
                    activeThumbColor: AppTheme.boardLine,
                    onChanged: cm.setShowMenuStar,
                  ),
                  const Divider(height: 1, indent: 16, endIndent: 16),
                  SwitchListTile(
                    title: const Text(
                      '标签星（绿色）',
                      style: TextStyle(fontSize: 14, color: Color(0xFF5A3A1A)),
                    ),
                    subtitle: const Text(
                      '打谱页的五角星开关，点击切换三个标签页的显隐',
                      style: TextStyle(fontSize: 12, color: Color(0xFF8B6B4A)),
                    ),
                    value: ui.showTabStar,
                    activeThumbColor: AppTheme.boardLine,
                    onChanged: cm.setShowTabStar,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            // 恢复默认按钮：清除全部 UI 相关配置
            FilledButton.icon(
              onPressed: () async {
                final ok = await showDialog<bool>(
                      context: context,
                      builder: (ctx) => AlertDialog(
                        title: const Text('恢复默认'),
                        content: const Text('确定要将所有界面设置恢复为默认值吗？\n'
                            '按钮工具条顺序、常驻列表、文字开关、浮动星星等'
                            '全部 UI 配置将被清除。'),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.of(ctx).pop(false),
                            child: const Text('取消'),
                          ),
                          FilledButton(
                            onPressed: () => Navigator.of(ctx).pop(true),
                            child: const Text('确定'),
                          ),
                        ],
                      ),
                    ) ??
                    false;
                if (!ok) return;
                await cm.resetUiToDefaults();
              },
              icon: const Icon(Icons.restart_alt),
              label: const Text('恢复默认'),
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF8B6B3D),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
            ),
          ],
        );
      },
    );
  }
}
