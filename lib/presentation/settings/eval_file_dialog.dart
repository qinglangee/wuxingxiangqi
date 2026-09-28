import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../../core/config/config_manager.dart';
import '../../domain/engine/pikafish_engine.dart';
import '../shared/error_dialog.dart';

/// 引擎权重文件（pikafish.nnue）安装服务与引导对话框。
///
/// 权重文件不随安装包分发：用户通过系统文件选择器选中自己保存的
/// pikafish.nnue 后：
/// - Windows 上若所选路径为纯 ASCII（Pikafish 窄字符路径可以直接打开），
///   则直接记录原路径使用，不做复制；
/// - 路径含中文等非 ASCII 字符、或引擎报告无法加载时，再复制到应用
///   默认数据目录（文档目录/wuxingxiangqi），并记录副本路径。
///
/// 最终使用的绝对路径写入引擎配置持久保存。
class EvalFileService {
  EvalFileService._();

  /// 权重文件回退副本的标准路径（应用数据目录/pikafish.nnue）。
  static Future<String> canonicalPath() async {
    final dataDir = await ConfigManager.instance.dataDirPath;
    return p.join(dataDir, 'pikafish.nnue');
  }

  /// 配置中记录的权重路径（可能已失效）。
  static String? get savedPath =>
      ConfigManager.instance.config.engine.evalFilePath;

  /// 权重文件是否已就绪：已配置且文件实际存在。
  ///
  /// 不再要求路径为纯 ASCII：非 ASCII 路径先交由引擎尝试，加载失败时
  /// 引擎层会自动复制到数据目录后重试（仅 Windows）。
  static bool get isReady {
    final pth = savedPath;
    return pth != null && File(pth).existsSync();
  }

  /// 路径是否为纯 ASCII（Pikafish 在 Windows 上以窄字符打开权重，
  /// 纯 ASCII 路径可直接使用，无需复制）。
  static bool _isAscii(String path) => path.codeUnits.every((c) => c < 128);

  /// 弹出系统文件选择器让用户选择 pikafish.nnue，确定最终使用的路径
  /// 并保存到引擎配置。成功返回路径，取消返回 null。
  ///
  /// Windows + 纯 ASCII 路径：直接使用原文件，不复制；
  /// 其余情况：复制到应用数据目录后使用副本。
  static Future<String?> pickAndInstall() async {
    // file_picker 13：单文件选择静态方法，返回 PlatformFile?
    final picked = await FilePicker.pickFile(
      type: FileType.custom,
      allowedExtensions: const ['nnue'],
    );
    final srcPath = picked?.path;
    if (srcPath == null) return null;

    final src = File(srcPath);
    if (!await src.exists()) {
      throw FileSystemException('所选权重文件不存在', srcPath);
    }

    String finalPath;
    if (Platform.isWindows && _isAscii(srcPath)) {
      // Windows 下纯 ASCII 路径可被引擎直接打开，无需复制
      finalPath = srcPath;
    } else {
      // 非 ASCII 路径或非 Windows 平台：复制到应用数据目录的标准位置
      finalPath = await canonicalPath();
      final target = File(finalPath);
      if (!await target.parent.exists()) {
        await target.parent.create(recursive: true);
      }
      // 覆盖旧文件（重新选择时更新内容）
      await src.copy(finalPath);
    }

    await ConfigManager.instance.updateEngine((c) {
      c.evalFilePath = finalPath;
      return c;
    });
    // 权重更换后关闭旧引擎进程；下次分析/AI 走子时会以新权重自动重启
    await PikafishEngine.instance.dispose();
    return finalPath;
  }
}

/// 权重文件缺失引导对话框。
///
/// [show] 返回 true 表示用户已成功安装权重文件；取消/失败返回 false。
class EvalFileGuideDialog extends StatelessWidget {
  const EvalFileGuideDialog({super.key});

  static Future<bool> show(BuildContext context) async {
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const EvalFileGuideDialog(),
    );
    return result ?? false;
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: const Color(0xFFFDF6E3),
      insetPadding: const EdgeInsets.symmetric(horizontal: 28, vertical: 40),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: Color(0xFFC9B68C), width: 1.2),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.warning_amber_rounded,
                    color: Color(0xFF8B5A2B), size: 22),
                SizedBox(width: 8),
                Text(
                  '需要引擎权重文件',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF5A3A1A),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            const Text(
              '皮卡鱼引擎运行需要神经网络权重文件 pikafish.nnue，'
              '该文件不随应用内置，请按以下步骤操作：',
              style: TextStyle(fontSize: 13.5, color: Color(0xFF5A3A1A), height: 1.5),
            ),
            const SizedBox(height: 8),
            _step(1, '先把 pikafish.nnue 文件保存到手机或电脑的任意文件夹；'),
            _step(2, '点击下方「选择权重文件」按钮，在系统文件选择器中选中它；'),
            _step(3, 'Windows 上若路径不含中文等特殊字符会直接使用原文件，'
                '否则应用会自动复制到专用数据目录并保存，下次无需重复操作。'),
            const SizedBox(height: 8),
            const Text(
              '若之后文件被清理导致不存在，会再次提示重新选择。',
              style: TextStyle(fontSize: 12, color: Color(0xFF8B6B4A)),
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(false),
                  child: const Text('取消',
                      style: TextStyle(color: Color(0xFF8B5A2B))),
                ),
                const SizedBox(width: 8),
                FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF8B5A2B),
                  ),
                  icon: const Icon(Icons.folder_open, size: 18),
                  label: const Text('选择权重文件'),
                  onPressed: () => _pick(context),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _step(int n, String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 18,
            height: 18,
            margin: const EdgeInsets.only(top: 1),
            alignment: Alignment.center,
            decoration: const BoxDecoration(
              color: Color(0xFF8B5A2B),
              shape: BoxShape.circle,
            ),
            child: Text('$n',
                style: const TextStyle(
                    fontSize: 11,
                    color: Colors.white,
                    fontWeight: FontWeight.bold)),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                  fontSize: 13, color: Color(0xFF5A3A1A), height: 1.45),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _pick(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    try {
      final path = await EvalFileService.pickAndInstall();
      if (path == null) return; // 用户取消选择
      messenger.showSnackBar(
        const SnackBar(content: Text('权重文件安装成功')),
      );
      navigator.pop(true);
    } catch (e) {
      // 失败：弹窗报错，需用户手动关闭，不自动消失
      if (context.mounted) {
        await showErrorDialog(context, '权重文件安装失败：$e');
      }
    }
  }
}
