import 'package:flutter/material.dart';

import '../../core/canju/canju_library.dart';
import '../../core/canju/canju_progress.dart';
import '../../core/config/config_manager.dart';
import '../canju/canju_controller.dart';
import '../canju/canju_selector_dialog.dart';
import '../library/notation_manager_widget.dart';
import '../shared/error_dialog.dart';
import '../library/notation_repository.dart';

/// 首页：中国象棋水墨风主菜单。
///
/// 三个入口卡片：棋谱 / 残局 / 打谱。
/// - 「棋谱」弹出棋谱管理浮动窗口（默认打开应用数据目录 books，
///   「外部仓库」按钮走外部目录流程）。
/// - 「残局」跳转到残局页面（/play 路由，残局模式）。
/// - 「打谱」跳转到对局页面（/play 路由，新对局）。
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
            child: LayoutBuilder(
              builder: (context, constraints) {
                final isLandscape =
                    constraints.maxWidth > constraints.maxHeight;
                return ConstrainedBox(
                  constraints: BoxConstraints(
                    maxWidth: isLandscape ? double.infinity : 480,
                  ),
                  child: Column(
                    children: [
                      SizedBox(height: isLandscape ? 16 : 56),
                      _buildTitleBar(context),
                      SizedBox(height: isLandscape ? 16 : 48),
                      Expanded(
                        child: isLandscape
                            ? _buildLandscapeCards(context)
                            : _buildPortraitCards(context),
                      ),
                      const SizedBox(height: 16),
                      _buildFooter(context),
                      SizedBox(height: isLandscape ? 12 : 20),
                    ],
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  /// 竖屏：三个菜单卡片垂直排列。
  Widget _buildPortraitCards(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 28),
      children: [
        _MenuCard(
          title: '棋谱',
          subtitle: '收藏与浏览棋谱',
          icon: const _MenuImage('assets/images/app/item01.jpg'),
          onTap: () => _openNotationManager(context),
        ),
        const SizedBox(height: 24),
        _MenuCard(
          title: '残局',
          subtitle: '练习残局破解',
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
    );
  }

  /// 横屏：三个菜单卡片水平并排。
  Widget _buildLandscapeCards(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 28),
      child: Row(
        children: [
          Expanded(
            child: _MenuCard(
              title: '棋谱',
              subtitle: '收藏与浏览棋谱',
              icon: const _MenuImage('assets/images/app/item01.jpg'),
              onTap: () => _openNotationManager(context),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: _MenuCard(
              title: '残局',
              subtitle: '练习残局破解',
              icon: const _MenuImage('assets/images/app/item02.jpg'),
              onTap: () => _openCanju(context),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: _MenuCard(
              title: '打谱',
              subtitle: '开始一局新棋',
              icon: const _MenuImage('assets/images/app/item03.jpg'),
              highlight: true,
              onTap: () => Navigator.of(context).pushNamed('/play'),
            ),
          ),
        ],
      ),
    );
  }

  /// 底部「软件介绍」链接式按钮。
  Widget _buildFooter(BuildContext context) {
    return Center(
      child: TextButton.icon(
        onPressed: () => Navigator.of(context).pushNamed('/instruction'),
        icon: const Icon(Icons.info_outline, size: 18),
        label: const Text(
          '软件介绍',
          style: TextStyle(
            fontSize: 14,
            decoration: TextDecoration.underline,
            decorationColor: Color(0xFF8B6B3D),
          ),
        ),
        style: TextButton.styleFrom(
          foregroundColor: const Color(0xFF8B6B3D),
          minimumSize: const Size(0, 40),
          padding: const EdgeInsets.symmetric(horizontal: 12),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
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
  // 棋谱入口：默认打开上次使用的仓库（内置 books 浮动窗口 / 外部仓库页面）
  // ---------------------------------------------------------------------------

  /// 点击「棋谱」：按配置中上次使用的仓库打开——
  /// - 上次用外部仓库（且已配置路径）：直接打开外部仓库页面
  ///   （[openExternalRepository]，未配置或失效时引导选择目录）；
  /// - 否则弹出全屏浮动窗口，内嵌棋谱管理控件浏览应用数据目录
  ///   `wuxingxiangqi/books` 下的棋谱；浮动窗口里的「外部仓库」按钮
  ///   先关闭浮动窗口，再以同一套棋谱管理页面打开外部仓库。
  void _openNotationManager(BuildContext context) {
    // 上次使用的是外部仓库：直接打开（目录失效时由 openExternalRepository
    // 引导重选）
    final lib = ConfigManager.instance.config.library;
    if (lib.lastRepoExternal &&
        (lib.notationLibraryPath?.isNotEmpty ?? false)) {
      openExternalRepository(context);
      return;
    }
    showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: '棋谱管理',
      transitionDuration: const Duration(milliseconds: 180),
      pageBuilder: (dialogCtx, animation, secondaryAnimation) {
        return FadeTransition(
          opacity: animation,
          child: Scaffold(
            appBar: AppBar(
              leading: IconButton(
                icon: const Icon(Icons.close),
                tooltip: '关闭',
                onPressed: () => Navigator.of(dialogCtx).pop(),
              ),
              title: const Text('棋谱管理'),
            ),
            body: SafeArea(
              child: NotationManagerWidget(
                onSwitchRepository: () {
                  Navigator.of(dialogCtx).pop();
                  openExternalRepository(context);
                },
                // 先关闭浮动窗口，再打开打谱页面
                onOpenFile: (path) {
                  Navigator.of(dialogCtx).pop();
                  openNotationFile(context, path);
                },
              ),
            ),
          ),
        );
      },
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
      showErrorDialog(context, '没有可用的残局库');
      return;
    }

    final last = store.lastLibrary;
    if (last != null && names.contains(last)) {
      // 直跳：载入上次库的上次局（库可能已被清空，如收藏被删空，
      // 此时落入下方弹窗让用户重选）
      final lib = await CanjuLibraryLoader.load(last);
      if (lib.isNotEmpty) {
        if (!context.mounted) return;
        final rec = store.recordOf(last);
        final idx = rec.currentIndex.clamp(0, lib.length - 1);
        _navigateToCanju(context, lib, idx, store);
        return;
      }
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
