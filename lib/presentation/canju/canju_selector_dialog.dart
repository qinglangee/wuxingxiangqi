import 'package:flutter/material.dart';

import '../../core/canju/canju_library.dart';
import '../../core/canju/canju_progress.dart';

/// 残局库选择弹窗：浮动在屏幕中央，高度 80% / 宽度 90%。
///
/// 列出 [libraries]，让用户选择一个库。每个条目显示库名、当前局与
/// 过关进度。点击后通过 [Navigator.pop] 返回所选 [CanjuLibrary]。
class CanjuSelectorDialog extends StatefulWidget {
  const CanjuSelectorDialog({
    super.key,
    required this.libraries,
    required this.store,
    this.currentLibraryName,
  });

  final List<CanjuLibrary> libraries;

  /// 进度存储，用于显示每个库的当前进度。
  final CanjuStore store;

  /// 当前选中的库名（高亮显示），可选。
  final String? currentLibraryName;

  /// 弹出 [CanjuSelectorDialog] 并等待用户选择，返回选中的库或 null（取消）。
  static Future<CanjuLibrary?> show(
    BuildContext context, {
    required List<CanjuLibrary> libraries,
    required CanjuStore store,
    String? currentLibraryName,
  }) {
    return showDialog<CanjuLibrary>(
      context: context,
      barrierDismissible: true,
      builder: (_) => CanjuSelectorDialog(
        libraries: libraries,
        store: store,
        currentLibraryName: currentLibraryName,
      ),
    );
  }

  @override
  State<CanjuSelectorDialog> createState() => _CanjuSelectorDialogState();
}

class _CanjuSelectorDialogState extends State<CanjuSelectorDialog> {
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
            const Divider(
              height: 1,
              color: Color(0xFFC9B68C),
            ),
            Expanded(child: _buildList()),
          ],
        ),
      ),
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
          const Icon(Icons.extension, color: Colors.white, size: 20),
          const SizedBox(width: 8),
          const Text(
            '选择残局库',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
          const Spacer(),
          Text(
            '${widget.libraries.length} 个库',
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

  Widget _buildList() {
    if (widget.libraries.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(16),
          child: Text(
            '没有可用的残局库',
            style: TextStyle(fontSize: 14, color: Color(0xFF8B6B3D)),
          ),
        ),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.symmetric(vertical: 4),
      itemCount: widget.libraries.length,
      separatorBuilder: (_, _) =>
          const Divider(height: 1, color: Color(0xFFE6D8B0)),
      itemBuilder: (ctx, i) {
        final lib = widget.libraries[i];
        final rec = widget.store.recordOf(lib.name);
        final isCurrent = lib.name == widget.currentLibraryName;
        return ListTile(
          tileColor: isCurrent ? const Color(0xFFE8C988) : null,
          leading: Container(
            width: 36,
            height: 36,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: const Color(0xFF8B5A2B),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              '${i + 1}',
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 14,
              ),
            ),
          ),
          title: Text(
            lib.name,
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: Color(0xFF5A3A1A),
            ),
          ),
          subtitle: Text(
            lib.isEmpty
                ? '共 0 局'
                : '共 ${lib.length} 局 · 当前第 ${rec.currentIndex + 1} 局',
            style: const TextStyle(fontSize: 12, color: Color(0xFF8B6B3D)),
          ),
          trailing: const Icon(Icons.chevron_right,
              color: Color(0xFFC9B68C), size: 20),
          // 空库（如清空后的收藏库）不可选
          onTap: lib.isEmpty ? null : () => Navigator.pop(context, lib),
        );
      },
    );
  }
}
