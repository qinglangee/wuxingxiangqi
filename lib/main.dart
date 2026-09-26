import 'package:flutter/material.dart';

import 'app/app.dart';
import 'core/config/board_calibration_store.dart';
import 'core/config/config_manager.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // 启动时从磁盘加载用户配置（不存在则使用默认值）
  await ConfigManager.instance.load();
  // 棋盘图片适配参数保存在独立配置文件中
  await BoardCalibrationStore.instance.load();
  runApp(const App());
}
