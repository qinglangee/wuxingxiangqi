import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../../core/config/config_manager.dart';
import '../../../core/theme/app_theme.dart';
import '../../shared/error_dialog.dart';

// ---------------------------------------------------------------------------
// 其他设置：应用配置文件保存位置等信息
// ---------------------------------------------------------------------------

class OtherSettingsTab extends StatelessWidget {
  const OtherSettingsTab({super.key});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<String>(
      future: ConfigManager.instance.configDirPath,
      builder: (context, snapshot) {
        final dir = snapshot.data;
        return ListView(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          children: [
            const Text(
              '存储位置',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.bold,
                color: Color(0xFF5A3A1A),
              ),
            ),
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFFDF6E3),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFFC9B68C)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    '应用配置文件保存目录',
                    style:
                        TextStyle(fontSize: 13, color: Color(0xFF8B6B4A)),
                  ),
                  const SizedBox(height: 6),
                  if (dir != null)
                    SelectableText(
                      "wuxingxiangqi",//dir,
                      style: const TextStyle(
                        fontSize: 13.5,
                        color: Color(0xFF3A2410),
                        fontWeight: FontWeight.w600,
                      ),
                    )
                  else
                    const Text(
                      '读取中…',
                      style:
                          TextStyle(fontSize: 13, color: Color(0xFFB0A48A)),
                    ),
                  const SizedBox(height: 6),
                  Text(
                    '配置文件名：${ConfigManager.kFileName}',
                    style: const TextStyle(
                        fontSize: 12, color: Color(0xFF8B6B4A)),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            const Text(
              '数据管理',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.bold,
                color: Color(0xFF5A3A1A),
              ),
            ),
            const SizedBox(height: 8),
            // 备份数据：打包 wuxingxiangqi 目录到下载目录
            OutlinedButton.icon(
              onPressed: () async {
                final ok = await showDialog<bool>(
                      context: context,
                      builder: (ctx) => AlertDialog(
                        title: const Text('备份数据'),
                        content: const Text('将应用数据目录'
                            '打包为 zip 并保存到系统下载目录。是否继续？'),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.of(ctx).pop(false),
                            child: const Text('取消'),
                          ),
                          FilledButton(
                            onPressed: () => Navigator.of(ctx).pop(true),
                            child: const Text('确定'),
                          ),
                        ],
                      ),
                    ) ??
                    false;
                if (!ok) return;
                try {
                  final path = await ConfigManager.instance.backupData();
                  if (context.mounted) {
                    showInfoDialog(context, '备份完成：$path');
                  }
                } catch (e) {
                  if (context.mounted) {
                    showErrorDialog(context, '备份失败：$e');
                  }
                }
              },
              icon: const Icon(Icons.backup_outlined),
              label: const Text('备份数据'),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppTheme.boardLine,
                side: const BorderSide(color: AppTheme.boardLine),
                padding: const EdgeInsets.symmetric(vertical: 32),
              ),
            ),
            const SizedBox(height: 10),
            // 恢复备份：从 zip 解压覆盖到应用数据目录
            OutlinedButton.icon(
              onPressed: () async {
                // 选择 zip 文件
                final picked = await FilePicker.pickFiles(
                  dialogTitle: '选择备份文件',
                  type: FileType.custom,
                  allowedExtensions: const ['zip'],
                );
                if (picked.isEmpty) return;
                final zipPath = picked.single.path;
                if (zipPath == null) return;
                if (!context.mounted) return;
                // 确认覆盖
                final ok = await showDialog<bool>(
                      context: context,
                      builder: (ctx) => AlertDialog(
                        title: const Text('恢复备份'),
                        content: const Text('恢复操作将覆盖应用数据目录'
                            '中的同名文件。当前的数据'
                            '将被替换。\n\n是否确定恢复？'),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.of(ctx).pop(false),
                            child: const Text('取消'),
                          ),
                          FilledButton(
                            onPressed: () => Navigator.of(ctx).pop(true),
                            child: const Text('确定'),
                          ),
                        ],
                      ),
                    ) ??
                    false;
                if (!ok) return;
                try {
                  await ConfigManager.instance.restoreBackup(zipPath);
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('备份已恢复')),
                    );
                  }
                } catch (e) {
                  if (context.mounted) {
                    showErrorDialog(context, '恢复失败：$e');
                  }
                }
              },
              icon: const Icon(Icons.restore),
              label: const Text('恢复备份'),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppTheme.boardLine,
                side: const BorderSide(color: AppTheme.boardLine),
                padding: const EdgeInsets.symmetric(vertical: 32),
              ),
            ),
            const SizedBox(height: 30),
            // 删除全部配置：清空 wuxingxiangqi 目录并重置内存配置
            FilledButton.icon(
              onPressed: () async {
                final ok = await showDialog<bool>(
                      context: context,
                      builder: (ctx) => AlertDialog(
                        title: const Text('删除应用数据'),
                        content: const Text('将删除应用数据目录'
                            '下的全部文件，包括引擎权重、'
                            '棋谱存档、残局进度、界面与引擎配置等。此操作不可恢复。'
                            '\n\n是否确定删除？'),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.of(ctx).pop(false),
                            child: const Text('取消'),
                          ),
                          FilledButton(
                            style: FilledButton.styleFrom(
                              backgroundColor: Colors.red,
                            ),
                            onPressed: () => Navigator.of(ctx).pop(true),
                            child: const Text('删除'),
                          ),
                        ],
                      ),
                    ) ??
                    false;
                if (!ok) return;
                try {
                  await ConfigManager.instance.deleteAllConfig();
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('已删除应用数据')),
                    );
                  }
                } catch (e) {
                  if (context.mounted) {
                    showErrorDialog(context, '删除失败：$e');
                  }
                }
              },
              icon: const Icon(Icons.delete_forever),
              label: const Text('删除应用数据'),
              style: FilledButton.styleFrom(
                backgroundColor: Colors.red.shade700,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
            ),
          ],
        );
      },
    );
  }
}
