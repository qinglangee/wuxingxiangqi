import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../../core/config/config_manager.dart';
import '../../domain/notation/parsers/pgn_parser.dart';
import '../../domain/notation/parsers/parsed_game.dart';
import '../../domain/review/review_analysis.dart';

/// 打谱页面的会话状态：保存/恢复离开时的棋谱与浏览位置。
///
/// 存储格式为 JSON 文件（`session.json`），位于应用数据目录
/// （`文档/wuxingxiangqi`）下。包含：
/// - PGN 文本（含全部分支与注释）
/// - 源文件路径（从文件打开时记录，用于保存功能）
/// - 当前浏览节点的子索引路径（从根到当前节点）
class GameSessionStore {
  GameSessionStore._();

  static const _fileName = 'session.json';

  /// 获取会话文件（异步，因为 dataDirPath 是 Future）。
  static Future<File> _getFile() async => File(p.join(
        await ConfigManager.instance.dataDirPath,
        _fileName,
      ));

  /// 保存当前会话状态。
  ///
  /// [pgnText] 为 PGN 格式的棋谱文本（含分支），[sourcePath] 为
  /// 棋谱来源文件路径，[nodePath] 为根到当前浏览节点的子索引列表。
  static Future<void> save({
    required String pgnText,
    String? sourcePath,
    required List<int> nodePath,
    ReviewAnalysis? analysis,
  }) async {
    try {
      final file = await _getFile();
      final dir = file.parent;
      if (!dir.existsSync()) dir.createSync(recursive: true);
      final json = jsonEncode({
        'pgn': pgnText,
        'sourcePath': sourcePath,
        'nodePath': nodePath,
        if (analysis != null) 'analysis': analysis.toJson(),
      });
      await file.writeAsString(json);
    } catch (e) {
      // 保存失败不影响正常使用，仅打印日志
      // ignore: avoid_print
      print('会话保存失败: $e');
    }
  }

  /// 加载上次保存的会话状态；不存在或解析失败时返回 null。
  static Future<GameSessionData?> load() async {
    try {
      final file = await _getFile();
      if (!file.existsSync()) return null;
      final json = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
      final pgnText = json['pgn'] as String?;
      if (pgnText == null || pgnText.isEmpty) return null;
      final sourcePath = json['sourcePath'] as String?;
      final nodePath = (json['nodePath'] as List<dynamic>?)
              ?.map((e) => e as int)
              .toList() ??
          const <int>[];
      // 把 PGN 解析回 ParsedGame
      final game = const PgnParser().parse(
        utf8.encode(pgnText),
        filename: 'session.pgn',
      );
      // 恢复复盘分析数据（可选）
      ReviewAnalysis? analysis;
      final analysisJson = json['analysis'];
      if (analysisJson is Map<String, dynamic>) {
        try {
          analysis = ReviewAnalysis.fromJson(analysisJson);
        } catch (_) {
          analysis = null;
        }
      }
      return GameSessionData(
        game: game,
        sourcePath: sourcePath,
        nodePath: nodePath,
        analysis: analysis,
      );
    } catch (e) {
      // ignore: avoid_print
      print('会话加载失败: $e');
      return null;
    }
  }
}

/// 加载出的会话数据。
class GameSessionData {
  const GameSessionData({
    required this.game,
    required this.sourcePath,
    required this.nodePath,
    this.analysis,
  });

  final ParsedGame game;
  final String? sourcePath;
  final List<int> nodePath;
  final ReviewAnalysis? analysis;
}
