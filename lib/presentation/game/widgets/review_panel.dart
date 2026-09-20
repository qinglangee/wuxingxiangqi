import 'package:flutter/material.dart';

import '../../../../domain/models/piece.dart';
import '../../../../domain/notation/move_record.dart';
import '../../../../domain/notation/notation_node.dart';
import '../../../core/theme/app_theme.dart';
import '../../controllers/game_controller.dart';

/// 打谱页面底部面板：三个标签页（棋谱注释 / 引擎 / 云库）。
///
/// - 「棋谱注释」：左 1/3 竖向着法列表 + 右 2/3 注释显示与编辑区。
/// - 「引擎」「云库」：当前仅占位，后续补充。
class ReviewPanel extends StatefulWidget {
  const ReviewPanel({super.key, required this.controller});

  final GameController controller;

  @override
  State<ReviewPanel> createState() => _ReviewPanelState();
}

class _ReviewPanelState extends State<ReviewPanel>
    with SingleTickerProviderStateMixin {
  late final TabController _tab = TabController(length: 3, vsync: this);

  GameController get controller => widget.controller;

  @override
  void dispose() {
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
                const _PlaceholderTab(label: '引擎', hint: '集成皮卡鱼引擎分析（待实现）'),
                const _PlaceholderTab(label: '云库', hint: '接入在线开局库（待实现）'),
              ],
            ),
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
        // 左 1/3：着法列表（含前进/后退按钮）
        Expanded(
          flex: 1,
          child: Container(
            decoration: const BoxDecoration(
              border: Border(
                right: BorderSide(color: Color(0xFFD8C69A), width: 0.6),
              ),
            ),
            child: Column(
              children: [
                _NavRow(controller: controller),
                Expanded(
                  child: moveNodes.isEmpty
                      ? const Center(
                          child: Padding(
                            padding: EdgeInsets.all(8),
                            child: Text(
                              '尚无着法',
                              style: TextStyle(
                                  color: Color(0xFF8B6B3D), fontSize: 13),
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
              ],
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

class _NavRow extends StatelessWidget {
  const _NavRow({required this.controller});

  final GameController controller;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        border: Border(
          bottom: BorderSide(color: Color(0xFFD8C69A), width: 0.6),
        ),
      ),
      child: Row(
        children: [
          _NavBtn(
            icon: Icons.skip_previous,
            tooltip: '回到开局',
            enabled: controller.canGoBack,
            onTap: () {
              // 连续后退到根
              while (controller.canGoBack) {
                controller.goBack();
              }
            },
          ),
          _NavBtn(
            icon: Icons.chevron_left,
            tooltip: '后退一步',
            enabled: controller.canGoBack,
            onTap: controller.goBack,
          ),
          const Spacer(),
          _NavBtn(
            icon: Icons.chevron_right,
            tooltip: '前进一步',
            enabled: controller.canGoForward,
            onTap: controller.goForward,
          ),
          _NavBtn(
            icon: Icons.skip_next,
            tooltip: '跳到末尾',
            enabled: controller.canGoForward,
            onTap: () {
              while (controller.canGoForward) {
                controller.goForward();
              }
            },
          ),
        ],
      ),
    );
  }
}

class _NavBtn extends StatelessWidget {
  const _NavBtn({
    required this.icon,
    required this.tooltip,
    required this.enabled,
    required this.onTap,
  });

  final IconData icon;
  final String tooltip;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      iconSize: 22,
      visualDensity: VisualDensity.compact,
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(minWidth: 40, minHeight: 32),
      icon: Icon(icon),
      tooltip: tooltip,
      onPressed: enabled ? onTap : null,
      color: AppTheme.boardLine,
      disabledColor: const Color(0xFFD0C4A8),
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
              if (hasMove)
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
                child: hasMove && comment.isNotEmpty
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
                          hasMove ? '（暂无注释）' : '（开局局面不可加注释）',
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
// 占位标签
// ---------------------------------------------------------------------------

class _PlaceholderTab extends StatelessWidget {
  const _PlaceholderTab({required this.label, required this.hint});

  final String label;
  final String hint;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.construction, size: 36, color: const Color(0xFFC9B68C)),
          const SizedBox(height: 8),
          Text(
            label,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: Color(0xFF8B6B3D),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            hint,
            style: const TextStyle(fontSize: 12, color: Color(0xFFB0A48A)),
          ),
        ],
      ),
    );
  }
}
