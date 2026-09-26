import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'config_manager.dart';

/// 单个棋盘图片的适配参数。
///
/// 四个值均为相对棋盘图片显示区域的比例（0..1）：[left]/[top] 是
/// 棋盘左上角交叉点（逻辑 0 列 0 行）的位置，[right]/[bottom] 是
/// 右下角交叉点（逻辑 8 列 9 行）的位置。由此可推出每个格子的宽高，
/// 棋子放置与点击坐标换算都以它为准。
class BoardCalibration {
  const BoardCalibration({
    required this.left,
    required this.top,
    required this.right,
    required this.bottom,
  });

  final double left;
  final double top;
  final double right;
  final double bottom;

  factory BoardCalibration.fromJson(Map<String, dynamic> json) =>
      BoardCalibration(
        left: (json['left'] as num).toDouble(),
        top: (json['top'] as num).toDouble(),
        right: (json['right'] as num).toDouble(),
        bottom: (json['bottom'] as num).toDouble(),
      );

  Map<String, dynamic> toJson() => {
        'left': left,
        'top': top,
        'right': right,
        'bottom': bottom,
      };
}

/// 棋盘适配参数存储：每个棋盘图片文件名单独一条记录，
/// 保存在应用数据目录下独立的 `board_calibration.json` 中。
class BoardCalibrationStore extends ChangeNotifier {
  BoardCalibrationStore._();

  static final BoardCalibrationStore instance = BoardCalibrationStore._();

  static const String kFileName = 'board_calibration.json';

  final Map<String, BoardCalibration> _items = {};

  /// 取某棋盘的适配参数；未适配返回 null（调用方使用默认布局）。
  BoardCalibration? get(String boardFileName) => _items[boardFileName];

  /// 是否已为该棋盘做过适配。
  bool has(String boardFileName) => _items.containsKey(boardFileName);

  /// 启动时从磁盘读取。任何异常都回退为空配置，不阻塞启动。
  Future<void> load() async {
    try {
      final file = await _file();
      if (await file.exists()) {
        final raw = await file.readAsString();
        if (raw.trim().isNotEmpty) {
          final json = jsonDecode(raw) as Map<String, dynamic>;
          _items
            ..clear()
            ..addAll(json.map((k, v) => MapEntry(
                  k,
                  BoardCalibration.fromJson(Map<String, dynamic>.from(v as Map)),
                )));
        }
      }
    } catch (e) {
      debugPrint('[BoardCalibrationStore] load failed: $e');
      _items.clear();
    }
  }

  /// 保存（或更新）某棋盘的适配参数并落盘。
  Future<void> save(String boardFileName, BoardCalibration calibration) async {
    _items[boardFileName] = calibration;
    notifyListeners();
    await _persist();
  }

  /// 删除某棋盘的适配参数（恢复默认布局）并落盘。
  Future<void> reset(String boardFileName) async {
    if (_items.remove(boardFileName) != null) {
      notifyListeners();
      await _persist();
    }
  }

  Future<File> _file() async {
    final dataDir = await ConfigManager.instance.dataDirPath;
    return File('$dataDir${Platform.pathSeparator}$kFileName');
  }

  Future<void> _persist() async {
    try {
      final file = await _file();
      if (!await file.parent.exists()) {
        await file.parent.create(recursive: true);
      }
      const encoder = JsonEncoder.withIndent('  ');
      await file.writeAsString(encoder.convert(
        _items.map((k, v) => MapEntry(k, v.toJson())),
      ));
    } catch (e) {
      debugPrint('[BoardCalibrationStore] save failed: $e');
    }
  }
}
