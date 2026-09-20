import 'package:flutter/material.dart';

import '../../../../domain/models/piece.dart';
import '../../../../domain/notation/move_record.dart';
import '../../../../domain/notation/notation_node.dart';
import '../../../core/theme/app_theme.dart';
import '../../controllers/game_controller.dart';

/// 底部棋谱栏：后退 / 前进按钮 + 可横向滚动的着法列表。
///
/// - 点击着法可跳转到对应局面。
/// - 有分支的着法显示分支标记；有注释的着法显示注释标记
///   （分支切换与注释编辑 UI 后续补充，数据层已支持）。
class NotationBar extends StatefulWidget {
  const NotationBar({super.key, required this.controller});

  final GameController controller;

  @override
  State<NotationBar> createState() => _NotationBarState();
}

class _NotationBarState extends State<NotationBar> {
  final Map<int, GlobalKey> _chipKeys = {};
  int? _lastFollowedDepth;

  GameController get controller => widget.controller;

  @override
  Widget build(BuildContext context) {
    final line = controller.mainLine;
    final moveNodes = line.skip(1).toList();
    final current = controller.currentNode;

    // 按回合两两分组
    final rounds = <_Round>[];
    for (var i = 0; i < moveNodes.length; i += 2) {
      rounds.add(_Round(
        number: moveNodes[i].moveNumber,
        red: moveNodes[i],
        black: i + 1 < moveNodes.length ? moveNodes[i + 1] : null,
      ));
    }

    // 当前节点变化后滚动到可见位置
    if (current.depth != _lastFollowedDepth) {
      _lastFollowedDepth = current.depth;
      WidgetsBinding.instance.addPostFrameCallback((_) => _ensureCurrentVisible());
    }

    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.75),
        border: const Border(
          top: BorderSide(color: Color(0xFFC9B68C), width: 0.8),
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
      child: Row(
        children: [
          _NavButton(
            icon: Icons.chevron_left,
            tooltip: '后退一步',
            enabled: controller.canGoBack,
            onTap: controller.goBack,
          ),
          Expanded(
            child: SizedBox(
              height: 52,
              child: rounds.isEmpty
                  ? const Center(
                      child: Text(
                        '尚无着法',
                        style: TextStyle(color: Color(0xFF8B6B3D), fontSize: 13),
                      ),
                    )
                  : ListView.separated(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      itemCount: rounds.length,
                      separatorBuilder: (_, _) => const SizedBox(width: 6),
                      itemBuilder: (_, i) => _buildRound(rounds[i], current),
                    ),
            ),
          ),
          _NavButton(
            icon: Icons.chevron_right,
            tooltip: '前进一步',
            enabled: controller.canGoForward,
            onTap: controller.goForward,
          ),
        ],
      ),
    );
  }

  Widget _buildRound(_Round round, NotationNode current) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Text(
              '${round.number}.',
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: Color(0xFF8B6B3D),
              ),
            ),
          ),
        ),
        _MoveChip(
          key: _keyFor(round.red.depth),
          node: round.red,
          isCurrent: identical(round.red, current),
          isFuture: round.red.depth > current.depth,
          onTap: () => controller.jumpTo(round.red),
        ),
        if (round.black != null) ...[
          const SizedBox(width: 4),
          _MoveChip(
            key: _keyFor(round.black!.depth),
            node: round.black!,
            isCurrent: identical(round.black, current),
            isFuture: round.black!.depth > current.depth,
            onTap: () => controller.jumpTo(round.black!),
          ),
        ],
      ],
    );
  }

  GlobalKey _keyFor(int depth) =>
      _chipKeys.putIfAbsent(depth, () => GlobalKey());

  void _ensureCurrentVisible() {
    final key = _chipKeys[controller.currentNode.depth];
    final ctx = key?.currentContext;
    if (ctx != null) {
      Scrollable.ensureVisible(
        ctx,
        alignment: 0.5,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
      );
    }
  }
}

class _NavButton extends StatelessWidget {
  const _NavButton({
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
      iconSize: 30,
      visualDensity: VisualDensity.compact,
      icon: Icon(icon),
      tooltip: tooltip,
      onPressed: enabled ? onTap : null,
      color: AppTheme.boardLine,
      disabledColor: const Color(0xFFD0C4A8),
    );
  }
}

/// 单个着法标签。
class _MoveChip extends StatelessWidget {
  const _MoveChip({
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

    Color bg;
    Color fg;
    if (isCurrent) {
      bg = AppTheme.boardLine;
      fg = Colors.white;
    } else if (isFuture) {
      bg = const Color(0xFFEFE7D2);
      fg = const Color(0xFFB0A48A);
    } else {
      bg = const Color(0xFFF5E6C8);
      fg = isRed ? AppTheme.redPiece : AppTheme.blackPiece;
    }

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isCurrent ? AppTheme.boardLine : const Color(0xFFD8C69A),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              record.notation,
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: fg,
              ),
            ),
            if (node.children.length > 1)
              Padding(
                padding: const EdgeInsets.only(left: 3),
                child: Icon(Icons.account_tree, size: 12, color: fg),
              ),
            if (record.comment != null && record.comment!.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(left: 3),
                child: Icon(Icons.edit_note, size: 13, color: fg),
              ),
          ],
        ),
      ),
    );
  }
}

/// 一个回合（红方一步 + 可能的黑方一步）。
class _Round {
  _Round({required this.number, required this.red, this.black});

  final int number;
  final NotationNode red;
  final NotationNode? black;
}
