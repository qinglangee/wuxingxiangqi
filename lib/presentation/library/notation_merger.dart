import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../../domain/engine/fen.dart';
import '../../domain/models/board.dart';
import '../../domain/models/piece.dart';
import '../../domain/notation/notation_node.dart';
import '../../domain/notation/notation_tree.dart';
import '../../domain/notation/parsers/notation_exception.dart';
import '../../domain/notation/parsers/notation_loader.dart';
import '../../domain/notation/parsers/notation_replay.dart';
import '../../domain/notation/parsers/parsed_game.dart';

/// 合谱选项：输出目录、文件名（不含扩展名）与格式（pgn/xqf/txt）。
class NotationMergeOptions {
  NotationMergeOptions({
    required this.directory,
    required this.fileName,
    required this.ext,
  });

  final String directory;
  final String fileName;
  final String ext;

  String get path => p.join(directory, '$fileName.$ext');
}

/// 合谱结果。
class NotationMergeResult {
  NotationMergeResult({
    required this.outputPath,
    required this.mergedCount,
    required this.skipped,
  });

  final String outputPath;
  final int mergedCount;
  final List<String> skipped;
}

/// 棋谱合并服务：把多个棋谱文件合并为一个文件。
///
/// - pgn / xqf：先把第一个棋谱构建成内部节点树（[NotationTree]），
///   后续棋谱逐棵构建并按「着法起终点」合并——已有相同着法复用原节点
///   （注释合并），没有的整条线作为新分支加入；起始局面不同的文件跳过；
/// - txt：不构建走子树，只取每份棋谱的初始局面 FEN，每行一个，
///   合并为残局库形式的文本文件。
class NotationMerger {
  NotationMerger._();

  /// 参与合并的棋谱文件扩展名（目录递归时按此收集）。
  static const _mergeableExts = ['pgn', 'xqf'];

  /// 展开选中的路径：文件直接保留（限 pgn/xqf），目录递归收集其中
  /// 全部可合并棋谱，按路径升序排列，保证合并顺序确定。
  static Future<List<String>> expandSources(List<String> selected) async {
    final files = <String>[];
    for (final path in selected) {
      final type = await FileSystemEntity.type(path);
      if (type == FileSystemEntityType.directory) {
        await for (final e
            in Directory(path).list(recursive: true, followLinks: false)) {
          if (e is File && _mergeableExts.contains(_extOf(e.path))) {
            files.add(e.path);
          }
        }
      } else if (type == FileSystemEntityType.file &&
          _mergeableExts.contains(_extOf(path))) {
        files.add(path);
      }
    }
    files.sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    return files;
  }

  static String _extOf(String path) {
    final dot = path.lastIndexOf('.');
    return dot < 0 ? '' : path.substring(dot + 1).toLowerCase();
  }

  /// 执行合并。[sources] 为 [expandSources] 展开后的文件列表。
  /// [onProgress] 每处理完一个文件回调一次（已完成数，总数）。
  static Future<NotationMergeResult> merge({
    required List<String> sources,
    required NotationMergeOptions options,
    void Function(int done, int total)? onProgress,
  }) async {
    if (sources.isEmpty) {
      throw NotationParseException('没有可合并的棋谱文件（仅支持 PGN/XQF）');
    }
    if (options.ext == 'txt') {
      return _mergeFenLibrary(sources, options, onProgress);
    }
    return _mergeTrees(sources, options, onProgress);
  }

  /// pgn/xqf：节点树合并。
  static Future<NotationMergeResult> _mergeTrees(
    List<String> sources,
    NotationMergeOptions options,
    void Function(int done, int total)? onProgress,
  ) async {
    final skipped = <String>[];
    NotationNode? target;
    GameInfo info = const GameInfo();
    String? baseFen;
    var count = 0;
    var done = 0;

    for (final path in sources) {
      final name = p.basename(path);
      try {
        final bytes = await File(path).readAsBytes();
        final parsed = NotationLoader.load(path: path, bytes: bytes);
        // 完整回放校验，同时得到起始局面用于一致性比对
        final data = NotationReplay.resolve(parsed);
        final startFen = Fen.fromBoard(data.startBoard, data.startSide);
        if (target == null) {
          baseFen = startFen;
          target = NotationTree.build(parsed, data);
          info = parsed.info;
          count++;
        } else if (startFen != baseFen) {
          skipped.add('$name：起始局面不同');
        } else {
          final tree = NotationTree.build(parsed, data);
          NotationTree.merge(target, tree);
          count++;
        }
      } on NotationParseException catch (e) {
        skipped.add('$name：${e.message}');
      } catch (e) {
        skipped.add('$name：读取失败（$e）');
      }
      done++;
      onProgress?.call(done, sources.length);
    }

    if (target == null) {
      throw NotationParseException('没有可合并的有效棋谱');
    }
    final game = NotationTree.export(target, info: info);
    await NotationLoader.saveToFile(path: options.path, game: game);
    return NotationMergeResult(
      outputPath: options.path,
      mergedCount: count,
      skipped: skipped,
    );
  }

  /// txt：只收集每份棋谱的初始 FEN，每行一个（残局库形式）。
  static Future<NotationMergeResult> _mergeFenLibrary(
    List<String> sources,
    NotationMergeOptions options,
    void Function(int done, int total)? onProgress,
  ) async {
    final skipped = <String>[];
    final fens = <String>[];
    var done = 0;

    for (final path in sources) {
      final name = p.basename(path);
      try {
        final bytes = await File(path).readAsBytes();
        final parsed = NotationLoader.load(path: path, bytes: bytes);
        final fen = parsed.startingFen?.trim();
        if (fen != null && fen.isNotEmpty) {
          fens.add(fen);
        } else {
          // 未声明起始局面 = 标准开局
          final board = Board()..resetToInitial();
          fens.add(Fen.fromBoard(board, Side.red));
        }
      } on NotationParseException catch (e) {
        skipped.add('$name：${e.message}');
      } catch (e) {
        skipped.add('$name：读取失败（$e）');
      }
      done++;
      onProgress?.call(done, sources.length);
    }

    if (fens.isEmpty) {
      throw NotationParseException('没有可合并的有效棋谱');
    }
    const header = '# 五星象棋残局库（每行一个初始局面 FEN）';
    await File(options.path)
        .writeAsString('$header\n${fens.join('\n')}\n', flush: true);
    return NotationMergeResult(
      outputPath: options.path,
      mergedCount: fens.length,
      skipped: skipped,
    );
  }

  /// 弹出合谱选项对话框：耗时提示 + 名称 / 格式（pgn/xqf/txt）/ 保存位置。
  /// 取消返回 null。
  static Future<NotationMergeOptions?> showOptionsDialog(
    BuildContext context, {
    required String defaultDir,
    required int fileCount,
  }) async {
    return showDialog<NotationMergeOptions>(
      context: context,
      builder: (_) =>
          _MergeOptionsDialog(defaultDir: defaultDir, fileCount: fileCount),
    );
  }
}

/// 合谱选项对话框。
class _MergeOptionsDialog extends StatefulWidget {
  const _MergeOptionsDialog({
    required this.defaultDir,
    required this.fileCount,
  });

  final String defaultDir;
  final int fileCount;

  @override
  State<_MergeOptionsDialog> createState() => _MergeOptionsDialogState();
}

class _MergeOptionsDialogState extends State<_MergeOptionsDialog> {
  late String _directory = widget.defaultDir;
  late final TextEditingController _nameCtrl =
      TextEditingController(text: '合并棋谱');
  String _ext = 'pgn';

  @override
  void dispose() {
    _nameCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickDirectory() async {
    final picked =
        await FilePicker.getDirectoryPath(dialogTitle: '选择保存目录');
    if (picked != null && mounted) {
      setState(() => _directory = picked);
    }
  }

  void _submit() {
    final raw = _nameCtrl.text.trim();
    final name = raw
        .replaceAll(RegExp(r'[\\/:*?"<>|\r\n\t]'), '')
        .trim();
    if (name.isEmpty) return;
    Navigator.of(context).pop(
      NotationMergeOptions(directory: _directory, fileName: name, ext: _ext),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '合谱',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: const Color(0xFFFDF1D6),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: const Color(0xFFE0B96A)),
              ),
              child: Text(
                '将把选中位置下的 ${widget.fileCount} 个棋谱（PGN/XQF）合并为'
                '一个文件。棋谱较多时合并可能需要较长时间，期间请耐心等待。\n\n'
                'PGN/XQF：相同着法自动合并为同一节点，不同着法作为分支保留；\n'
                'TXT：仅合并每份棋谱的初始局面（每行一个 FEN，残局库形式）。',
                style: const TextStyle(fontSize: 12.5, height: 1.5),
              ),
            ),
            const SizedBox(height: 14),
            const Text('保存目录',
                style: TextStyle(fontSize: 13, color: Color(0xFF8B6B4A))),
            const SizedBox(height: 4),
            Row(
              children: [
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 8),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFDF6E3),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: const Color(0xFFC9B68C)),
                    ),
                    child: Text(
                      _directory,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 12.5),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                OutlinedButton(
                  onPressed: _pickDirectory,
                  child: const Text('浏览…'),
                ),
              ],
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _nameCtrl,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: '文件名（不含扩展名）',
                border: OutlineInputBorder(),
                isDense: true,
              ),
              onSubmitted: (_) => _submit(),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                const Text('格式：', style: TextStyle(fontSize: 13)),
                const SizedBox(width: 8),
                DropdownButton<String>(
                  value: _ext,
                  items: const [
                    DropdownMenuItem(value: 'pgn', child: Text('PGN')),
                    DropdownMenuItem(value: 'xqf', child: Text('XQF')),
                    DropdownMenuItem(value: 'txt', child: Text('TXT（残局库）')),
                  ],
                  onChanged: (v) => setState(() => _ext = v ?? _ext),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('取消'),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: _submit,
                  child: const Text('开始合并'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
