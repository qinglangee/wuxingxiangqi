import 'dart:io';

import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as p;

import '../../core/assets/asset_catalog.dart';
import '../../core/config/app_config.dart';
import '../../core/config/board_calibration_store.dart';
import '../../core/config/config_manager.dart';
import '../../core/theme/app_theme.dart';
import '../../domain/models/piece.dart';
import '../shared/error_dialog.dart';
import 'board_calibration_screen.dart';
import 'engine_settings_widget.dart';

/// 设置页面：用标签页分成四个部分。
///
/// 1. 引擎设置：引擎可执行文件、权重、思考时间、深度等。
/// 2. 界面设置：字号、颜色、背景等风格参数。
/// 3. 棋子棋盘：内层再分「棋盘 / 棋子」两个子标签，用 tiles 展示
///    `assets/images/boards/` 下的棋盘图片与 `assets/images/pieces/`
///    下的棋子套系，点击即选择并保存；经典代码绘制为默认方式。
/// 4. 其他：棋谱仓库等杂项设置。
///
/// 引擎 / 界面 / 其他三个标签页内容先留空占位，后续迭代逐步填充。
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tab = TabController(length: 4, vsync: this);

  @override
  void dispose() {
    _tab.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('设置'),
        bottom: TabBar(
          controller: _tab,
          labelColor: Colors.white,
          unselectedLabelColor: const Color(0xFFE8D5B0),
          indicatorColor: Colors.white,
          indicatorSize: TabBarIndicatorSize.label,
          labelStyle:
              const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
          tabs: const [
            Tab(text: '引擎设置'),
            Tab(text: '界面设置'),
            Tab(text: '棋子棋盘'),
            Tab(text: '其他'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tab,
        children: [
          const EngineSettingsWidget(),
          const _UiSettingsWidget(),
          const _PieceBoardSettings(),
          const _OtherSettingsWidget(),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// 界面设置：按钮工具条文字的统一管理开关
// ---------------------------------------------------------------------------

class _UiSettingsWidget extends StatelessWidget {
  const _UiSettingsWidget();

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: ConfigManager.instance,
      builder: (context, _) {
        final ui = ConfigManager.instance.config.ui;
        final cm = ConfigManager.instance;
        return ListView(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          children: [
            const Text(
              '按钮工具条',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.bold,
                color: Color(0xFF5A3A1A),
              ),
            ),
            const SizedBox(height: 8),
            Container(
              decoration: BoxDecoration(
                color: const Color(0xFFFDF6E3),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFFC9B68C)),
              ),
              child: Column(
                children: [
                  SwitchListTile(
                    title: const Text(
                      '统一管理文字显示',
                      style: TextStyle(fontSize: 14, color: Color(0xFF5A3A1A)),
                    ),
                    subtitle: const Text(
                      '开启后，页面中所有按钮工具条统一按下方开关显示或隐藏文字',
                      style: TextStyle(fontSize: 12, color: Color(0xFF8B6B4A)),
                    ),
                    value: ui.unifiedButtonLabels,
                    activeThumbColor: AppTheme.boardLine,
                    onChanged: cm.setUnifiedButtonLabels,
                  ),
                  const Divider(height: 1, indent: 16, endIndent: 16),
                  SwitchListTile(
                    title: Text(
                      '显示按钮文字',
                      style: TextStyle(
                        fontSize: 14,
                        color: ui.unifiedButtonLabels
                            ? const Color(0xFF5A3A1A)
                            : const Color(0xFFB0A48A),
                      ),
                    ),
                    subtitle: Text(
                      ui.unifiedButtonLabels
                          ? '统一管理开启时，所有工具条都使用该设置'
                          : '统一管理已关闭：各工具条按自身设置显示',
                      style: const TextStyle(
                          fontSize: 12, color: Color(0xFF8B6B4A)),
                    ),
                    value: ui.globalShowButtonLabels,
                    activeThumbColor: AppTheme.boardLine,
                    // 仅在统一管理开启时该全局开关生效
                    onChanged: ui.unifiedButtonLabels
                        ? cm.setGlobalShowButtonLabels
                        : null,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFFFF4DC),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFFE0C486)),
              ),
              child: const Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.info_outline, size: 18, color: Color(0xFF8B6B3D)),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '说明：在任意一个按钮工具条中点击「显示文字」按钮单独设置'
                      '文字是否显示时，会自动关闭统一管理，之后各工具条按各自的'
                      '设置显示。',
                      style:
                          TextStyle(fontSize: 12.5, color: Color(0xFF6B4A28), height: 1.5),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              '浮动星星',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.bold,
                color: Color(0xFF5A3A1A),
              ),
            ),
            const SizedBox(height: 8),
            Container(
              decoration: BoxDecoration(
                color: const Color(0xFFFDF6E3),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFFC9B68C)),
              ),
              child: Column(
                children: [
                  SwitchListTile(
                    title: const Text(
                      '缩放星（黄色）',
                      style: TextStyle(fontSize: 14, color: Color(0xFF5A3A1A)),
                    ),
                    subtitle: const Text(
                      '棋盘下边缘的五角星，上下拖动可整体缩放棋盘',
                      style: TextStyle(fontSize: 12, color: Color(0xFF8B6B4A)),
                    ),
                    value: ui.showScaleStar,
                    activeThumbColor: AppTheme.boardLine,
                    onChanged: cm.setShowScaleStar,
                  ),
                  const Divider(height: 1, indent: 16, endIndent: 16),
                  SwitchListTile(
                    title: const Text(
                      '菜单星（红色）',
                      style: TextStyle(fontSize: 14, color: Color(0xFF5A3A1A)),
                    ),
                    subtitle: const Text(
                      '打谱页的五角星菜单，点击环形展开常驻按钮',
                      style: TextStyle(fontSize: 12, color: Color(0xFF8B6B4A)),
                    ),
                    value: ui.showMenuStar,
                    activeThumbColor: AppTheme.boardLine,
                    onChanged: cm.setShowMenuStar,
                  ),
                  const Divider(height: 1, indent: 16, endIndent: 16),
                  SwitchListTile(
                    title: const Text(
                      '标签星（绿色）',
                      style: TextStyle(fontSize: 14, color: Color(0xFF5A3A1A)),
                    ),
                    subtitle: const Text(
                      '打谱页的五角星开关，点击切换三个标签页的显隐',
                      style: TextStyle(fontSize: 12, color: Color(0xFF8B6B4A)),
                    ),
                    value: ui.showTabStar,
                    activeThumbColor: AppTheme.boardLine,
                    onChanged: cm.setShowTabStar,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            // 恢复默认按钮：清除全部 UI 相关配置
            FilledButton.icon(
              onPressed: () async {
                final ok = await showDialog<bool>(
                      context: context,
                      builder: (ctx) => AlertDialog(
                        title: const Text('恢复默认'),
                        content: const Text('确定要将所有界面设置恢复为默认值吗？\n'
                            '按钮工具条顺序、常驻列表、文字开关、浮动星星等'
                            '全部 UI 配置将被清除。'),
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
                await cm.resetUiToDefaults();
              },
              icon: const Icon(Icons.restart_alt),
              label: const Text('恢复默认'),
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF8B6B3D),
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

// ---------------------------------------------------------------------------
// 其他设置：应用配置文件保存位置等信息
// ---------------------------------------------------------------------------

class _OtherSettingsWidget extends StatelessWidget {
  const _OtherSettingsWidget();

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
                      dir,
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
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('备份完成：$path')),
                    );
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

// ---------------------------------------------------------------------------
// 棋子棋盘设置：内层「棋盘 / 棋子」子标签 + tiles 选择
// ---------------------------------------------------------------------------

class _PieceBoardSettings extends StatefulWidget {
  const _PieceBoardSettings();

  @override
  State<_PieceBoardSettings> createState() => _PieceBoardSettingsState();
}

class _PieceBoardSettingsState extends State<_PieceBoardSettings>
    with SingleTickerProviderStateMixin {
  late final TabController _tab = TabController(length: 2, vsync: this);

  // 资源清单加载一次缓存，避免每次 build 重复扫描
  late final Future<List<String>> _boards = AssetCatalog.loadBoards();
  late final Future<List<String>> _pieceSets = AssetCatalog.loadPieceSets();

  // 数据目录棋盘图片（可删除），刷新时重新加载
  List<String> _dataBoards = const [];

  Future<void> _reloadDataBoards() async {
    final dataDir = await ConfigManager.instance.dataDirPath;
    final boards = await AssetCatalog.loadDataBoards(dataDir);
    if (mounted) setState(() => _dataBoards = boards);
  }

  BoardConfig get _cfg => ConfigManager.instance.config.board;

  @override
  void initState() {
    super.initState();
    _reloadDataBoards();
  }

  @override
  void dispose() {
    _tab.dispose();
    super.dispose();
  }

  /// 选择棋盘：null 表示经典代码绘制。
  Future<void> _pickBoard(String? fileName) async {
    await ConfigManager.instance.updateBoard((c) {
      if (fileName == null) {
        c.boardType = BoardConfig.kTypeClassic;
        c.boardStyle = 'classic';
      } else {
        c.boardType = BoardConfig.kTypeImage;
        c.boardStyle = fileName;
      }
      c.customBoardPath = null; // 内置资源棋盘始终清除自定义路径
      return c;
    });
    if (mounted) setState(() {});
  }

  /// 选择数据目录中的自定义棋盘图片。
  Future<void> _pickDataBoard(String filePath) async {
    final name = p.basename(filePath);
    await ConfigManager.instance.updateBoard((c) {
      c.boardType = BoardConfig.kTypeImage;
      c.boardStyle = name;
      c.customBoardPath = filePath;
      return c;
    });
    if (mounted) setState(() {});
  }

  /// 删除数据目录中的自定义棋盘图片。
  Future<void> _deleteDataBoard(String filePath) async {
    try {
      final file = File(filePath);
      if (await file.exists()) await file.delete();
      // 若删除的是当前选中的棋盘，回退到经典绘制
      if (_cfg.customBoardPath == filePath) {
        await _pickBoard(null);
      }
      // 清除该棋盘的对齐数据
      BoardCalibrationStore.instance.reset(filePath);
      await _reloadDataBoards();
    } catch (_) {
      // 静默失败
    }
  }

  /// 选择棋子套系：null 表示经典代码绘制。
  Future<void> _pickPieceSet(String? setName) async {
    await ConfigManager.instance.updateBoard((c) {
      if (setName == null) {
        c.pieceType = BoardConfig.kTypeClassic;
        c.pieceStyle = 'classic';
      } else {
        c.pieceType = BoardConfig.kTypeImage;
        c.pieceStyle = setName;
      }
      return c;
    });
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Material(
          color: const Color(0xFFF5E6C8),
          child: TabBar(
            controller: _tab,
            labelColor: AppTheme.boardLine,
            unselectedLabelColor: const Color(0xFF8B6B3D),
            indicatorColor: AppTheme.boardLine,
            indicatorSize: TabBarIndicatorSize.label,
            labelStyle:
                const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
            tabs: const [
              Tab(text: '棋盘'),
              Tab(text: '棋子'),
            ],
          ),
        ),
        Expanded(
          child: TabBarView(
            controller: _tab,
            children: [
              _buildBoardGrid(),
              _buildPieceGrid(),
            ],
          ),
        ),
      ],
    );
  }

  /// 棋盘选择网格：第一项经典绘制（默认），之后为内置资源棋盘图片，
  /// 最后为数据目录（wuxingxiangqi/images/board/）下的自定义棋盘图片。
  /// 自定义棋盘额外带删除按钮。
  Widget _buildBoardGrid() {
    final useImage = _cfg.boardType == BoardConfig.kTypeImage;
    return ListenableBuilder(
      listenable: BoardCalibrationStore.instance,
      builder: (context, _) => FutureBuilder<List<String>>(
        future: _boards,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator(strokeWidth: 2));
          }
          final assetBoards = snap.data ?? const <String>[];
          final dataBoards = _dataBoards;
          final total = assetBoards.length + dataBoards.length + 1;
          return GridView.builder(
            padding: const EdgeInsets.all(12),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3,
              mainAxisSpacing: 10,
              crossAxisSpacing: 10,
              childAspectRatio: 0.72,
            ),
            itemCount: total,
            itemBuilder: (context, i) {
              if (i == 0) {
                return _OptionTile(
                  selected: !useImage,
                  label: '经典绘制（默认）',
                  onTap: () => _pickBoard(null),
                  child: const Icon(Icons.draw,
                      size: 40, color: Color(0xFF8B6B3D)),
                );
              }
              // 内置资源棋盘
              if (i <= assetBoards.length) {
                final name = assetBoards[i - 1];
                final calibrated = BoardCalibrationStore.instance.has(name);
                return _OptionTile(
                  selected: useImage &&
                      _cfg.customBoardPath == null &&
                      _cfg.boardStyle == name,
                  label: _prettyName(name),
                  onTap: () => _pickBoard(name),
                  child: Stack(
                    children: [
                      Positioned.fill(
                        child: Image.asset(
                          AssetCatalog.boardAsset(name),
                          fit: BoxFit.contain,
                          errorBuilder: (_, _, _) => const Icon(
                            Icons.broken_image,
                            size: 36,
                            color: Color(0xFFB0A48A),
                          ),
                        ),
                      ),
                      Positioned(
                        left: 0,
                        top: 0,
                        child: _CalibrateButton(
                          calibrated: calibrated,
                          onPressed: () => _openCalibration(name),
                        ),
                      ),
                    ],
                  ),
                );
              }
              // 数据目录自定义棋盘
              final idx = i - assetBoards.length - 1;
              final filePath = dataBoards[idx];
              final name = p.basename(filePath);
              final calibrated =
                  BoardCalibrationStore.instance.has(filePath);
              final selected =
                  useImage && _cfg.customBoardPath == filePath;
              return _OptionTile(
                selected: selected,
                label: _prettyName(name),
                onTap: () => _pickDataBoard(filePath),
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: Image.file(
                        File(filePath),
                        fit: BoxFit.contain,
                        errorBuilder: (_, _, _) => const Icon(
                          Icons.broken_image,
                          size: 36,
                          color: Color(0xFFB0A48A),
                        ),
                      ),
                    ),
                    // 适配按钮
                    Positioned(
                      left: 0,
                      top: 0,
                      child: _CalibrateButton(
                        calibrated: calibrated,
                        onPressed: () =>
                            _openCalibration(name, filePath: filePath),
                      ),
                    ),
                    // 删除按钮
                    Positioned(
                      right: 0,
                      top: 0,
                      child: _DeleteBoardButton(
                        onPressed: () => _deleteDataBoard(filePath),
                      ),
                    ),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }

  void _openCalibration(String boardFileName, {String? filePath}) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => BoardCalibrationScreen(
          boardFileName: boardFileName,
          boardDisplayName: _prettyName(boardFileName),
          boardFilePath: filePath,
        ),
      ),
    );
  }

  /// 棋子选择网格：顶部为棋子大小与阴影设置区，其下第一项为经典绘制
  /// （默认），之后为所有棋子套系。每个套系用红帅 + 黑将两张图片预览。
  Widget _buildPieceGrid() {
    final useImage = _cfg.pieceType == BoardConfig.kTypeImage;
    return FutureBuilder<List<String>>(
      future: _pieceSets,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator(strokeWidth: 2));
        }
        final sets = snap.data ?? const <String>[];
        return CustomScrollView(
          slivers: [
            // 顶部：棋子大小与阴影设置
            const SliverToBoxAdapter(child: _PieceAdjustSettings()),
            // 棋子套系选择网格
            SliverPadding(
              padding: const EdgeInsets.all(12),
              sliver: SliverGrid(
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 3,
                  mainAxisSpacing: 10,
                  crossAxisSpacing: 10,
                  childAspectRatio: 0.72,
                ),
                delegate: SliverChildBuilderDelegate(
                  childCount: sets.length + 1,
                  (context, i) {
                    if (i == 0) {
                      return _OptionTile(
                        selected: !useImage,
                        label: '经典绘制（默认）',
                        onTap: () => _pickPieceSet(null),
                        child: const Icon(Icons.font_download,
                            size: 40, color: Color(0xFF8B6B3D)),
                      );
                    }
                    final name = sets[i - 1];
                    return _OptionTile(
                      selected: useImage && _cfg.pieceStyle == name,
                      label: name,
                      onTap: () => _pickPieceSet(name),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          _piecePreview(name, Side.red),
                          const SizedBox(width: 4),
                          _piecePreview(name, Side.black),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _piecePreview(String setName, Side side) {
    return Image.asset(
      AssetCatalog.pieceAsset(setName, side, PieceType.general),
      width: 32,
      height: 32,
      errorBuilder: (_, _, _) => const Icon(
        Icons.broken_image,
        size: 28,
        color: Color(0xFFB0A48A),
      ),
    );
  }

  /// 去掉扩展名，作为展示名。
  static String _prettyName(String fileName) {
    final dot = fileName.lastIndexOf('.');
    return dot > 0 ? fileName.substring(0, dot) : fileName;
  }
}

/// 棋子标签页顶部的「大小 / 阴影」设置区。
///
/// 棋子大小按默认大小的百分比调整（20%-200%）；阴影含开关、半径
/// （棋子半径的倍数）、水平/垂直偏移（棋子半径的倍数，正负均可：
/// 正值向右/向下、负值向左/向上，默认偏移右下方）与模糊程度（像素）。
/// 所有修改即时落盘，ConfigManager 通知后由 ListenableBuilder 自动刷新。
class _PieceAdjustSettings extends StatelessWidget {
  const _PieceAdjustSettings();

  BoardConfig get _cfg => ConfigManager.instance.config.board;

  /// 修改棋盘配置并落盘。
  Future<void> _update(void Function(BoardConfig c) apply) =>
      ConfigManager.instance.updateBoard((c) {
        apply(c);
        return c;
      });

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: ConfigManager.instance,
      builder: (context, _) {
        final cfg = _cfg;
        return Container(
          margin: const EdgeInsets.fromLTRB(12, 12, 12, 0),
          padding: const EdgeInsets.fromLTRB(12, 4, 12, 10),
          decoration: BoxDecoration(
            color: const Color(0xFFFDF6E3),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: const Color(0xFFC9B68C)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _sliderRow(
                label: '棋子大小',
                value: cfg.pieceSizeScale,
                min: BoardConfig.kMinPieceSizeScale,
                max: BoardConfig.kMaxPieceSizeScale,
                divisions: 18,
                format: (v) => '${(v * 100).round()}%',
                onChanged: (v) => _update((c) => c.pieceSizeScale = v),
              ),
              const Divider(height: 10, color: Color(0xFFC9B68C)),
              Row(
                children: [
                  const SizedBox(
                    width: 64,
                    child: Text(
                      '棋子阴影',
                      style:
                          TextStyle(fontSize: 13, color: Color(0xFF5A3A1A)),
                    ),
                  ),
                  Switch(
                    value: cfg.pieceShadow,
                    activeThumbColor: AppTheme.boardLine,
                    onChanged: (v) => _update((c) => c.pieceShadow = v),
                  ),
                  Expanded(
                    child: Text(
                      cfg.pieceShadow ? '默认偏移右下方' : '已关闭',
                      style: const TextStyle(
                          fontSize: 12, color: Color(0xFF8B6B4A)),
                    ),
                  ),
                ],
              ),
              _sliderRow(
                label: '阴影半径',
                value: cfg.shadowRadiusFactor,
                min: BoardConfig.kMinShadowRadiusFactor,
                max: BoardConfig.kMaxShadowRadiusFactor,
                divisions: 18,
                format: (v) => '${v.toStringAsFixed(1)} 倍',
                onChanged: (v) => _update((c) => c.shadowRadiusFactor = v),
                enabled: cfg.pieceShadow,
              ),
              _sliderRow(
                label: '水平偏移',
                value: cfg.shadowOffsetXFactor,
                min: BoardConfig.kMinShadowOffsetFactor,
                max: BoardConfig.kMaxShadowOffsetFactor,
                divisions: 40,
                format: (v) => v.toStringAsFixed(2),
                onChanged: (v) => _update((c) => c.shadowOffsetXFactor = v),
                enabled: cfg.pieceShadow,
              ),
              _sliderRow(
                label: '垂直偏移',
                value: cfg.shadowOffsetYFactor,
                min: BoardConfig.kMinShadowOffsetFactor,
                max: BoardConfig.kMaxShadowOffsetFactor,
                divisions: 40,
                format: (v) => v.toStringAsFixed(2),
                onChanged: (v) => _update((c) => c.shadowOffsetYFactor = v),
                enabled: cfg.pieceShadow,
              ),
              _sliderRow(
                label: '模糊程度',
                value: cfg.shadowBlur,
                min: BoardConfig.kMinShadowBlur,
                max: BoardConfig.kMaxShadowBlur,
                divisions: 40,
                format: (v) => '${v.toStringAsFixed(1)} px',
                onChanged: (v) => _update((c) => c.shadowBlur = v),
                enabled: cfg.pieceShadow,
              ),
            ],
          ),
        );
      },
    );
  }

  /// 单行滑块：左侧固定宽标签、中间滑条、右侧当前值。
  Widget _sliderRow({
    required String label,
    required double value,
    required double min,
    required double max,
    required int divisions,
    required String Function(double) format,
    required ValueChanged<double> onChanged,
    bool enabled = true,
  }) {
    final textColor = enabled
        ? const Color(0xFF5A3A1A)
        : const Color(0xFFB0A48A);
    return Row(
      children: [
        SizedBox(
          width: 64,
          child: Text(
            label,
            style: TextStyle(fontSize: 13, color: textColor),
          ),
        ),
        Expanded(
          child: Slider(
            value: value.clamp(min, max).toDouble(),
            min: min,
            max: max,
            divisions: divisions,
            label: format(value),
            onChanged: enabled ? onChanged : null,
          ),
        ),
        SizedBox(
          width: 56,
          child: Text(
            format(value),
            textAlign: TextAlign.right,
            style: TextStyle(fontSize: 12, color: textColor),
          ),
        ),
      ],
    );
  }
}

/// 棋盘缩略图上的「适配」小按钮：已适配时变为绿色（图标不变），
/// 未适配时为中性描边图标。点击进入棋盘格子对齐页面。
class _CalibrateButton extends StatelessWidget {
  const _CalibrateButton({
    required this.calibrated,
    required this.onPressed,
  });

  final bool calibrated;
  final VoidCallback onPressed;

  /// 已适配的绿色。
  static const _green = Color(0xFF2E7D32);

  @override
  Widget build(BuildContext context) {
    return Material(
      color: calibrated
          ? _green.withValues(alpha: 0.85)
          : Colors.white.withValues(alpha: 0.75),
      shape: CircleBorder(
        side: BorderSide(
          color: calibrated ? _green : const Color(0xFF8B5A2B),
          width: 0.8,
        ),
      ),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onPressed,
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Icon(
            // 适配前后使用同一图标，仅改变颜色
            Icons.tune,
            size: 30,
            color: calibrated ? Colors.white : const Color(0xFF8B5A2B),
          ),
        ),
      ),
    );
  }
}

/// 自定义棋盘图片的删除按钮：右上角红色小圆形。
class _DeleteBoardButton extends StatelessWidget {
  const _DeleteBoardButton({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.red.shade700,
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onPressed,
        child: const Padding(
          padding: EdgeInsets.all(5),
          child: Icon(Icons.close, size: 16, color: Colors.white),
        ),
      ),
    );
  }
}

/// 可选项 tile：上方预览区 + 下方名称，选中时描边高亮并显示勾。
class _OptionTile extends StatelessWidget {
  const _OptionTile({
    required this.selected,
    required this.label,
    required this.child,
    required this.onTap,
  });

  final bool selected;
  final String label;
  final Widget child;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        decoration: BoxDecoration(
          color: const Color(0xFFFDF6E3),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color:
                selected ? const Color(0xFF8B5A2B) : const Color(0xFFC9B68C),
            width: selected ? 2 : 1,
          ),
        ),
        child: Stack(
          children: [
            Padding(
              padding: const EdgeInsets.all(6),
              child: Column(
                children: [
                  Expanded(child: Center(child: child)),
                  const SizedBox(height: 4),
                  Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 11, color: Color(0xFF8B6B3D)),
                  ),
                ],
              ),
            ),
            if (selected)
              const Positioned(
                right: 4,
                top: 4,
                child: Icon(Icons.check_circle,
                    size: 36, color: Color(0xFF2E7D32)),
              ),
          ],
        ),
      ),
    );
  }
}
