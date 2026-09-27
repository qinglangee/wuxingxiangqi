import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../../core/config/config_manager.dart';
import '../../domain/notation/parsers/notation_exception.dart';
import '../../domain/notation/parsers/notation_loader.dart';
import '../../domain/notation/parsers/parsed_game.dart';
import '../controllers/game_controller.dart';
import 'notation_repository.dart';

/// 棋谱保存服务：把打谱页当前棋谱树写回文件。
///
/// 流程：
/// - 棋谱由文件打开（[GameController.sourceFilePath] 非空）时，先询问
///   「覆盖原文件 / 另存为 / 取消」：覆盖按原格式写回原路径；
/// - 新对局或选择「另存为」时，弹出保存对话框，由用户选择目录
///   （默认应用数据目录 books，可浏览其子目录或改用系统目录）、
///   文件名与格式（PGN / XQF）；
/// - 目标目录必须有写权限（Android 上必要时引导授权），同名文件
///   需再次确认覆盖。
class GameSaver {
  GameSaver._();

  /// 保存入口。[controller] 为当前打谱页控制器。
  static Future<void> saveGame(
    BuildContext context,
    GameController controller,
  ) async {
    final game = controller.exportParsedGame();
    final source = controller.sourceFilePath;

    if (source != null) {
      final choice = await _askOverwrite(context, source);
      if (!context.mounted) return;
      switch (choice) {
        case _SaveChoice.cancel:
          return;
        case _SaveChoice.overwrite:
          await _writeTo(
            context,
            game: game,
            path: source,
            controller: controller,
            overwriteConfirmed: true,
          );
          return;
        case _SaveChoice.saveAs:
          break; // 走下面另存为
      }
    }

    if (!context.mounted) return;
    final picked = await _SaveAsDialog.show(
      context,
      defaultName: _defaultFileName(game),
      defaultExt: source == null ? 'pgn' : p.extension(source).substring(1),
    );
    if (picked == null || !context.mounted) return;

    final path = p.join(picked.directory, '${picked.fileName}.${picked.ext}');
    await _writeTo(
      context,
      game: game,
      path: path,
      controller: controller,
    );
  }

  /// 默认文件名：赛事名 → 标题 → 「棋谱」。
  static String _defaultFileName(ParsedGame game) {
    final raw = (game.info.event ?? game.info.note ?? '').trim();
    if (raw.isEmpty) return '棋谱';
    return _sanitizeName(raw);
  }

  /// 去掉文件名中不允许的字符。
  static String _sanitizeName(String name) {
    final cleaned = name
        .replaceAll(RegExp(r'[\\/:*?"<>|\r\n\t]'), '')
        .trim();
    return cleaned.isEmpty ? '棋谱' : cleaned;
  }

  /// 覆盖原文件 / 另存为 / 取消 三选一。
  static Future<_SaveChoice> _askOverwrite(
      BuildContext context, String source) async {
    final result = await showDialog<_SaveChoice>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('保存棋谱'),
        content: Text('是否覆盖原文件？\n\n$source'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, _SaveChoice.cancel),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, _SaveChoice.saveAs),
            child: const Text('另存为'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, _SaveChoice.overwrite),
            child: const Text('覆盖'),
          ),
        ],
      ),
    );
    return result ?? _SaveChoice.cancel;
  }

  /// 实际写文件：权限校验 → 同名确认 → 序列化落盘 → 结果提示。
  static Future<void> _writeTo(
    BuildContext context, {
    required ParsedGame game,
    required String path,
    required GameController controller,
    bool overwriteConfirmed = false,
  }) async {
    final dir = p.dirname(path);

    // 目标目录必须有写权限（Android 上失败时先引导授权）
    final writable = await ensureDirectoryWritable(context, dir);
    if (!writable) {
      if (!context.mounted) return;
      await _alert(context, '目标目录不可写', '没有向目标目录写入的权限：\n$dir');
      return;
    }

    // 同名文件确认
    if (!overwriteConfirmed && await File(path).exists()) {
      if (!context.mounted) return;
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('文件已存在'),
          content: Text('以下文件已存在，是否覆盖？\n\n${p.basename(path)}'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('覆盖'),
            ),
          ],
        ),
      );
      if (ok != true) return;
    }

    try {
      await NotationLoader.saveToFile(path: path, game: game);
    } on NotationParseException catch (e) {
      if (!context.mounted) return;
      await _alert(context, '保存失败', e.message);
      return;
    } catch (e) {
      if (!context.mounted) return;
      await _alert(context, '保存失败', '$e');
      return;
    }

    // 另存为新文件后，后续保存默认覆盖新文件
    controller.markSavedTo(path);
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('已保存：$path')),
    );
  }

  static Future<void> _alert(
      BuildContext context, String title, String content) {
    return showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(content),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('知道了'),
          ),
        ],
      ),
    );
  }
}

enum _SaveChoice { cancel, overwrite, saveAs }

/// 另存为选择结果。
class SaveAsResult {
  SaveAsResult({
    required this.directory,
    required this.fileName,
    required this.ext,
  });

  final String directory;
  final String fileName;
  final String ext;
}

/// 另存为对话框：选择目录（默认 books）、文件名与格式。
class _SaveAsDialog extends StatefulWidget {
  const _SaveAsDialog({
    required this.defaultDir,
    required this.defaultName,
    required this.defaultExt,
  });

  final String defaultDir;
  final String defaultName;
  final String defaultExt;

  /// 弹出对话框；取消返回 null。
  static Future<SaveAsResult?> show(
    BuildContext context, {
    required String defaultName,
    required String defaultExt,
  }) async {
    final books =
        '${await ConfigManager.instance.dataDirPath}${Platform.pathSeparator}books';
    if (!context.mounted) return null;
    return showDialog<SaveAsResult>(
      context: context,
      builder: (_) => _SaveAsDialog(
        defaultDir: books,
        defaultName: defaultName,
        defaultExt: defaultExt,
      ),
    );
  }

  @override
  State<_SaveAsDialog> createState() => _SaveAsDialogState();
}

class _SaveAsDialogState extends State<_SaveAsDialog> {
  late String _directory = widget.defaultDir;
  late final TextEditingController _nameCtrl =
      TextEditingController(text: widget.defaultName);
  late String _ext = NotationLoader.writableExtensions.contains(widget.defaultExt)
      ? widget.defaultExt
      : 'pgn';

  @override
  void dispose() {
    _nameCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickDirectory() async {
    // 优先在应用 books 目录树内选择；用户也可选系统上的其它目录
    final picked = await showDialog<String>(
      context: context,
      builder: (_) => _FolderPickerDialog(rootPath: widget.defaultDir),
    );
    if (picked != null && mounted) {
      setState(() => _directory = picked);
    }
  }

  void _submit() {
    final name = GameSaver._sanitizeName(_nameCtrl.text.trim());
    if (name.isEmpty) return;
    Navigator.of(context).pop(
      SaveAsResult(directory: _directory, fileName: name, ext: _ext),
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
              '另存为',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 14),
            const Text('保存目录',
                style: TextStyle(fontSize: 13, color: Color(0xFF8B6B4A))),
            const SizedBox(height: 4),
            Row(
              children: [
                Expanded(
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
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
                  items: [
                    for (final e in NotationLoader.writableExtensions)
                      DropdownMenuItem(value: e, child: Text(e.toUpperCase())),
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
                  child: const Text('保存'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// 目录选择对话框：从 books 根浏览其子目录（仅目录），
/// 底部提供「选择其它系统目录…」走系统目录选择器。
class _FolderPickerDialog extends StatefulWidget {
  const _FolderPickerDialog({required this.rootPath});

  final String rootPath;

  @override
  State<_FolderPickerDialog> createState() => _FolderPickerDialogState();
}

class _FolderPickerDialogState extends State<_FolderPickerDialog> {
  late String _current = widget.rootPath;
  List<Directory> _dirs = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    setState(() => _loading = true);
    try {
      final dirs = <Directory>[];
      await for (final e in Directory(_current).list(followLinks: false)) {
        if (e is Directory) dirs.add(e);
      }
      dirs.sort((a, b) => p
          .basename(a.path)
          .toLowerCase()
          .compareTo(p.basename(b.path).toLowerCase()));
      if (!mounted) return;
      setState(() {
        _dirs = dirs;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _dirs = [];
        _loading = false;
      });
    }
  }

  String get _displayPath {
    final root = widget.rootPath;
    if (_current == root) return 'books';
    final rel = _current.substring(root.length + 1);
    return 'books / ${rel.replaceAll(Platform.pathSeparator, ' / ')}';
  }

  Future<void> _pickSystemDirectory() async {
    final picked =
        await FilePicker.getDirectoryPath(dialogTitle: '选择保存目录');
    if (picked != null && mounted && context.mounted) {
      Navigator.pop(context, picked);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      child: SizedBox(
        width: 420,
        height: 460,
        child: Column(
          children: [
            Row(
              children: [
                IconButton(
                  onPressed: _current != widget.rootPath
                      ? () {
                          setState(() =>
                              _current = p.dirname(_current));
                          _reload();
                        }
                      : null,
                  icon: const Icon(Icons.arrow_upward),
                  tooltip: '上一级',
                ),
                const Expanded(
                  child: Text(
                    '选择保存目录',
                    textAlign: TextAlign.center,
                    style:
                        TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close),
                  tooltip: '取消',
                ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  '当前：$_displayPath',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontSize: 13, color: Color(0xFF8B6B4A)),
                ),
              ),
            ),
            const Divider(height: 12),
            Expanded(
              child: _loading
                  ? const Center(
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : _dirs.isEmpty
                      ? const Center(
                          child: Text('该目录下没有子目录',
                              style: TextStyle(color: Color(0xFFB0A48A))),
                        )
                      : ListView.separated(
                          itemCount: _dirs.length,
                          separatorBuilder: (_, _) =>
                              const Divider(height: 1),
                          itemBuilder: (context, i) => ListTile(
                            leading: const Icon(Icons.folder,
                                color: Color(0xFFC8A24B)),
                            title: Text(p.basename(_dirs[i].path)),
                            dense: true,
                            onTap: () {
                              setState(() => _current = _dirs[i].path);
                              _reload();
                            },
                          ),
                        ),
            ),
            const Divider(height: 1),
            TextButton.icon(
              onPressed: _pickSystemDirectory,
              icon: const Icon(Icons.folder_open, size: 18),
              label: const Text('选择其它系统目录…'),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              child: Row(
                children: [
                  const Spacer(),
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('取消'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: () => Navigator.pop(context, _current),
                    child: const Text('选择当前目录'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
