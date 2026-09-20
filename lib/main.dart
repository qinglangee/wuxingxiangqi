import 'package:flutter/material.dart';

import 'app/app.dart';
import 'core/config/config_manager.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // 启动时从磁盘加载用户配置（不存在则使用默认值）
  await ConfigManager.instance.load();
  runApp(const App());
}
