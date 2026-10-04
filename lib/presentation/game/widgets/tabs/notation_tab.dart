import 'package:flutter/material.dart';

import '../../../../domain/models/piece.dart';
import '../../../../domain/notation/move_record.dart';
import '../../../../domain/notation/notation_node.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../controllers/game_controller.dart';
import '../review_panel.dart';
import 'comment_area.dart';

// ---------------------------------------------------------------------------
// Tab1：棋谱 + 注释
// ---------------------------------------------------------------------------

class NotationTab extends StatefulWidget {
  const NotationTab({
    super.key,
    required this.controller,
    required this.highlightEnabled,
  });

  final GameController controller;

  /// 走到带注释的着法时注释框是否浅绿高亮。
  final bool highlightEnabled;

  @override
  State<NotationTab> createState() => _NotationTabState();
}

class _NotationTabState extends State<NotationTab> {
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
          child: CommentArea(
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
/// 分支数不超过 10 时等分整条宽度；超过 10 个时改为可左右滑动，
/// 各字母保持固定间距。
class BranchSelectorBar extends StatelessWidget {
  const BranchSelectorBar({super.key, required this.controller});

  final GameController controller;

  /// 滑动模式下相邻字母圆点的固定间距。
  static const double _dotSpacing = 6;

  @override
  Widget build(BuildContext context) {
    final options = controller.branchOptions;
    if (options.isEmpty) return const SizedBox.shrink();

    final scrollable = options.length > 10;
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
      child: scrollable
          ? SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  for (var i = 0; i < options.length; i++)
                    Padding(
                      padding: EdgeInsets.only(
                        left: i == 0 ? 0 : _dotSpacing,
                      ),
                      child: _buildDot(i),
                    ),
                ],
              ),
            )
          : Row(
              children: [
                for (var i = 0; i < options.length; i++)
                  Expanded(child: Center(child: _buildDot(i))),
              ],
            ),
    );
  }

  /// 单个分支字母圆点。
  Widget _buildDot(int i) {
    return InkWell(
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
            if (node.parent!.children.length > 1 || node.children.length > 1)
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
                  '${node.parent!.children.length > 1 ? branchLetter(node.parent!.children.indexOf(node)) : ''}'
                  '${node.children.length > 1 ? node.children.length : ''}',
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
