import 'dart:io';

import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';

/// 会话棋谱选择弹窗（复盘导航条「选谱」按钮）：列出当前会话的棋谱
/// 文件（打开棋谱时同目录下的全部棋谱，名称升序），当前局高亮。
///
/// 点击条目后通过 [Navigator.pop] 返回所选下标（0-based），取消返回 null。
class SessionGamesDialog extends StatelessWidget {
  const SessionGamesDialog({
    super.key,
    required this.paths,
    this.currentIndex,
  });

  /// 会话棋谱文件绝对路径列表（名称升序）。
  final List<String> paths;

  /// 当前局下标（高亮显示），可选。
  final int? currentIndex;

  static Future<int?> show(
    BuildContext context, {
    required List<String> paths,
    int? currentIndex,
  }) {
    return showDialog<int>(
      context: context,
      barrierDismissible: true,
      builder: (_) => SessionGamesDialog(
        paths: paths,
        currentIndex: currentIndex,
      ),
    );
  }

  static String _fileNameOf(String path) =>
      path.split(Platform.pathSeparator).last;

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: const Color(0xFFFDF6E3),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: Color(0xFFC9B68C), width: 1.2),
      ),
      child: SizedBox(
        width: 360,
        height: 480,
        child: Column(
          children: [
            _buildHeader(context),
            const Divider(height: 1, color: Color(0xFFC9B68C)),
            Expanded(child: _buildList(context)),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: const BoxDecoration(
        color: Color(0xFF8B5A2B),
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      child: Row(
        children: [
          const Icon(Icons.library_books, color: Colors.white, size: 20),
          const SizedBox(width: 8),
          const Text(
            '选择棋谱',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
          const Spacer(),
          Text(
            '共 ${paths.length} 局',
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

  Widget _buildList(BuildContext context) {
    if (paths.isEmpty) {
      return const Center(
        child: Text(
          '当前会话没有棋谱列表',
          style: TextStyle(fontSize: 14, color: Color(0xFF8B6B3D)),
        ),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.all(8),
      itemCount: paths.length,
      itemBuilder: (ctx, i) {
        final name = _fileNameOf(paths[i]);
        final dot = name.lastIndexOf('.');
        final title = dot > 0 ? name.substring(0, dot) : name;
        final ext = dot > 0 ? name.substring(dot + 1).toUpperCase() : '';
        final isCurrent = i == currentIndex;
        return Container(
          margin: const EdgeInsets.symmetric(vertical: 2),
          decoration: BoxDecoration(
            color: isCurrent ? const Color(0xFFE8C988) : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: isCurrent ? AppTheme.boardLine : Colors.transparent,
              width: isCurrent ? 1.5 : 0,
            ),
          ),
          child: ListTile(
            leading: Icon(
              Icons.description,
              size: 20,
              color: isCurrent ? AppTheme.boardLine : const Color(0xFF8B6B3D),
            ),
            title: Text(
              title,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 14,
                fontWeight: isCurrent ? FontWeight.w700 : FontWeight.w500,
                color: isCurrent ? AppTheme.boardLine : const Color(0xFF5A3A1A),
              ),
            ),
            trailing: ext.isEmpty
                ? null
                : Text(
                    ext,
                    style:
                        const TextStyle(fontSize: 11, color: Color(0xFFB0A48A)),
                  ),
            dense: true,
            onTap: () => Navigator.pop(context, i),
          ),
        );
      },
    );
  }
}
