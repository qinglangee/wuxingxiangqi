import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import 'app_config.dart';

/// 程序配置管理器：负责配置的加载、保存与修改通知。
///
/// - 配置文件位于应用默认数据目录（系统文档目录下的 `wuxingxiangqi`
///   子目录）中的 `app_config.json`（JSON 文本）。
/// - 启动时调用 [load] 从磁盘读取；修改后通过 [save] 落盘。
/// - 继承 [ChangeNotifier]，可被 Provider 注入到 UI 层，UI 在 [notifyListeners]
///   时刷新。当前仅实现读写能力，UI 集成在后续迭代再做。
class ConfigManager extends ChangeNotifier {
  ConfigManager._();

  static final ConfigManager instance = ConfigManager._();

  AppConfig _config = AppConfig();
  bool _loaded = false;

  /// 思考时间硬上限（毫秒），由引擎层强制限制。
  static const int kMaxMoveTimeMs = 30000;

  /// 当前配置（只读视图）。
  AppConfig get config => _config;

  /// 是否已从磁盘加载完成。
  bool get isLoaded => _loaded;

  /// 配置文件名（存放于应用默认数据目录）。
  static const String kFileName = 'app_config.json';

  /// 应用默认数据目录名（位于系统文档目录之下）。
  static const String kDataDirName = 'wuxingxiangqi';

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

  /// 读取某个按钮工具条（按 id）的持久化配置；无记录返回 null。
  ButtonBarConfig? buttonBarConfig(String id) => _config.ui.buttonBars[id];

  /// 保存某个按钮工具条的配置（顺序 / 常驻 / 文字开关）并落盘。
  Future<void> saveButtonBar(String id, ButtonBarConfig barConfig) async {
    await updateUi((ui) {
      ui.buttonBars[id] = barConfig;
      return ui;
    });
  }

  /// 设置是否统一管理按钮工具条文字。
  Future<void> setUnifiedButtonLabels(bool unified) async {
    await updateUi((ui) {
      ui.unifiedButtonLabels = unified;
      return ui;
    });
  }

  /// 设置统一管理下所有工具条是否显示文字。
  Future<void> setGlobalShowButtonLabels(bool show) async {
    await updateUi((ui) {
      ui.globalShowButtonLabels = show;
      return ui;
    });
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
    final dir = Directory(await dataDirPath);
    // 确保默认数据目录存在
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return File('${dir.path}${Platform.pathSeparator}$kFileName');
  }

  String? _dataDirPathCache;
  String? _configFilePathCache;

  /// 应用默认数据目录：系统文档目录下的 `wuxingxiangqi` 子目录。
  /// 配置文件、权重回退副本等应用数据都放在这里。
  Future<String> get dataDirPath async => _dataDirPathCache ??=
      '${(await getApplicationDocumentsDirectory()).path}'
      '${Platform.pathSeparator}$kDataDirName';

  /// 配置文件的完整绝对路径（异步获取并缓存）。
  Future<String> get configFilePath async =>
      _configFilePathCache ??= (await _file()).path;

  /// 配置文件所在目录的绝对路径（即应用默认数据目录）。
  Future<String> get configDirPath async =>
      File(await configFilePath).parent.path;
}
