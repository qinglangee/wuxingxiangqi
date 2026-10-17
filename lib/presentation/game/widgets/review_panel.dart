import 'package:flutter/material.dart';

import '../../../core/config/config_manager.dart';
import '../../../core/theme/app_theme.dart';
import '../../controllers/game_controller.dart';
import '../../library/game_saver.dart';
import '../../memorize/memorize_screen.dart';
import '../../review/analysis_panel.dart';
import '../../review/review_analysis_controller.dart';
import '../../review/session_games_dialog.dart';
import '../../shared/adjustable_button_bar.dart';
import '../../shared/error_dialog.dart';
import '../../shared/floating_star_menu.dart';
import '../../shared/floating_toggle_star.dart';
import 'board_setup_screen.dart';
import 'cloud_base_controller.dart';
import 'tabs/cloud_base_panel.dart';
import 'tabs/comment_area.dart';
import 'tabs/notation_tab.dart';
import 'tabs/engine_tab.dart';

/// 分支序号转字母：0→A、1→B … 25→Z，之后继续用小写 a-z 表示
/// （超过 52 个分支时小写字母循环复用）。
String branchLetter(int index) {
  const upper = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ';
  if (index < upper.length) return upper[index];
  return upper[(index - upper.length) % upper.length].toLowerCase();
}

/// 打谱页面底部面板：三个标签页（棋谱注释 / 引擎 / 云库）。
///
/// - 「棋谱注释」：左 1/3 竖向着法列表 + 右 2/3 注释显示与编辑区。
/// - 「引擎」：引擎状态条（红黑优势比/深度/nps/用时/评分）+ 将军提示
///   + 多路 PV 中文记谱展示，电脑行棋时随引擎 info 实时刷新。
/// - 「云库」：ChessDB 开局库，局面变化时查询并展示按评分排序的候选
///   着法，点击条目即走子。
class ReviewPanel extends StatefulWidget {
  const ReviewPanel({
    super.key,
    required this.controller,
    this.boardAreaKey,
  });

  final GameController controller;

  /// 棋盘区域定位键：浮动红星据此计算默认位置（棋盘下边缘 1/3 处）。
  final GlobalKey? boardAreaKey;

  @override
  State<ReviewPanel> createState() => _ReviewPanelState();
}

class _ReviewPanelState extends State<ReviewPanel>
    with SingleTickerProviderStateMixin {
  late final TabController _tab = TabController(length: 3, vsync: this);

  /// 云库控制器与面板同生命周期：不能放在 build 里新建，
  /// 否则每次重建都会生成新实例（构造即查询 + 旧实例监听泄漏），
  /// 导致一次局面变化叠加出大量重复请求。
  late final CloudBaseController _cloud =
      CloudBaseController(gameController: widget.controller);

  /// 复盘分析控制器（与面板同生命周期）。
  late final ReviewAnalysisController _reviewAnalysis =
      ReviewAnalysisController(widget.controller);

  /// 是否显示复盘模块（true 时隐藏 review_panel 三标签页，显示复盘模块）。
  bool _showAnalysis = false;

  /// 绿星三态：0=标签与面板都显示；1=隐藏标签（面板保留）；
  /// 2=标签与面板都隐藏。
  int _tabStarState = 0;

  /// 「走到带注释的着法时注释框浅绿高亮」开关（默认开启）。
  ///
  /// 初值从复盘导航条按钮配置恢复；check button 状态由
  /// AdjustableButtonBar 自动持久化到 app_config.json。
  late bool _commentHighlight =
      ConfigManager.instance.buttonBarConfig('review_nav_bar')
              ?.checked['注释高亮'] ??
          true;

  GameController get controller => widget.controller;

  @override
  void dispose() {
    _cloud.dispose();
    _reviewAnalysis.dispose();
    _tab.dispose();
    super.dispose();
  }

  /// 弹出「棋谱注释」标签的操作说明。
  void _showNotationHelp() {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('棋谱注释操作说明'),
        content: const SingleChildScrollView(
          child: Text(
            '• 点击着法：跳转到该步局面。\n'
            '• 长按着法：弹出操作菜单，可删除该着法（及其后所有着法和分支），'
            '或管理其续着分支（上移/下移排序、删除分支）。\n'
            '• 删除操作不可撤销，删除前会二次确认。\n'
            '• 右侧注释区可编辑当前步的注释。',
            style: TextStyle(fontSize: 13, height: 1.6),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('知道了'),
          ),
        ],
      ),
    );
  }

  /// 载入会话棋谱列表中下标 [index] 的棋谱（上一局/下一局共用）。
  ///
  /// 失败时提示错误信息并保留当前棋谱；成功后重置复盘模块
  /// （旧棋谱的分析数据对新棋谱已失效）。
  Future<void> _loadSessionGame(int index) async {
    final err = await controller.loadSessionGame(index);
    if (err != null) {
      // 加载失败：弹窗报错，需用户手动关闭，不自动消失
      if (mounted) await showErrorDialog(context, err, title: '加载棋谱失败');
      return;
    }
    _reviewAnalysis.resetForNewGame();
  }

  /// 打开「选谱」弹窗，从会话棋谱列表中选择并载入对应棋谱。
  Future<void> _pickSessionGame() async {
    final chosen = await SessionGamesDialog.show(
      context,
      paths: controller.sessionGames,
      currentIndex: controller.sessionGameIndex,
    );
    if (chosen == null || chosen == controller.sessionGameIndex) return;
    await _loadSessionGame(chosen);
  }

  /// 「删着」：与棋谱页长按着法的删除功能完全相同——弹确认框，用户
  /// 确认后删除当前着法及其全部后代（子分支一并删除）；当前节点在
  /// 被删子树中，[GameController.deleteMove] 会自动回退到上一着法。
  Future<void> _confirmDeleteCurrentMove() async {
    final node = controller.currentNode;
    if (node.isRoot) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除着法'),
        content: Text('将删除「${node.move!.notation}」及其后续所有着法和分支，'
            '此操作不可撤销。确认删除？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFFC62828),
            ),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    controller.deleteMove(node);
  }

  @override
  Widget build(BuildContext context) {
    final navButtons = _buildNavButtons();
    // 监听配置：界面设置切换红星/绿星显隐时重建
    return ListenableBuilder(
      listenable: ConfigManager.instance,
      builder: (context, _) {
        final config = ConfigManager.instance.config;
    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.85),
        border: const Border(
          top: BorderSide(color: Color(0xFFC9B68C), width: 0.8),
        ),
      ),
      child: Column(
        children: [
          // 浮动红星：管理复盘导航条的全部按钮（不参与布局，
          // 通过 Overlay 浮在所有组件上方）；显隐由两处共同作用：
          // 黄星（缩放把手）处于禁用状态（灰色）时红星不显示，
          // 黄星可用（黄色）时再按界面设置「菜单星」开关决定
          if (config.board.boardHandleEnabled && config.ui.showMenuStar)
            FloatingStarMenu(
              id: 'review_floating_star',
              buttons: navButtons,
              defaultPinnedIds: const {'保存', '背谱', '复盘', '对弈', '摆局'},
              defaultAnchorKey: widget.boardAreaKey,
            ),
          // 浮动绿星：三态循环——0 全部显示（深绿）、1 隐藏标签（浅绿）、
          // 2 隐藏标签与面板（灰绿）；显隐由两处共同作用：
          // 黄星（缩放把手）处于禁用状态（灰色）时绿星不显示，
          // 黄星可用（黄色）时再按界面设置「标签星」开关决定
          if (config.board.boardHandleEnabled && config.ui.showTabStar)
            FloatingToggleStar(
              id: 'review_tab_toggle_star',
              state: _tabStarState,
              onChanged: (v) => setState(() => _tabStarState = v),
              defaultAnchorKey: widget.boardAreaKey,
            ),
          // 复盘模块：显示 AnalysisPanel，隐藏普通三标签页
          if (_showAnalysis)
            Expanded(
              child: AnalysisPanel(
                controller: controller,
                analysisController: _reviewAnalysis,
              ),
            )
          else ...[
            // 绿星三态：0 全部显示；1 隐藏标签（面板保留）；2 全部隐藏
            if (_tabStarState == 0)
              Material(
                color: const Color(0xFFF5E6C8),
                child: TabBar(
                controller: _tab,
                labelColor: AppTheme.boardLine,
                unselectedLabelColor: const Color(0xFF8B6B3D),
                indicatorColor: AppTheme.boardLine,
                indicatorSize: TabBarIndicatorSize.label,
                labelStyle:
                    const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                tabs: [
                  Tab(
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text('棋谱注释'),
                        const SizedBox(width: 4),
                        IconButton(
                          icon: const Icon(Icons.help_outline, size: 16),
                          onPressed: _showNotationHelp,
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(
                            minWidth: 22,
                            minHeight: 22,
                          ),
                          tooltip: '操作说明',
                        ),
                      ],
                    ),
                  ),
                  const Tab(text: '引擎'),
                  const Tab(text: '云库'),
                ],
              ),
            ),
            if (_tabStarState <= 1)
              Expanded(
                child: TabBarView(
                  controller: _tab,
                  children: [
                    NotationTab(
                      controller: controller,
                      highlightEnabled: _commentHighlight,
                    ),
                    EngineTab(controller: controller),
                    CloudBasePanel(controller: _cloud),
                  ],
                ),
              ),
          ],
          // 底部导航条：任意标签页都可用，控制棋谱前进/后退
          // 仅当当前节点为分支点时，在导航条上方显示分支选择条
          if (controller.atBranch) BranchSelectorBar(controller: controller),
          AdjustableButtonBar(
            id: 'review_nav_bar',
            defaultPinnedIds: const {
              '上一分支',
              '下一分支',
              '前进',
              '后退',
              '注释',
              '删着',
            },
            buttons: navButtons,
          ),
        ],
      ),
      );
    });
  }

  /// 复盘导航条的全部按钮（底部导航条与浮动红星共用同一份定义）。
  List<FreeButton> _buildNavButtons() {
    return [
              FreeButton(
                id: '开局',
                icon: Icons.skip_previous,
                label: '开局',
                enabled: controller.canGoBack,
                onTap: () {
                  while (controller.canGoBack) {
                    controller.goBack();
                  }
                },
              ),
              FreeButton(
                id: '上一分支',
                icon: Icons.alt_route,
                label: '上一分支',
                enabled: controller.canGoPrevBranch,
                onTap: controller.goToPrevBranch,
              ),
              FreeButton(
                id: '后退',
                icon: Icons.chevron_left,
                label: '后退',
                enabled: controller.canGoBack,
                onTap: controller.goBack,
              ),
              FreeButton(
                id: '前进',
                icon: Icons.chevron_right,
                label: '前进',
                enabled: controller.canGoForward,
                onTap: controller.goForward,
              ),
              FreeButton(
                id: '下一分支',
                icon: Icons.alt_route,
                label: '下一分支',
                // 与「上一分支」共用同一图标，水平镜像后方向相反、视觉对称
                flipIcon: true,
                enabled: controller.canGoNextBranch,
                onTap: controller.goToNextBranch,
              ),
              FreeButton(
                id: '末尾',
                icon: Icons.skip_next,
                label: '末尾',
                enabled: controller.canGoForward,
                onTap: () {
                  while (controller.canGoForward) {
                    controller.goForward();
                  }
                },
              ),
              FreeButton(
                id: '上一局',
                icon: Icons.keyboard_double_arrow_left,
                label: '上一局',
                enabled: controller.canPrevGame,
                onTap: () => _loadSessionGame(controller.sessionGameIndex - 1),
              ),
              FreeButton(
                id: '下一局',
                icon: Icons.keyboard_double_arrow_right,
                label: '下一局',
                enabled: controller.canNextGame,
                onTap: () => _loadSessionGame(controller.sessionGameIndex + 1),
              ),
              FreeButton(
                id: '选谱',
                icon: Icons.grid_view,
                label: '选谱',
                enabled: controller.sessionGames.isNotEmpty,
                // 选择后弹窗与按钮栏抽屉都关闭，棋盘直接显示局面
                closesDrawer: true,
                onTap: _pickSessionGame,
              ),
              FreeButton(
                id: '保存',
                icon: Icons.save,
                label: '保存',
                onTap: () => GameSaver.saveGame(context, controller),
              ),
              FreeButton(
                id: '注释',
                icon: Icons.edit_note,
                label: '注释',
                // 与「棋谱注释」页的添加/编辑注释按钮完全相同：
                // 为当前着法（根节点为开局评注）添加或编辑注释
                onTap: () => CommentArea.editComment(context, controller),
              ),
              FreeButton(
                id: '删着',
                icon: Icons.delete_outline,
                label: '删着',
                // 根节点（开局局面）无着法可删
                enabled: controller.canGoBack,
                // 与棋谱页长按着法的删除功能完全相同：
                // 确认后删除当前着法及其全部后代，回退到上一着法
                onTap: _confirmDeleteCurrentMove,
              ),
              FreeButton(
                id: '背谱',
                icon: Icons.school,
                label: '背谱',
                onTap: () {
                  // 没有着法（如纯残局初始局面）时无法背谱
                  if (controller.mainLine.length <= 1) {
                    showErrorDialog(context, '当前棋谱没有着法，无法背谱');
                    return;
                  }
                  MemorizeScreen.open(context, controller.exportParsedGame());
                },
              ),
              FreeButton(
                id: '复盘',
                icon: Icons.insights,
                label: '复盘',
                closesDrawer: true,
                checked: _showAnalysis,
                onCheckedChanged: (v) => setState(() => _showAnalysis = v),
              ),
              FreeButton(
                id: '注释高亮',
                icon: Icons.highlight,
                label: '注释高亮',
                checked: _commentHighlight,
                onCheckedChanged: (v) =>
                    setState(() => _commentHighlight = v),
              ),
              FreeButton(
                id: '对弈',
                icon: Icons.sports_esports,
                label: '对弈',
                // 选择后弹窗与按钮栏抽屉都关闭，棋盘直接显示局面
                closesDrawer: true,
                onTap: () => controller.enterPlayMode(),
              ),
              FreeButton(
                id: '摆局',
                icon: Icons.grid_on,
                label: '摆局',
                // 打开全屏摆局页；完成后以 FEN 初始化打谱页
                closesDrawer: true,
                onTap: () async {
                  final fen = await BoardSetupScreen.open(context, controller);
                  if (fen != null && fen.isNotEmpty) controller.loadFen(fen);
                },
              ),
            ];
  }
}
