import 'package:flutter/material.dart';

import 'app/app.dart';
import 'core/config/board_calibration_store.dart';
import 'core/config/config_manager.dart';
import 'core/services/sound_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // 启动时从磁盘加载用户配置（不存在则使用默认值）
  await ConfigManager.instance.load();
  // 棋盘图片适配参数保存在独立配置文件中
  await BoardCalibrationStore.instance.load();
  // 预加载走子/吃子/终局音效，消除首次播放延迟
  await SoundService.preload();
  runApp(const App());
}
