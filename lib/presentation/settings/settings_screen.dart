import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';

/// 设置页面：用标签页分成四个部分。
///
/// 1. 引擎设置：引擎可执行文件、权重、思考时间、深度等。
/// 2. 界面设置：字号、颜色、背景等风格参数。
/// 3. 棋子棋盘：内置棋子/棋盘样式选择与自定义资源。
/// 4. 其他：棋谱仓库等杂项设置。
///
/// 当前各标签页内容先留空占位，后续迭代逐步填充。
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tab = TabController(length: 4, vsync: this);

  @override
  void dispose() {
    _tab.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('设置'),
        bottom: TabBar(
          controller: _tab,
          labelColor: Colors.white,
          unselectedLabelColor: const Color(0xFFE8D5B0),
          indicatorColor: Colors.white,
          indicatorSize: TabBarIndicatorSize.label,
          labelStyle:
              const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
          tabs: const [
            Tab(text: '引擎设置'),
            Tab(text: '界面设置'),
            Tab(text: '棋子棋盘'),
            Tab(text: '其他'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tab,
        children: const [
          _SettingsPlaceholder(title: '引擎设置', hint: '引擎文件、权重、思考参数（待实现）'),
          _SettingsPlaceholder(title: '界面设置', hint: '字号、颜色、背景等风格设置（待实现）'),
          _SettingsPlaceholder(title: '棋子棋盘', hint: '棋子与棋盘样式选择、自定义资源（待实现）'),
          _SettingsPlaceholder(title: '其他设置', hint: '棋谱仓库等杂项设置（待实现）'),
        ],
      ),
    );
  }
}

/// 设置标签页统一占位：居中显示标题与提示文字。
class _SettingsPlaceholder extends StatelessWidget {
  const _SettingsPlaceholder({required this.title, required this.hint});

  final String title;
  final String hint;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.settings_suggest,
              size: 48,
              color: AppTheme.boardLine.withValues(alpha: 0.4),
            ),
            const SizedBox(height: 12),
            Text(
              title,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: Color(0xFF8B6B3D),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              hint,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 13,
                color: Color(0xFFB0A48A),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
