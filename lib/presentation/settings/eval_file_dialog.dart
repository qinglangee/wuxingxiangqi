import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../core/config/config_manager.dart';
import '../../domain/engine/pikafish_engine.dart';

/// 引擎权重文件（pikafish.nnue）安装服务与引导对话框。
///
/// 权重文件不随安装包分发：用户通过系统文件选择器选中自己保存的
/// pikafish.nnue 后，应用把它复制到临时目录下的 pikafish 子目录
/// （同时是引擎进程的工作目录），并将绝对路径写入引擎配置持久保存。
///
/// 必须使用该位置：Pikafish 在 Windows 上以窄字符路径打开权重，
/// 应用支持目录含中文（如 `五星象棋`）时 UTF-8 路径无法被正确解析，
/// 会报 "network file ... was not loaded successfully"。
class EvalFileService {
  EvalFileService._();

  /// 权重文件的标准安装路径（临时目录/pikafish/pikafish.nnue，ASCII 路径）。
  static Future<String> canonicalPath() async {
    final tmp = await getTemporaryDirectory();
    return p.join(tmp.path, 'pikafish', 'pikafish.nnue');
  }

  /// 配置中记录的权重路径（可能已失效）。
  static String? get savedPath =>
      ConfigManager.instance.config.engine.evalFilePath;

  /// 权重文件是否已就绪：已配置、路径为纯 ASCII（Pikafish 无法打开
  /// 含中文等非 ASCII 字符的权重路径）且文件存在。
  static bool get isReady {
    final pth = savedPath;
    return pth != null &&
        pth.codeUnits.every((c) => c < 128) &&
        File(pth).existsSync();
  }

  /// 弹出系统文件选择器让用户选择 pikafish.nnue，复制到标准路径，
  /// 并保存路径到引擎配置。成功返回安装后的绝对路径，取消/失败返回 null。
  static Future<String?> pickAndInstall() async {
    // file_picker 13：单文件选择静态方法，返回 PlatformFile?
    final picked = await FilePicker.pickFile(
      type: FileType.custom,
      allowedExtensions: const ['nnue'],
    );
    final srcPath = picked?.path;
    if (srcPath == null) return null;

    final targetPath = await canonicalPath();
    final target = File(targetPath);
    if (!await target.parent.exists()) {
      await target.parent.create(recursive: true);
    }
    // 覆盖旧文件（重新选择时更新内容）
    await File(srcPath).copy(targetPath);

    await ConfigManager.instance.updateEngine((c) {
      c.evalFilePath = targetPath;
      return c;
    });
    // 权重更换后关闭旧引擎进程；下次分析/AI 走子时会以新权重自动重启
    await PikafishEngine.instance.dispose();
    return targetPath;
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
            _step(3, '应用会自动把文件复制到专用位置并保存，下次使用无需重复操作。'),
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
      messenger.showSnackBar(
        SnackBar(content: Text('权重文件安装失败：$e')),
      );
    }
  }
}
