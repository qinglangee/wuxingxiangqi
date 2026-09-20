import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import 'app_config.dart';

/// 程序配置管理器：负责配置的加载、保存与修改通知。
///
/// - 配置文件位于应用文档目录下的 `app_config.json`（JSON 文本）。
/// - 启动时调用 [load] 从磁盘读取；修改后通过 [save] 落盘。
/// - 继承 [ChangeNotifier]，可被 Provider 注入到 UI 层，UI 在 [notifyListeners]
///   时刷新。当前仅实现读写能力，UI 集成在后续迭代再做。
class ConfigManager extends ChangeNotifier {
  ConfigManager._();

  static final ConfigManager instance = ConfigManager._();

  AppConfig _config = AppConfig();
  bool _loaded = false;

  /// 思考时间硬上限（毫秒），由引擎层强制限制。
  static const int kMaxMoveTimeMs = 1000;

  /// 当前配置（只读视图）。
  AppConfig get config => _config;

  /// 是否已从磁盘加载完成。
  bool get isLoaded => _loaded;

  /// 配置文件名（存放于应用文档目录）。
  static const String kFileName = 'app_config.json';

  /// 启动时调用：从磁盘读取配置。文件不存在或解析失败时使用默认配置。
  ///
  /// 任何异常都不会向外抛出，保证启动流程不被阻塞。
  Future<void> load() async {
    try {
      final file = await _file();
      if (await file.exists()) {
        final raw = await file.readAsString();
        if (raw.trim().isEmpty) {
          _config = AppConfig();
        } else {
          final json = jsonDecode(raw) as Map<String, dynamic>;
          _config = AppConfig.fromJson(json);
        }
      } else {
        _config = AppConfig();
      }
    } catch (e) {
      debugPrint('[ConfigManager] load failed, use defaults: $e');
      _config = AppConfig();
    } finally {
      _loaded = true;
    }
  }

  /// 把当前配置写入磁盘。任何异常都不会向外抛出。
  Future<void> save() async {
    try {
      final file = await _file();
      // 确保父目录存在
      final parent = file.parent;
      if (!await parent.exists()) {
        await parent.create(recursive: true);
      }
      const encoder = JsonEncoder.withIndent('  ');
      await file.writeAsString(encoder.convert(_config.toJson()));
    } catch (e) {
      debugPrint('[ConfigManager] save failed: $e');
    }
  }

  /// 直接整体替换配置并保存。
  Future<void> setConfig(AppConfig config) async {
    _config = config;
    notifyListeners();
    await save();
  }

  /// 更新引擎配置：传入 [updater] 在副本上修改，再写回并保存。
  Future<void> updateEngine(
      EngineConfig Function(EngineConfig current) updater) async {
    final next = updater(_config.engine.copyWith());
    _config = _config.copyWith(engine: next);
    notifyListeners();
    await save();
  }

  /// 更新界面配置。
  Future<void> updateUi(UiConfig Function(UiConfig current) updater) async {
    final next = updater(_config.ui.copyWith());
    _config = _config.copyWith(ui: next);
    notifyListeners();
    await save();
  }

  /// 更新棋子 / 棋盘配置。
  Future<void> updateBoard(
      BoardConfig Function(BoardConfig current) updater) async {
    final next = updater(_config.board.copyWith());
    _config = _config.copyWith(board: next);
    notifyListeners();
    await save();
  }

  /// 更新棋谱仓库配置。
  Future<void> updateLibrary(
      LibraryConfig Function(LibraryConfig current) updater) async {
    final next = updater(_config.library.copyWith());
    _config = _config.copyWith(library: next);
    notifyListeners();
    await save();
  }

  /// 检查目录存在且可写入（尝试在该目录下创建并删除一个临时文件）。
  /// 目录不存在或无写权限时返回 false。
  static Future<bool> isDirectoryWritable(String path) async {
    try {
      final dir = Directory(path);
      if (!await dir.exists()) return false;
      final testFile = File(
        '${dir.path}${Platform.pathSeparator}.wuxing_write_test',
      );
      final raf = await testFile.open(mode: FileMode.write);
      await raf.writeString('ok');
      await raf.close();
      await testFile.delete();
      return true;
    } catch (_) {
      return false;
    }
  }

  /// 重置为默认配置并保存。
  Future<void> resetToDefaults() async {
    _config = AppConfig();
    notifyListeners();
    await save();
  }

  Future<File> _file() async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}${Platform.pathSeparator}$kFileName');
  }
}
