import 'dart:io';

import 'package:flutter/material.dart';

import '../../../../domain/notation/notation_node.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../controllers/game_controller.dart';

// ---------------------------------------------------------------------------
// 注释区
// ---------------------------------------------------------------------------

class CommentArea extends StatefulWidget {
  const CommentArea({
    super.key,
    required this.controller,
    required this.highlightEnabled,
  });

  final GameController controller;

  /// 走到带注释的着法时注释框是否浅绿高亮（由导航条 check 按钮控制）。
  final bool highlightEnabled;

  /// 弹出编辑注释对话框并保存结果（棋谱注释页「添加注释/编辑注释」
  /// 按钮与复盘导航条「注释」按钮共用同一实现）。
  static Future<void> editComment(
      BuildContext context, GameController controller) async {
    final initial = controller.currentComment;
    final edited = await showDialog<String>(
      context: context,
      builder: (_) => _CommentDialog(initial: initial),
    );
    if (edited != null) {
      controller.setCurrentComment(edited);
    }
  }

  @override
  State<CommentArea> createState() => _CommentAreaState();
}

class _CommentAreaState extends State<CommentArea>
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
  void didUpdateWidget(covariant CommentArea oldWidget) {
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
                      _notationTitle(controller),
                      overflow: TextOverflow.ellipsis,
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

  /// 注释区顶部标题：棋谱来自文件时显示文件名，否则显示「未保存」。
  static String _notationTitle(GameController controller) {
    final path = controller.sourceFilePath;
    if (path == null || path.isEmpty) return '未保存';
    return path.split(Platform.pathSeparator).last;
  }

  /// 弹出编辑注释对话框（复用 [CommentArea.editComment]）。
  Future<void> _editComment(BuildContext context) =>
      CommentArea.editComment(context, controller);
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
