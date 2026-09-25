import 'package:flutter/material.dart';

import '../../core/canju/canju_progress.dart';
import '../../core/theme/app_theme.dart';
import '../shared/adjustable_button_bar.dart';

/// 残局选关弹窗：浮动在屏幕中央，高度 80% / 宽度 90%。
///
/// 以网格形式列出 [count] 局题目，每格显示局号与过关状态。
/// 点击后通过 [Navigator.pop] 返回所选局索引（0-based），取消返回 null。
class CanjuLevelDialog extends StatefulWidget {
  const CanjuLevelDialog({
    super.key,
    required this.count,
    required this.progress,
    this.currentIndex,
  });

  final int count;

  /// 当前库的过关位图，用于在每格显示是否已通关。
  final CanjuProgress progress;

  /// 当前局索引（高亮显示），可选。
  final int? currentIndex;

  static Future<int?> show(
    BuildContext context, {
    required int count,
    required CanjuProgress progress,
    int? currentIndex,
  }) {
    return showDialog<int>(
      context: context,
      barrierDismissible: true,
      builder: (_) => CanjuLevelDialog(
        count: count,
        progress: progress,
        currentIndex: currentIndex,
      ),
    );
  }

  @override
  State<CanjuLevelDialog> createState() => _CanjuLevelDialogState();
}

class _CanjuLevelDialogState extends State<CanjuLevelDialog> {
  late final ScrollController _scrollController = ScrollController();

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  /// 沿 [up] 指定的方向滚动 [count] 道题目：按 count/总题数 的比例
  /// 推进滚动位置，越界时 clamp（向下超出总数到底部，向上到顶部）。
  void _scrollBy(int count, {required bool up}) {
    if (!_scrollController.hasClients) return;
    final pos = _scrollController.position;
    if (widget.count <= 0 || pos.maxScrollExtent <= 0) return;
    final delta = (count / widget.count) * pos.maxScrollExtent;
    final target = (up ? pos.pixels - delta : pos.pixels + delta)
        .clamp(0.0, pos.maxScrollExtent);
    _scrollController.animateTo(
      target,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final dialogH = media.size.height * 0.8;
    final dialogW = media.size.width * 0.9;

    return Dialog(
      backgroundColor: const Color(0xFFFDF6E3),
      insetPadding: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: Color(0xFFC9B68C), width: 1.2),
      ),
      child: SizedBox(
        width: dialogW,
        height: dialogH,
        child: Column(
          children: [
            _buildHeader(),
            const Divider(height: 1, color: Color(0xFFC9B68C)),
            _buildJumpBar(),
            Expanded(child: _buildGrid()),
          ],
        ),
      ),
    );
  }

  /// 跳转按钮条：每档数量一对按钮（↓向下 / ↑向上），数量为
  /// 10/100/500/1000/5000；前三对（10/100/500）常驻，其余收进抽屉。
  /// 点击后网格向对应方向滚动该数量的题目，越界时停在端点。
  Widget _buildJumpBar() {
    const counts = [10, 100, 500, 1000, 5000];
    return AdjustableButtonBar(
      defaultPinnedIds: const {
        '10↓', '10↑', '100↓', '100↑', '500↓', '500↑',
      },
      buttons: [
        for (final n in counts) ...[
          FreeButton(
            id: '$n↓',
            icon: Icons.arrow_downward,
            label: '$n',
            onTap: () => _scrollBy(n, up: false),
          ),
          FreeButton(
            id: '$n↑',
            icon: Icons.arrow_upward,
            label: '$n',
            onTap: () => _scrollBy(n, up: true),
          ),
        ],
      ],
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: const BoxDecoration(
        color: Color(0xFF8B5A2B),
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      child: Row(
        children: [
          const Icon(Icons.view_module, color: Colors.white, size: 20),
          const SizedBox(width: 8),
          const Text(
            '选择关卡',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
          const Spacer(),
          Text(
            '共 ${widget.count} 局',
            style: const TextStyle(fontSize: 12, color: Color(0xFFF5E6C8)),
          ),
          const SizedBox(width: 8),
          IconButton(
            icon: const Icon(Icons.close, color: Colors.white, size: 18),
            visualDensity: VisualDensity.compact,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
            onPressed: () => Navigator.pop(context),
          ),
        ],
      ),
    );
  }

  Widget _buildGrid() {
    if (widget.count <= 0) {
      return const Center(
        child: Text(
          '当前题库为空',
          style: TextStyle(fontSize: 14, color: Color(0xFF8B6B3D)),
        ),
      );
    }
    return GridView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.all(12),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 5,
        mainAxisSpacing: 10,
        crossAxisSpacing: 10,
        childAspectRatio: 1.2,
      ),
      itemCount: widget.count,
      itemBuilder: (ctx, i) {
        final cleared = widget.progress.isCleared(i);
        final isCurrent = i == widget.currentIndex;
        return InkWell(
          onTap: () => Navigator.pop(context, i),
          borderRadius: BorderRadius.circular(8),
          child: Container(
            decoration: BoxDecoration(
              color: isCurrent
                  ? const Color(0xFFE8C988)
                  : const Color(0xFFF5E6C8),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: isCurrent ? AppTheme.boardLine : const Color(0xFFD8C69A),
                width: isCurrent ? 2 : 1,
              ),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  '${i + 1}',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: cleared
                        ? const Color(0xFF2E7D32)
                        : const Color(0xFF5A3A1A),
                  ),
                ),
                if (cleared)
                  const Icon(
                    Icons.check_circle,
                    size: 14,
                    color: Color(0xFF2E7D32),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}
