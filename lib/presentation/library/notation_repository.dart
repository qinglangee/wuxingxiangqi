import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../core/config/config_manager.dart';
import '../../core/services/storage_access_service.dart';
import '../../domain/notation/parsers/notation_exception.dart';
import '../../domain/notation/parsers/notation_loader.dart';
import '../../domain/notation/parsers/notation_replay.dart';
import '../../domain/notation/parsers/parsed_game.dart';
import 'notation_manager_widget.dart';

/// 支持的棋谱文件扩展名。
const List<String> kNotationExtensions = ['pgn', 'xqf', 'cbf', 'txt'];

/// 打开棋谱文件：读取字节、解析，按设置决定是否完整回放校验，成功后
/// 跳转打谱页面；解析/校验失败则弹窗提示且不跳转（避免在页面构建期
/// 抛异常）。
///
/// 设置中关闭「加载棋谱时验证」时不做事前回放验证，直接跳转，
/// 棋谱使用过程中出错再提示。
///
/// [path] 为棋谱文件的绝对路径。
Future<void> openNotationFile(BuildContext context, String path) async {
  final bytes = await File(path).readAsBytes();
  ParsedGame? parsed;
  ReplayData? replay;
  String? errMsg;
  try {
    parsed = NotationLoader.load(path: path, bytes: bytes);
    // 按设置决定是否完整回放验证：起始 FEN、每步坐标反解与规则校验
    if (ConfigManager.instance.config.ui.validateNotationOnLoad) {
      replay = NotationReplay.resolve(parsed);
    }
  } on NotationParseException catch (e) {
    errMsg = e.message;
  } catch (e) {
    errMsg = '读取或解析文件时出错：$e';
  }

  // 会话棋谱列表：同目录下的全部棋谱文件（与 context 无关，先算好
  // 再检查 mounted，避免跨 async 使用 BuildContext）。
  var sessionGames = [path];
  var sessionGameIndex = 0;
  if (parsed != null && errMsg == null) {
    sessionGames = await _listSessionGames(path);
    sessionGameIndex = sessionGames
        .indexWhere((p) => p.toLowerCase() == path.toLowerCase());
  }

  if (!context.mounted) return;
  if (parsed != null && errMsg == null) {
    // 解析成功（按设置可能已附带验证坐标）：把棋谱、已验证坐标（关闭
    // 验证时为 null，由打谱页按设置自行处理）与来源文件路径一起传给
    // 打谱页（来源路径用于保存时「覆盖原文件」）。
    // 同时把同目录下的全部棋谱文件作为当前会话的棋谱列表传入，
    // 供复盘导航条「上一局/下一局/选谱」切换。
    Navigator.of(context).pushNamed(
      '/play',
      arguments: (parsed, replay, path, sessionGames, sessionGameIndex),
    );
  } else {
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('棋谱解析失败'),
        content: Text(errMsg ?? '未知错误'),
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

/// 列出 [path] 所在目录下的全部棋谱文件（名称升序，忽略大小写），
/// 作为当前会话的棋谱列表。
///
/// 目录读取失败时退化为仅含当前文件；当前文件因故不在列表中时补入，
/// 保证「选谱」总能回到当前局。
Future<List<String>> _listSessionGames(String path) async {
  try {
    final dir = File(path).parent;
    final files = <String>[];
    await for (final e in dir.list(followLinks: false)) {
      if (e is File) {
        final ext = e.path.split('.').last.toLowerCase();
        if (kNotationExtensions.contains(ext)) files.add(e.path);
      }
    }
    String nameKey(String p) =>
        p.split(Platform.pathSeparator).last.toLowerCase();
    files.sort((a, b) => nameKey(a).compareTo(nameKey(b)));
    if (!files.any((p) => p.toLowerCase() == path.toLowerCase())) {
      files.add(path);
    }
    return files;
  } catch (_) {
    return [path];
  }
}

/// 确保目录 [dir] 可直接读写。
///
/// 可写时直接返回 true。Android 上写入失败时，按系统版本引导用户授予
/// 存储权限（Android 11+ 为系统设置中的「所有文件访问」，Android 10 及
/// 以下为外部存储运行时权限），授权后重试写入验证。其余情况返回 false。
Future<bool> ensureDirectoryWritable(
  BuildContext context,
  String dir,
) async {
  if (await ConfigManager.isDirectoryWritable(dir)) return true;
  if (!Platform.isAndroid) return false;

  final sdk = await StorageAccessService.sdkInt();
  if (sdk >= 30) {
    // Android 11+：SAF 目录授权对 dart:io 无效，需要「所有文件访问」
    if (await StorageAccessService.hasAllFilesAccess()) return false;
    if (!context.mounted) return false;
    final go = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('需要存储权限'),
        content: const Text(
          '写入所选目录需要授予应用「所有文件访问」权限。\n\n'
          '点击「去授权」后在系统设置中允许，然后返回应用。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('去授权'),
          ),
        ],
      ),
    );
    if (go != true) return false;
    await StorageAccessService.requestAllFilesAccess();
    // 用户从系统设置返回后，逐次确认授权结果
    while (context.mounted) {
      if (await StorageAccessService.hasAllFilesAccess()) break;
      if (!context.mounted) return false;
      final retry = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('等待授权'),
          content: const Text(
            '尚未检测到「所有文件访问」权限。\n\n'
            '请在系统设置中允许后，点击「我已授权」重试。',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('取消'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('我已授权'),
            ),
          ],
        ),
      );
      if (retry != true) return false;
    }
  } else {
    // Android 10 及以下：传统外部存储运行时权限
    final granted = await StorageAccessService.requestLegacyStorage();
    if (!granted) return false;
  }
  return ConfigManager.isDirectoryWritable(dir);
}

/// 打开外部棋谱仓库（仓库切换按钮 / 首页「棋谱」按上次使用记录直开）：
/// 1. 读取配置中的 [LibraryConfig.notationLibraryPath]；
/// 2. 已配置且目录可写入 → 直接用棋谱管理页面打开该目录（与内置 books
///    同一套浏览/多选/改名/删除界面）；
/// 3. 未配置或目录失效 → 提示并引导用户选择目录，验证可写后保存配置，
///    再打开棋谱管理页面。
///
/// 成功打开后把「上次使用的仓库」记为外部仓库（下次首页「棋谱」直开）。
/// [replace] 为 true 时用新页面替换当前页面（内置 ↔ 外部互跳时保持
/// 导航栈不累积）；为 false 时正常压栈。
///
/// 调用前应先关闭浮动窗口（若有），避免管理页面被遮挡。
Future<void> openExternalRepository(
  BuildContext context, {
  bool replace = false,
}) async {
  final mgr = ConfigManager.instance;
  var path = mgr.config.library.notationLibraryPath;

  // 已配置：检查目录仍存在且可写（Android 上写入失败时先引导授权重试）
  if (path != null && path.isNotEmpty) {
    final ok = await ensureDirectoryWritable(context, path);
    if (!ok) {
      // 配置失效（目录被删/权限丢失），清空并走选择流程
      await mgr.updateLibrary((c) => c.copyWith()..notationLibraryPath = null);
      path = null;
    }
  }

  // 未配置：提示并引导用户选择目录
  if (path == null || path.isEmpty) {
    if (!context.mounted) return;
    final accepted = await _promptChooseDirectory(context);
    if (!accepted) return;
    final picked = await FilePicker.getDirectoryPath(
      dialogTitle: '选择棋谱仓库目录',
    );
    if (picked == null || picked.isEmpty) return;
    if (!context.mounted) return;
    final writable = await ensureDirectoryWritable(context, picked);
    if (!writable) {
      if (!context.mounted) return;
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('目录不可用'),
          content: Text('所选目录不存在或不可写入：\n$picked\n请选择其它目录。'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('知道了'),
            ),
          ],
        ),
      );
      return;
    }
    await mgr.updateLibrary(
      (c) => c.copyWith()..notationLibraryPath = picked,
    );
    path = picked;
  }

  // 已配置：用棋谱管理页面打开外部仓库（与内置 books 同一套界面）
  if (!context.mounted) return;
  // 记录上次使用的仓库为外部仓库（下次首页「棋谱」直开）
  await mgr.updateLibrary((c) => c.copyWith(lastRepoExternal: true));
  if (!context.mounted) return;
  final label = path.split(Platform.pathSeparator).last;
  final route = MaterialPageRoute<void>(
    builder: (pageCtx) => NotationManagerScreen(
      rootDirectory: path,
      rootLabel: label,
      title: '外部仓库 · $label',
      // 外部仓库页面的「内置仓库」按钮：替换式跳回内置 books
      onSwitchRepository: () => openInternalRepository(pageCtx),
    ),
  );
  if (replace) {
    await Navigator.of(context).pushReplacement(route);
  } else {
    await Navigator.of(context).push(route);
  }
}

/// 打开内置 books 棋谱仓库（外部仓库页面的「内置仓库」按钮）：
/// 以默认 books 根打开棋谱管理页面并替换当前页（保持导航栈不累积），
/// 同时把「上次使用的仓库」记为内置仓库。
void openInternalRepository(BuildContext context) {
  // 记录上次使用的仓库为内置 books
  ConfigManager.instance.updateLibrary(
    (c) => c.copyWith(lastRepoExternal: false),
  );
  Navigator.of(context).pushReplacement(
    MaterialPageRoute<void>(
      builder: (pageCtx) => NotationManagerScreen(
        // 内置仓库页面的「外部仓库」按钮：替换式跳到外部仓库
        onSwitchRepository: () =>
            openExternalRepository(pageCtx, replace: true),
      ),
    ),
  );
}

/// 弹出对话框提示用户先选择棋谱仓库目录。
/// 返回 true 表示用户同意继续选择目录；false 表示取消。
Future<bool> _promptChooseDirectory(BuildContext context) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('尚未配置棋谱仓库'),
      content: const Text('需要先选择一个目录作为棋谱仓库，是否现在选择？'),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: const Text('选择目录'),
        ),
      ],
    ),
  );
  return result ?? false;
}
