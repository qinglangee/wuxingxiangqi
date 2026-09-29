import 'package:flutter/material.dart';

import '../../../core/config/app_config.dart';
import '../../../core/config/config_manager.dart';
import '../../../core/theme/app_theme.dart';
import '../../../domain/engine/pikafish_engine.dart';
import '../../shared/error_dialog.dart';
import '../eval_file_dialog.dart';

/// 引擎设置控件：性能（滑块）+ 棋规（下拉框）两部分。
///
/// 可在设置页的「引擎设置」标签中直接使用，也可通过 [EngineSettingsDialog]
/// 以浮动弹窗形式在任意页面调出。修改值后立即保存并实时下发到引擎。
class EngineSettingsWidget extends StatelessWidget {
  const EngineSettingsWidget({super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: ConfigManager.instance,
      builder: (_, _) {
        final cfg = ConfigManager.instance.config.engine;
        return SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _sectionTitle('性能'),
              const SizedBox(height: 8),
              _sliderRow(
                label: '线程数',
                value: cfg.threads.toDouble(),
                min: EngineConfig.kMinThreads.toDouble(),
                max: EngineConfig.kMaxThreads.toDouble(),
                divisions: EngineConfig.kMaxThreads - EngineConfig.kMinThreads,
                format: (v) => '${v.toInt()}',
                onChanged: (v) => _update((c) => c.threads = v.toInt()),
              ),
              _sliderRow(
                label: '哈希表',
                value: cfg.hashSizeMb.toDouble(),
                min: EngineConfig.kMinHashMb.toDouble(),
                max: EngineConfig.kMaxHashMb.toDouble(),
                divisions: 32,
                format: (v) => '${v.toInt()} MB',
                onChanged: (v) => _update((c) => c.hashSizeMb = v.toInt()),
              ),
              _sliderRow(
                label: '思考时间',
                value: cfg.moveTimeMs.toDouble(),
                min: EngineConfig.kMinMoveTimeMs.toDouble(),
                max: EngineConfig.kMaxMoveTimeMs.toDouble(),
                divisions: 60,
                format: (v) => '${(v / 1000).toStringAsFixed(1)} 秒',
                onChanged: (v) => _update((c) => c.moveTimeMs = v.toInt()),
              ),
              _sliderRow(
                label: 'PV 数',
                value: cfg.multiPv.toDouble(),
                min: EngineConfig.kMinMultiPv.toDouble(),
                max: EngineConfig.kMaxMultiPv.toDouble(),
                divisions: EngineConfig.kMaxMultiPv - EngineConfig.kMinMultiPv,
                format: (v) => '${v.toInt()}',
                onChanged: (v) => _update((c) => c.multiPv = v.toInt()),
              ),
              _sliderRow(
                label: '分析深度',
                value: (cfg.depth ?? 20).toDouble(),
                min: EngineConfig.kMinDepth.toDouble(),
                max: EngineConfig.kMaxDepth.toDouble(),
                divisions: EngineConfig.kMaxDepth - EngineConfig.kMinDepth,
                format: (v) => '${v.toInt()}',
                onChanged: (v) => _update((c) => c.depth = v.toInt()),
              ),
              const SizedBox(height: 20),
              _sectionTitle('棋规'),
              const SizedBox(height: 8),
              _ruleDropdown(cfg.rule),
              const SizedBox(height: 20),
              _sectionTitle('权重文件'),
              const SizedBox(height: 8),
              const _EvalFileTile(),
            ],
          ),
        );
      },
    );
  }

  Widget _sectionTitle(String title) {
    return Text(
      title,
      style: const TextStyle(
        fontSize: 15,
        fontWeight: FontWeight.w600,
        color: AppTheme.boardLine,
      ),
    );
  }

  Widget _sliderRow({
    required String label,
    required double value,
    required double min,
    required double max,
    required int divisions,
    required String Function(double) format,
    required ValueChanged<double> onChanged,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          SizedBox(
            width: 70,
            child: Text(
              label,
              style: const TextStyle(fontSize: 13, color: Color(0xFF5A3A1A)),
            ),
          ),
          Expanded(
            child: Slider(
              value: value.clamp(min, max),
              min: min,
              max: max,
              divisions: divisions,
              activeColor: AppTheme.boardLine,
              onChanged: onChanged,
            ),
          ),
          SizedBox(
            width: 70,
            child: Text(
              format(value),
              textAlign: TextAlign.right,
              style: const TextStyle(fontSize: 13, color: Color(0xFF5A3A1A)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _ruleDropdown(ChessRule current) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: const Color(0xFFFDF6E3),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFC9B68C)),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<ChessRule>(
          value: current,
          isExpanded: true,
          style: const TextStyle(fontSize: 14, color: Color(0xFF5A3A1A)),
          items: ChessRule.values
              .map((r) => DropdownMenuItem(value: r, child: Text(r.label)))
              .toList(),
          onChanged: (v) {
            if (v != null) _update((c) => c.rule = v);
          },
        ),
      ),
    );
  }

  void _update(void Function(EngineConfig c) mutate) {
    ConfigManager.instance.updateEngine((c) {
      mutate(c);
      return c;
    }).then((_) {
      PikafishEngine.instance.applyOptions();
    });
  }
}

/// 权重文件设置项：显示安装状态与路径，提供选择/重新选择入口。
class _EvalFileTile extends StatelessWidget {
  const _EvalFileTile();

  @override
  Widget build(BuildContext context) {
    final path = ConfigManager.instance.config.engine.evalFilePath;
    final ready = EvalFileService.isReady;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFFDF6E3),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFC9B68C)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                ready ? Icons.check_circle : Icons.error_outline,
                size: 16,
                color: ready ? const Color(0xFF2E7D32) : const Color(0xFFC62828),
              ),
              const SizedBox(width: 6),
              Text(
                ready ? '已就绪' : '未配置或文件不存在',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color:
                      ready ? const Color(0xFF2E7D32) : const Color(0xFFC62828),
                ),
              ),
              const Spacer(),
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFF8B5A2B),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  minimumSize: const Size(0, 32),
                  visualDensity: VisualDensity.compact,
                ),
                icon: const Icon(Icons.folder_open, size: 16),
                label: Text(ready ? '重新选择' : '选择文件'),
                onPressed: () => _pick(context),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            ready ? path! : '引擎运行需要 pikafish.nnue 权重文件',
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 11.5, color: Color(0xFF8B6B4A)),
          ),
          // 未配置时，除了「选择文件」按钮，也提示可自行把文件放到
          // 应用默认数据目录（放好后引擎下次启动会自动识别）。
          if (!ready) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: const Color(0xFFFFF4DC),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: const Color(0xFFE0C486)),
              ),
              child: FutureBuilder<String>(
                future: EvalFileService.canonicalPath(),
                builder: (context, snapshot) {
                  final target = snapshot.data;
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        '也可以自行把 pikafish.nnue 权重文件放到以下位置，'
                        '应用下次使用引擎时会自动识别：',
                        style: TextStyle(
                            fontSize: 11.5,
                            color: Color(0xFF6B4A28),
                            height: 1.45),
                      ),
                      const SizedBox(height: 4),
                      if (target != null)
                        SelectableText(
                          target,
                          style: const TextStyle(
                            fontSize: 11.5,
                            color: Color(0xFF3A2410),
                            fontWeight: FontWeight.w600,
                          ),
                        )
                      else
                        const Text(
                          '路径读取中…',
                          style: TextStyle(
                              fontSize: 11.5, color: Color(0xFFB0A48A)),
                        ),
                    ],
                  );
                },
              ),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _pick(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final path = await EvalFileService.pickAndInstall();
      if (path != null) {
        messenger.showSnackBar(
          const SnackBar(content: Text('权重文件安装成功')),
        );
      }
    } catch (e) {
      // 失败：弹窗报错，需用户手动关闭，不自动消失
      if (context.mounted) {
        await showErrorDialog(context, '权重文件安装失败：$e');
      }
    }
  }
}

/// 引擎设置浮动弹窗：在任意页面通过按钮点击调出。
class EngineSettingsDialog extends StatelessWidget {
  const EngineSettingsDialog({super.key});

  static Future<void> show(BuildContext context) {
    return showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (_) => const EngineSettingsDialog(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    return Dialog(
      backgroundColor: const Color(0xFFFDF6E3),
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: Color(0xFFC9B68C), width: 1.2),
      ),
      child: SizedBox(
        width: media.size.width * 0.9,
        height: media.size.height * 0.75,
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: const BoxDecoration(
                color: Color(0xFF8B5A2B),
                borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.settings, color: Colors.white, size: 20),
                  const SizedBox(width: 8),
                  const Text(
                    '引擎设置',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.white, size: 18),
                    visualDensity: VisualDensity.compact,
                    padding: EdgeInsets.zero,
                    constraints:
                        const BoxConstraints(minWidth: 28, minHeight: 28),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),
            const Divider(height: 1, color: Color(0xFFC9B68C)),
            const Expanded(child: EngineSettingsWidget()),
          ],
        ),
      ),
    );
  }
}
