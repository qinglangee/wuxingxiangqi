import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../core/canju/canju_library.dart';
import '../../core/canju/canju_progress.dart';
import '../../core/config/config_manager.dart';
import '../../domain/notation/parsers/notation_exception.dart';
import '../../domain/notation/parsers/notation_loader.dart';
import '../../domain/notation/parsers/notation_replay.dart';
import '../../domain/notation/parsers/parsed_game.dart';
import '../canju/canju_controller.dart';
import '../canju/canju_selector_dialog.dart';

/// 首页：中国象棋水墨风主菜单。
///
/// 三个入口卡片：棋谱 / 残局 / 打谱。
/// - 「棋谱」打开棋谱仓库目录（未配置时引导用户选择目录）。
/// - 「打谱」跳转到对局页面（/play 路由）。
/// - 「残局」与右上角设置按钮暂用 SnackBar 占位。
class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          // 首屏背景图：整幅铺满
          image: DecorationImage(
            image: AssetImage('assets/images/bg/default.jpeg'),
            fit: BoxFit.cover,
          ),
        ),
        child: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: Column(
                children: [
                  const SizedBox(height: 56),
                  _buildTitleBar(context),
                  const SizedBox(height: 48),
                  Expanded(
                    child: ListView(
                      padding: const EdgeInsets.symmetric(horizontal: 28),
                      children: [
                        _MenuCard(
                          title: '棋谱',
                          subtitle: '收藏与浏览经典棋谱',
                          icon: const _MenuImage('assets/images/app/item01.jpg'),
                          onTap: () => _openNotationLibrary(context),
                        ),
                        const SizedBox(height: 24),
                        _MenuCard(
                          title: '残局',
                          subtitle: '练习经典残局破解',
                          icon: const _MenuImage('assets/images/app/item02.jpg'),
                          onTap: () => _openCanju(context),
                        ),
                        const SizedBox(height: 24),
                        _MenuCard(
                          title: '打谱',
                          subtitle: '开始一局新棋',
                          icon: const _MenuImage('assets/images/app/item03.jpg'),
                          highlight: true,
                          onTap: () => Navigator.of(context).pushNamed('/play'),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 32),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTitleBar(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Row(
        children: [
          Container(width: 36, height: 2, color: const Color(0xFF8B6B3D)),
          const SizedBox(width: 12),
          const Expanded(
            child: Center(
              child: Text(
                '五星象棋',
                style: TextStyle(
                  fontSize: 34,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF2C3E2D),
                  letterSpacing: 6,
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          GestureDetector(
            onTap: () => Navigator.of(context).pushNamed('/settings'),
            child: const Icon(Icons.settings, color: Color(0xFF8B6B3D), size: 28),
          ),
          const SizedBox(width: 36),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // 残局入口：有上次记录直跳，无记录弹窗选择
  // ---------------------------------------------------------------------------

  Future<void> _openCanju(BuildContext context) async {
    final store = CanjuStore.instance;
    if (!store.isLoaded) await store.load();
    final names = await CanjuLibraryLoader.listNames();
    if (names.isEmpty) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('assets/canju/ 目录下没有残局库')),
      );
      return;
    }

    final last = store.lastLibrary;
    if (last != null && names.contains(last)) {
      // 直跳：载入上次库的上次局
      final lib = await CanjuLibraryLoader.load(last);
      if (!context.mounted) return;
      final rec = store.recordOf(last);
      final idx = rec.currentIndex.clamp(0, lib.length - 1);
      _navigateToCanju(context, lib, idx, store);
      return;
    }

    // 首次或上次库已不存在：弹窗让用户选
    final libs = await CanjuLibraryLoader.loadAll();
    if (!context.mounted) return;
    final chosen = await CanjuSelectorDialog.show(
      context,
      libraries: libs,
      store: store,
      currentLibraryName: last,
    );
    if (chosen == null) return;
    await store.setLastLibrary(chosen.name);
    await store.setCurrentIndex(chosen.name, 0);
    if (!context.mounted) return;
    _navigateToCanju(context, chosen, 0, store);
  }

  void _navigateToCanju(
    BuildContext context,
    CanjuLibrary lib,
    int initialIndex,
    CanjuStore store,
  ) {
    Navigator.of(context).pushNamed(
      '/play',
      arguments: CanjuSession(
        library: lib,
        initialIndex: initialIndex,
        store: store,
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // 棋谱仓库：打开已配置目录或引导用户先选择目录
  // ---------------------------------------------------------------------------

  /// 点击「棋谱」按钮：
  /// 1. 读取配置中的 [LibraryConfig.notationLibraryPath]；
  /// 2. 已配置且目录可写入 → 用文件选择器从该目录起手让用户选择棋谱文件；
  /// 3. 未配置或目录失效 → 提示并引导用户选择目录，验证可写后保存配置，
  ///    再继续打开文件选择器。
  Future<void> _openNotationLibrary(BuildContext context) async {
    final mgr = ConfigManager.instance;
    var path = mgr.config.library.notationLibraryPath;

    // 已配置：检查目录仍存在且可写
    if (path != null && path.isNotEmpty) {
      final ok = await ConfigManager.isDirectoryWritable(path);
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
      final writable = await ConfigManager.isDirectoryWritable(picked);
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

    // 已配置：打开文件选择器，让用户在仓库目录中选择棋谱或进入子目录
    final file = await FilePicker.pickFiles(
      dialogTitle: '选择棋谱文件',
      initialDirectory: path,
      type: FileType.custom,
      allowedExtensions: const ['pgn', 'xqf', 'cbf', 'txt'],
    );
    if (file.isEmpty) return;
    final pickedPath = file.single.path;
    if (pickedPath == null || pickedPath.isEmpty) return;

    // 读取文件字节并交给解析器；解析后还会在内存中完整回放一遍校验，
    // 任何一步失败都弹窗提示，且不跳转到打谱页（避免在页面构建期抛异常）。
    final bytes = await File(pickedPath).readAsBytes();
    ParsedGame? parsed;
    ReplayData? replay;
    String? errMsg;
    try {
      parsed = NotationLoader.load(path: pickedPath, bytes: bytes);
      // 完整回放验证：起始 FEN、每步坐标反解与规则校验
      replay = NotationReplay.resolve(parsed);
    } on NotationParseException catch (e) {
      errMsg = e.message;
    } catch (e) {
      errMsg = '读取或解析文件时出错：$e';
    }

    if (!context.mounted) return;
    if (parsed != null && replay != null) {
      // 解析与回放均成功：把棋谱与已验证的坐标一起传给打谱页
      Navigator.of(context).pushNamed(
        '/play',
        arguments: (parsed, replay),
      );
    } else {
      // 解析/回放失败：弹出错误对话框显示详情，停留当前页
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
}

// ---------------------------------------------------------------------------
// 菜单卡片
// ---------------------------------------------------------------------------

class _MenuCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final Widget icon;
  final VoidCallback onTap;
  final bool highlight;

  const _MenuCard({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.onTap,
    this.highlight = false,
  });

  @override
  Widget build(BuildContext context) {
    final borderColor =
        highlight ? const Color(0xFF8B5A2B) : const Color(0xFFC9B68C);
    final buttonBg = highlight ? const Color(0xFF8B5A2B) : const Color(0xFF2C3E2D);

    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 168,
        decoration: BoxDecoration(
          color: const Color(0xFFFDF6E3),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: borderColor, width: 1.2),
          boxShadow: const [
            BoxShadow(
              color: Color(0x20000000),
              blurRadius: 10,
              offset: Offset(0, 4),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              // 左侧插画
              Expanded(
                flex: 2,
                child: Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF5E6C8),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: icon,
                ),
              ),
              const SizedBox(width: 16),
              // 右侧大按钮
              Expanded(
                flex: 3,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 22, vertical: 12),
                      decoration: BoxDecoration(
                        color: buttonBg,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        title,
                        style: const TextStyle(
                          fontSize: 26,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFFFDF6E3),
                          letterSpacing: 4,
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        fontSize: 13,
                        color: Color(0xFF8B6B3D),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// 左侧插画：资源图片（圆角裁切铺满）
// ---------------------------------------------------------------------------

class _MenuImage extends StatelessWidget {
  final String asset;

  const _MenuImage(this.asset);

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: Image.asset(
        asset,
        fit: BoxFit.cover,
        width: double.infinity,
        height: double.infinity,
      ),
    );
  }
}
