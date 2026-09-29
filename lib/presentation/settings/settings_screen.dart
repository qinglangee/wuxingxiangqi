import 'package:flutter/material.dart';

import 'engine_settings_widget.dart';
import 'tabs/other_settings_tab.dart';
import 'tabs/piece_board_tab.dart';
import 'tabs/ui_settings_tab.dart';

/// 设置页面：用标签页分成四个部分。
///
/// 1. 引擎设置：引擎可执行文件、权重、思考时间、深度等。
/// 2. 界面设置：字号、颜色、背景等风格参数。
/// 3. 棋子棋盘：内层再分「棋盘 / 棋子」两个子标签，用 tiles 展示
///    `assets/images/boards/` 下的棋盘图片与 `assets/images/pieces/`
///    下的棋子套系，点击即选择并保存；经典代码绘制为默认方式。
/// 4. 其他：棋谱仓库等杂项设置。
///
/// 引擎 / 界面 / 其他三个标签页内容先留空占位，后续迭代逐步填充。
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
        children: [
          const EngineSettingsWidget(),
          const UiSettingsTab(),
          const PieceBoardTab(),
          const OtherSettingsTab(),
        ],
      ),
    );
  }
}
