import 'package:flutter/material.dart';

import '../../../../domain/engine/engine_info.dart';
import '../../../../domain/models/piece.dart';
import '../../../../domain/notation/move_record.dart';
import '../../../../domain/notation/notation_node.dart';
import '../../../core/theme/app_theme.dart';
import '../../controllers/game_controller.dart';
import '../../shared/adjustable_button_bar.dart';
import 'cloud_base_controller.dart';
import 'cloud_base_panel.dart';
import 'engine_status_bar.dart';
import 'pv_view.dart';

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

  GameController get controller => widget.controller;

  @override
  void dispose() {
    _cloud.dispose();
    _tab.dispose();
    super.dispose();
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
              tabs: const [
                Tab(text: '棋谱注释'),
                Tab(text: '引擎'),
                Tab(text: '云库'),
              ],
            ),
          ),
          Expanded(
            child: TabBarView(
              controller: _tab,
              children: [
                _NotationTab(controller: controller),
                _EngineTab(controller: controller),
                CloudBasePanel(controller: _cloud),
              ],
            ),
          ),
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
  const _NotationTab({required this.controller});

  final GameController controller;

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
        // 左 1/3：着法列表
        Expanded(
          flex: 1,
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
                      );
                    },
                  ),
          ),
        ),
        // 右 2/3：注释区
        Expanded(
          flex: 2,
          child: _CommentArea(controller: controller),
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
}

/// 分支选择条：浮动在底部导航栏上方，仅在分支点显示。
///
/// 一条水平长条，按分支数等分宽度，每段显示一个 1-based 数字。
/// 点击数字即选择对应分支并跳转。
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
                      '${i + 1}',
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
  });

  final NotationNode node;
  final bool isCurrent;
  final bool isFuture;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final MoveRecord record = node.move!;
    final isRed = record.side == Side.red;
    final round = node.moveNumber;

    Color bg;
    Color fg;
    Color sideDot;
    if (isCurrent) {
      bg = AppTheme.boardLine;
      fg = Colors.white;
      sideDot = isRed ? Colors.red.shade100 : Colors.black87;
    } else if (isFuture) {
      bg = Colors.transparent;
      fg = const Color(0xFFB0A48A);
      sideDot = const Color(0xFFC9B68C);
    } else {
      bg = isRed
          ? const Color(0x11C62828)
          : const Color(0x112C3E2D);
      fg = isRed ? AppTheme.redPiece : AppTheme.blackPiece;
      sideDot = isRed ? AppTheme.redPiece : AppTheme.blackPiece;
    }

    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8),
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
            // 红黑小圆点
            Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(color: sideDot, shape: BoxShape.circle),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                record.notation,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: fg,
                ),
              ),
            ),
            if (node.children.length > 1)
              Icon(Icons.account_tree, size: 12, color: fg),
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
// 注释区
// ---------------------------------------------------------------------------

class _CommentArea extends StatelessWidget {
  const _CommentArea({required this.controller});

  final GameController controller;

  @override
  Widget build(BuildContext context) {
    // 注释属于「到达当前节点的那步棋」；根节点没有对应走法。
    final hasMove = controller.currentNode.move != null;
    final comment = controller.currentComment;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // 顶部操作条：步号 + 添加/编辑注释按钮
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
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
                      ? '第 ${controller.currentNode.moveNumber} 回合注释'
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
        // 注释内容区
        Expanded(
          child: Container(
            padding: const EdgeInsets.all(12),
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
