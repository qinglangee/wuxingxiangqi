import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';

/// 可选择的电脑对手列表（第一版三个）。
const List<String> kOpponents = ['阮星弈', '李世才', '五星'];

/// 对手选择浮动窗口。
///
/// 宽度为应用宽度的 80%，高度为应用高度的 80%。内部排列显示可选对手，
/// 点击即选中并关闭窗口。
class OpponentDialog extends StatelessWidget {
  const OpponentDialog({
    super.key,
    required this.current,
    required this.onSelected,
  });

  /// 当前选中的对手名称。
  final String current;

  /// 选中对手后的回调。
  final ValueChanged<String> onSelected;

  /// 显示对手选择窗口，返回用户选择的对手名称（取消时返回 null）。
  static Future<String?> show(
    BuildContext context, {
    required String current,
  }) {
    return showDialog<String>(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => OpponentDialog(
        current: current,
        onSelected: (name) => Navigator.of(ctx).pop(name),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    return Dialog(
      backgroundColor: const Color(0xFFFBF3E0),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: Color(0xFFC9B68C), width: 1.2),
      ),
      insetPadding: EdgeInsets.zero,
      child: SizedBox(
        width: size.width * 0.8,
        height: size.height * 0.8,
        child: Column(
          children: [
            // 标题栏
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
              decoration: const BoxDecoration(
                color: Color(0xFFEFE0B8),
                borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
                border: Border(
                  bottom: BorderSide(color: Color(0xFFC9B68C), width: 0.8),
                ),
              ),
              child: Row(
                children: [
                  const Icon(Icons.sports_esports,
                      color: AppTheme.boardLine),
                  const SizedBox(width: 8),
                  const Text(
                    '选择对手',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: AppTheme.boardLine,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.close, color: Color(0xFF8B6B3D)),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),
            // 对手列表
            Expanded(
              child: ListView.separated(
                padding: const EdgeInsets.symmetric(vertical: 12),
                itemCount: kOpponents.length,
                separatorBuilder: (_, _) => const Divider(
                  height: 1,
                  color: Color(0xFFE0D2A8),
                ),
                itemBuilder: (context, index) {
                  final name = kOpponents[index];
                  final selected = name == current;
                  return ListTile(
                    contentPadding:
                        const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                    leading: CircleAvatar(
                      radius: 24,
                      backgroundColor: selected
                          ? AppTheme.boardLine
                          : const Color(0xFFE0D2A8),
                      child: Text(
                        name.substring(0, 1),
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w700,
                          color: selected
                              ? Colors.white
                              : AppTheme.boardLine,
                        ),
                      ),
                    ),
                    title: Text(
                      name,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: selected
                            ? AppTheme.boardLine
                            : const Color(0xFF5A3A1A),
                      ),
                    ),
                    trailing: selected
                        ? const Icon(Icons.check_circle,
                            color: AppTheme.boardLine)
                        : const Icon(Icons.chevron_right,
                            color: Color(0xFFB0A48A)),
                    onTap: () => onSelected(name),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
