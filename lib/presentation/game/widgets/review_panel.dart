import 'package:flutter/material.dart';

import '../../../../domain/engine/engine_info.dart';
import '../../../../domain/models/piece.dart';
import '../../../../domain/notation/move_record.dart';
import '../../../../domain/notation/notation_node.dart';
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
import 'cloud_base_controller.dart';
import 'cloud_base_panel.dart';
import 'engine_status_bar.dart';
import 'pv_view.dart';

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
  const ReviewPanel({super.key, required this.controller});

  final GameController controller;

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

  /// 打开「选棋」弹窗，从会话棋谱列表中选择并载入对应棋谱。
  Future<void> _pickSessionGame() async {
    final chosen = await SessionGamesDialog.show(
      context,
      paths: controller.sessionGames,
      currentIndex: controller.sessionGameIndex,
    );
    if (chosen == null || chosen == controller.sessionGameIndex) return;
    await _loadSessionGame(chosen);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.85),
        border: const Border(
          top: BorderSide(color: Color(0xFFC9B68C), width: 0.8),
        ),
      ),
      child: Column(
        children: [
          // 复盘模块：显示 AnalysisPanel，隐藏普通三标签页
          if (_showAnalysis)
            Expanded(
              child: AnalysisPanel(
                controller: controller,
                analysisController: _reviewAnalysis,
              ),
            )
          else ...[
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
            Expanded(
              child: TabBarView(
                controller: _tab,
                children: [
                  _NotationTab(
                    controller: controller,
                    highlightEnabled: _commentHighlight,
                  ),
                  _EngineTab(controller: controller),
                  CloudBasePanel(controller: _cloud),
                ],
              ),
            ),
          ],
          // 底部导航条：任意标签页都可用，控制棋谱前进/后退
          // 仅当当前节点为分支点时，在导航条上方显示分支选择条
          if (controller.atBranch) _BranchSelectorBar(controller: controller),
          AdjustableButtonBar(
            id: 'review_nav_bar',
            defaultPinnedIds: const {'前进', '后退'},
            buttons: [
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
                id: '选棋',
                icon: Icons.grid_view,
                label: '选棋',
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
            ],
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Tab1：棋谱 + 注释
// ---------------------------------------------------------------------------

class _NotationTab extends StatefulWidget {
  const _NotationTab({
    required this.controller,
    required this.highlightEnabled,
  });

  final GameController controller;

  /// 走到带注释的着法时注释框是否浅绿高亮。
  final bool highlightEnabled;

  @override
  State<_NotationTab> createState() => _NotationTabState();
}

class _NotationTabState extends State<_NotationTab> {
  final Map<int, GlobalKey> _rowKeys = {};
  int? _lastFollowedDepth;

  GameController get controller => widget.controller;

  @override
  Widget build(BuildContext context) {
    final line = controller.mainLine;
    // 第 0 个是根节点，无着法；跳过
    final moveNodes = line.skip(1).toList();
    final current = controller.currentNode;

    // 当前节点变化后滚动到可见位置
    if (current.depth != _lastFollowedDepth) {
      _lastFollowedDepth = current.depth;
      WidgetsBinding.instance.addPostFrameCallback((_) => _ensureVisible());
    }

    return Row(
      children: [
        // 左 2/5：着法列表
        Expanded(
          flex: 2,
          child: Container(
            decoration: const BoxDecoration(
              border: Border(
                right: BorderSide(color: Color(0xFFD8C69A), width: 0.6),
              ),
            ),
            child: moveNodes.isEmpty
                ? const Center(
                    child: Padding(
                      padding: EdgeInsets.all(8),
                      child: Text(
                        '尚无着法',
                        style:
                            TextStyle(color: Color(0xFF8B6B3D), fontSize: 13),
                      ),
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    itemCount: moveNodes.length,
                    itemExtent: 32,
                    itemBuilder: (_, i) {
                      final node = moveNodes[i];
                      return _MoveRow(
                        key: _keyFor(node.depth),
                        node: node,
                        isCurrent: identical(node, current),
                        isFuture: node.depth > current.depth,
                        onTap: () => controller.jumpTo(node),
                        onLongPress: () => _showMoveOperations(node),
                      );
                    },
                  ),
          ),
        ),
        // 右 3/5：注释区
        Expanded(
          flex: 3,
          child: _CommentArea(
            controller: controller,
            highlightEnabled: widget.highlightEnabled,
          ),
        ),
      ],
    );
  }

  GlobalKey _keyFor(int depth) =>
      _rowKeys.putIfAbsent(depth, () => GlobalKey());

  void _ensureVisible() {
    final key = _rowKeys[controller.currentNode.depth];
    final ctx = key?.currentContext;
    if (ctx != null) {
      Scrollable.ensureVisible(
        ctx,
        alignment: 0.3,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
      );
    }
  }

  /// 长按着法后弹出操作对话框：删除着法 / 管理其分支。
  void _showMoveOperations(NotationNode node) {
    showDialog<void>(
      context: context,
      builder: (_) => _MoveOperationsDialog(
        controller: controller,
        node: node,
      ),
    );
  }
}

/// 分支选择条：浮动在底部导航栏上方，仅在分支点显示。
///
/// 一条水平长条，按分支数等分宽度，每段显示一个分支序号字母
/// （A-Z，超过 26 个继续用小写 a-z）。点击字母即选择对应分支并跳转。
class _BranchSelectorBar extends StatelessWidget {
  const _BranchSelectorBar({required this.controller});

  final GameController controller;

  @override
  Widget build(BuildContext context) {
    final options = controller.branchOptions;
    if (options.isEmpty) return const SizedBox.shrink();

    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFFEFE0B8),
        border: Border(
          top: BorderSide(color: Color(0xFFC9B68C), width: 0.6),
          bottom: BorderSide(color: Color(0xFFC9B68C), width: 0.6),
        ),
      ),
      // 固定高度：只够放下一个数字小圆点
      height: 32,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Row(
        children: [
          for (var i = 0; i < options.length; i++)
            Expanded(
              child: Center(
                child: InkWell(
                  onTap: () => controller.selectBranch(i),
                  child: Container(
                    width: 24,
                    height: 24,
                    decoration: BoxDecoration(
                      color: AppTheme.boardLine,
                      shape: BoxShape.circle,
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      branchLetter(i),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// 着法单行（竖向列表的一行）。
class _MoveRow extends StatelessWidget {
  const _MoveRow({
    super.key,
    required this.node,
    required this.isCurrent,
    required this.isFuture,
    required this.onTap,
    this.onLongPress,
  });

  final NotationNode node;
  final bool isCurrent;
  final bool isFuture;
  final VoidCallback onTap;

  /// 长按弹出着法操作菜单（删除着法 / 管理分支）。
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    final MoveRecord record = node.move!;
    final isRed = record.side == Side.red;
    final round = node.moveNumber;

    Color bg;
    Color fg;
    if (isCurrent) {
      bg = AppTheme.boardLine;
      fg = Colors.white;
    } else if (isFuture) {
      bg = Colors.transparent;
      fg = const Color(0xFFB0A48A);
    } else {
      bg = isRed
          ? const Color(0x11C62828)
          : const Color(0x112C3E2D);
      fg = isRed ? AppTheme.redPiece : AppTheme.blackPiece;
    }

    return InkWell(
      onTap: onTap,
      onLongPress: onLongPress,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 3),
        decoration: BoxDecoration(color: bg),
        child: Row(
          children: [
            // 回合号
            SizedBox(
              width: 28,
              child: Text(
                '$round.',
                textAlign: TextAlign.right,
                style: TextStyle(
                  fontSize: 12,
                  color: isCurrent
                      ? Colors.white.withValues(alpha: 0.85)
                      : const Color(0xFF8B6B3D),
                ),
              ),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                record.notation,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: fg,
                ),
              ),
            ),
            if (node.children.length > 1)
              // 分支标记：圆角背景上显示「分支总数 + 当前分支序号字母」
              Container(
                margin: const EdgeInsets.only(left: 4),
                padding:
                    const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                decoration: BoxDecoration(
                  color: fg.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '${node.children.length}'
                  '${branchLetter(node.parent!.children.indexOf(node))}',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    color: fg,
                  ),
                ),
              ),
            if (record.comment != null && record.comment!.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(left: 4),
                child: Icon(Icons.edit_note, size: 13, color: fg),
              ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// 着法操作对话框（长按着法弹出）
// ---------------------------------------------------------------------------

/// 长按着法后弹出的操作对话框。
///
/// - 「删除此着法」：删除该着法及其全部后代（主线续着与所有分支），
///   删除前二次确认；
/// - 若该着法有多于一条续着（即存在分支），列出全部续着，可上移/下移
///   调整顺序，也可删除某条续着（含其后代），删除前二次确认。
class _MoveOperationsDialog extends StatefulWidget {
  const _MoveOperationsDialog({
    required this.controller,
    required this.node,
  });

  final GameController controller;

  /// 被长按的着法节点。
  final NotationNode node;

  @override
  State<_MoveOperationsDialog> createState() => _MoveOperationsDialogState();
}

class _MoveOperationsDialogState extends State<_MoveOperationsDialog> {
  GameController get controller => widget.controller;
  NotationNode get node => widget.node;

  @override
  Widget build(BuildContext context) {
    final record = node.move!;
    final children = node.children;
    final hasBranches = children.length > 1;

    return AlertDialog(
      title: Text('第 ${node.moveNumber} 回合  ${record.notation}'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 删除此着法
            OutlinedButton.icon(
              onPressed: _confirmDeleteMove,
              icon: const Icon(Icons.delete_outline, color: Color(0xFFC62828)),
              label: const Text(
                '删除此着法',
                style: TextStyle(color: Color(0xFFC62828)),
              ),
              style: OutlinedButton.styleFrom(
                side: const BorderSide(color: Color(0xFFC62828)),
              ),
            ),
            if (children.isNotEmpty) ...[
              const SizedBox(height: 16),
              Row(
                children: [
                  Text(
                    '续着（共 ${children.length} 条）',
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF8B6B3D),
                    ),
                  ),
                  if (hasBranches) ...[
                    const SizedBox(width: 8),
                    const Text(
                      '可上下调整顺序或删除',
                      style: TextStyle(fontSize: 11, color: Color(0xFFB0A48A)),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 6),
              for (var i = 0; i < children.length; i++)
                _buildBranchRow(context, children[i], i),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('关闭'),
        ),
      ],
    );
  }

  Widget _buildBranchRow(BuildContext context, NotationNode child, int index) {
    final isMain = index == node.mainChildIndex;
    final rec = child.move!;
    final color =
        rec.side == Side.red ? AppTheme.redPiece : AppTheme.blackPiece;
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 2),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: isMain
            ? AppTheme.boardLine.withValues(alpha: 0.08)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: isMain
              ? AppTheme.boardLine.withValues(alpha: 0.4)
              : const Color(0xFFE0D2A8),
          width: 0.6,
        ),
      ),
      child: Row(
        children: [
          // 分支字母徽标
          Container(
            width: 20,
            height: 20,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: AppTheme.boardLine,
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              branchLetter(index),
              style: const TextStyle(
                color: Colors.white,
                fontSize: 11,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              rec.notation,
              style: TextStyle(fontSize: 13, color: color),
            ),
          ),
          if (isMain)
            Container(
              margin: const EdgeInsets.only(right: 6),
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
              decoration: BoxDecoration(
                color: AppTheme.boardLine.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                '主线',
                style: TextStyle(
                  fontSize: 10,
                  color: AppTheme.boardLine,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          // 上移
          IconButton(
            icon: const Icon(Icons.arrow_upward, size: 18),
            onPressed: index == 0
                ? null
                : () {
                    controller.moveBranchUp(node, index);
                    setState(() {});
                  },
            tooltip: '上移',
            visualDensity: VisualDensity.compact,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 30, minHeight: 30),
          ),
          // 下移
          IconButton(
            icon: const Icon(Icons.arrow_downward, size: 18),
            onPressed: index == node.children.length - 1
                ? null
                : () {
                    controller.moveBranchDown(node, index);
                    setState(() {});
                  },
            tooltip: '下移',
            visualDensity: VisualDensity.compact,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 30, minHeight: 30),
          ),
          // 删除该续着
          IconButton(
            icon: const Icon(Icons.delete_outline,
                size: 18, color: Color(0xFFC62828)),
            onPressed: () => _confirmDeleteBranch(index),
            tooltip: '删除此续着',
            visualDensity: VisualDensity.compact,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 30, minHeight: 30),
          ),
        ],
      ),
    );
  }

  /// 二次确认后删除当前着法及其全部后代。
  Future<void> _confirmDeleteMove() async {
    final ok = await _confirm(
      context,
      title: '删除着法',
      content: '将删除「${node.move!.notation}」及其后续所有着法和分支，'
          '此操作不可撤销。确认删除？',
    );
    if (!ok || !mounted) return;
    controller.deleteMove(node);
    if (mounted) Navigator.of(context).pop();
  }

  /// 二次确认后删除第 [index] 条续着及其全部后代。
  Future<void> _confirmDeleteBranch(int index) async {
    final child = node.children[index];
    final ok = await _confirm(
      context,
      title: '删除续着',
      content: '将删除续着「${child.move!.notation}」及其后续所有着法和分支，'
          '此操作不可撤销。确认删除？',
    );
    if (!ok || !mounted) return;
    controller.deleteBranch(node, index);
    setState(() {});
  }

  /// 通用二次确认对话框，返回用户是否确认。
  Future<bool> _confirm(
    BuildContext context, {
    required String title,
    required String content,
  }) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(content),
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
    return result ?? false;
  }
}

// ---------------------------------------------------------------------------
// 注释区
// ---------------------------------------------------------------------------

class _CommentArea extends StatefulWidget {
  const _CommentArea({
    required this.controller,
    required this.highlightEnabled,
  });

  final GameController controller;

  /// 走到带注释的着法时注释框是否浅绿高亮（由导航条 check 按钮控制）。
  final bool highlightEnabled;

  @override
  State<_CommentArea> createState() => _CommentAreaState();
}

class _CommentAreaState extends State<_CommentArea>
    with SingleTickerProviderStateMixin {
  /// 注释高亮动画：0 = 浅绿背景，1 = 透明（恢复原色），时长 3 秒。
  late final AnimationController _highlightCtrl = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 3),
    value: 1,
  );

  /// 上一次浏览到的节点，用于识别「前进/后退/跳转」导致的节点切换。
  NotationNode? _lastNode;

  /// 高亮起始浅绿。
  static const Color _highlightColor = Color.fromARGB(255, 116, 245, 120);

  GameController get controller => widget.controller;

  @override
  void dispose() {
    _highlightCtrl.dispose();
    super.dispose();
  }

  /// 节点切换时：若高亮开关开启且新节点（到达它的那步）带有注释，
  /// 重新播放高亮，让注释框由浅绿在 3 秒内逐渐恢复；开关关闭或无注释
  /// 时直接保持透明。
  void _maybeHighlight(NotationNode node) {
    if (identical(_lastNode, node)) return;
    final firstBuild = _lastNode == null;
    _lastNode = node;
    if (firstBuild) return; // 首次进入页面不高亮，仅导航切换时触发
    if (!widget.highlightEnabled) {
      _highlightCtrl.value = 1;
      return;
    }
    final hasComment = controller.currentComment.trim().isNotEmpty;
    if (hasComment) {
      _highlightCtrl.forward(from: 0);
    } else {
      _highlightCtrl.value = 1;
    }
  }

  @override
  void didUpdateWidget(covariant _CommentArea oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 开关在高亮途中被关闭：立即恢复背景
    if (!widget.highlightEnabled && oldWidget.highlightEnabled) {
      _highlightCtrl.value = 1;
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([controller, _highlightCtrl]),
      builder: (context, _) {
        final current = controller.currentNode;
        _maybeHighlight(current);
        // 注释属于「到达当前节点的那步棋」；根节点没有对应走法。
        final hasMove = current.move != null;
        final comment = controller.currentComment;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 顶部操作条：步号 + 添加/编辑注释按钮
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: const BoxDecoration(
                border: Border(
                  bottom: BorderSide(color: Color(0xFFD8C69A), width: 0.6),
                ),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      hasMove
                          ? '第 ${current.moveNumber} 回合注释'
                          : '开局注释',
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF8B6B3D),
                      ),
                    ),
                  ),
                  TextButton.icon(
                    onPressed: () => _editComment(context),
                    icon: const Icon(Icons.edit_note, size: 18),
                    label: Text(
                      comment.isEmpty ? '添加注释' : '编辑注释',
                      style: const TextStyle(fontSize: 13),
                    ),
                    style: TextButton.styleFrom(
                      foregroundColor: AppTheme.boardLine,
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                    ),
                  ),
                ],
              ),
            ),
            // 注释内容区：导航到带注释的着法时浅绿高亮，3 秒渐退
            Expanded(
              child: AnimatedBuilder(
                animation: _highlightCtrl,
                builder: (context, child) => Container(
                  // 固定浅绿、仅对透明度插值，避免渐隐过程中颜色发暗
                  color: _highlightColor
                      .withValues(alpha: 1 - _highlightCtrl.value),
                  padding: const EdgeInsets.all(12),
                  child: child,
                ),
                child: SingleChildScrollView(
                  child: Align(
                    alignment: Alignment.topLeft,
                    child: comment.isNotEmpty
                        ? SelectableText(
                            comment,
                            style: const TextStyle(
                              fontSize: 14,
                              height: 1.6,
                              color: Color(0xFF2C3E2D),
                            ),
                          )
                        : Center(
                            child: Text(
                              '（暂无注释）',
                              style: TextStyle(
                                fontSize: 13,
                                color: const Color(0xFFB0A48A),
                                fontStyle: FontStyle.italic,
                              ),
                            ),
                          ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Future<void> _editComment(BuildContext context) async {
    final initial = controller.currentComment;
    final edited = await showDialog<String>(
      context: context,
      builder: (_) => _CommentDialog(initial: initial),
    );
    if (edited != null) {
      controller.setCurrentComment(edited);
    }
  }
}

class _CommentDialog extends StatefulWidget {
  const _CommentDialog({required this.initial});

  final String initial;

  @override
  State<_CommentDialog> createState() => _CommentDialogState();
}

class _CommentDialogState extends State<_CommentDialog> {
  late final TextEditingController _ctrl =
      TextEditingController(text: widget.initial);

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('编辑注释'),
      content: SizedBox(
        width: double.maxFinite,
        child: TextField(
          controller: _ctrl,
          autofocus: true,
          maxLines: 6,
          minLines: 4,
          decoration: const InputDecoration(
            border: OutlineInputBorder(),
            hintText: '输入这一步的注释…',
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        TextButton(
          onPressed: () {
            final text = _ctrl.text;
            Navigator.of(context).pop(text);
          },
          child: const Text('清除'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(_ctrl.text),
          style: FilledButton.styleFrom(
            backgroundColor: AppTheme.boardLine,
          ),
          child: const Text('保存'),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// 引擎标签
// ---------------------------------------------------------------------------

/// 引擎面板：引擎状态条 + 将军信息条（仅有将军时显示）+ PV 区域。
class _EngineTab extends StatelessWidget {
  const _EngineTab({required this.controller});

  final GameController controller;

  /// 把引擎首选线评分（走子方视角）换算为状态条需要的红方视角数据。
  EngineStatusData _toStatusData(EngineSearchInfo? info) {
    if (info == null) return const EngineStatusData();
    final best = info.bestLine;
    if (best == null) {
      return EngineStatusData(
        depth: info.depth,
        nps: info.nps,
        timeMs: info.timeMs,
      );
    }
    final side = info.sideToMove;
    final cp = best.cp;
    final mate = best.mate;
    return EngineStatusData(
      depth: info.depth,
      nps: info.nps,
      timeMs: info.timeMs,
      // 走子方为黑时，其视角评分取反即为红方视角
      cpRed: cp == null ? null : (side == Side.red ? cp : -cp),
      mateInRed: mate == null ? null : (side == Side.red ? mate : -mate),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final info = controller.engineInfo;
        return Column(
          children: [
            // 1. 引擎状态条
            EngineStatusBar(data: _toStatusData(info)),
            // 2. 将军信息条：仅当前走子方被将军时出现
            if (controller.currentInCheck) const _CheckInfoBar(),
            // 3. PV 区域
            Expanded(
              child: info == null
                  ? const Center(
                      child: Text(
                        '开启「红方电脑/黑方电脑」后，行棋时在此显示引擎分析',
                        style: TextStyle(
                          fontSize: 13,
                          color: Color(0xFFB0A48A),
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                    )
                  : PvLinesView(info: info),
            ),
          ],
        );
      },
    );
  }
}

/// 将军信息状态条：醒目橙底白字。
class _CheckInfoBar extends StatelessWidget {
  const _CheckInfoBar();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      height: 26,
      color: const Color(0xFFD84315),
      alignment: Alignment.center,
      child: const Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.warning, size: 16, color: Colors.white),
          SizedBox(width: 6),
          Text(
            '将军！',
            style: TextStyle(
              color: Colors.white,
              fontSize: 13,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// 占位标签
// ---------------------------------------------------------------------------
