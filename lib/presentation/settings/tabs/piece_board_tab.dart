import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../../../core/assets/asset_catalog.dart';
import '../../../core/config/app_config.dart';
import '../../../core/config/board_calibration_store.dart';
import '../../../core/config/config_manager.dart';
import '../../../core/theme/app_theme.dart';
import '../../../domain/models/piece.dart';
import '../board_calibration_screen.dart';

// ---------------------------------------------------------------------------
// 棋子棋盘设置：内层「棋盘 / 棋子」子标签 + tiles 选择
// ---------------------------------------------------------------------------

class PieceBoardTab extends StatefulWidget {
  const PieceBoardTab({super.key});

  @override
  State<PieceBoardTab> createState() => _PieceBoardSettingsState();
}

class _PieceBoardSettingsState extends State<PieceBoardTab>
    with SingleTickerProviderStateMixin {
  late final TabController _tab = TabController(length: 2, vsync: this);

  // 资源清单加载一次缓存，避免每次 build 重复扫描
  late final Future<List<String>> _boards = AssetCatalog.loadBoards();
  late final Future<List<String>> _pieceSets = AssetCatalog.loadPieceSets();

  // 数据目录棋盘图片（可删除），刷新时重新加载
  List<String> _dataBoards = const [];
  // 数据目录棋子套系目录路径（可删除），刷新时重新加载
  List<String> _dataPieceSets = const [];

  Future<void> _reloadDataBoards() async {
    final dataDir = await ConfigManager.instance.dataDirPath;
    final boards = await AssetCatalog.loadDataBoards(dataDir);
    if (mounted) setState(() => _dataBoards = boards);
  }

  Future<void> _reloadDataPieceSets() async {
    final dataDir = await ConfigManager.instance.dataDirPath;
    final sets = await AssetCatalog.loadDataPieceSets(dataDir);
    if (mounted) setState(() => _dataPieceSets = sets);
  }

  BoardConfig get _cfg => ConfigManager.instance.config.board;

  @override
  void initState() {
    super.initState();
    _reloadDataBoards();
    _reloadDataPieceSets();
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
      c.customPiecePath = null; // 内置资源套系清除自定义路径
      return c;
    });
    if (mounted) setState(() {});
  }

  /// 选择数据目录中的自定义棋子套系。
  Future<void> _pickDataPieceSet(String dirPath) async {
    final name = p.basename(dirPath);
    await ConfigManager.instance.updateBoard((c) {
      c.pieceType = BoardConfig.kTypeImage;
      c.pieceStyle = name;
      c.customPiecePath = dirPath;
      return c;
    });
    if (mounted) setState(() {});
  }

  /// 删除数据目录中的自定义棋子套系目录。
  Future<void> _deleteDataPieceSet(String dirPath) async {
    try {
      final dir = Directory(dirPath);
      if (await dir.exists()) await dir.delete(recursive: true);
      if (_cfg.customPiecePath == dirPath) {
        await _pickPieceSet(null);
      }
      await _reloadDataPieceSets();
    } catch (_) {
      // 静默失败
    }
  }

  /// 导入棋盘图片：选择图片文件，复制到数据目录 images/board/ 下。
  Future<void> _importBoard() async {
    final picked = await FilePicker.pickFiles(
      dialogTitle: '选择棋盘图片',
      type: FileType.image,
    );
    if (picked.isEmpty) return;
    final srcPath = picked.single.path;
    if (srcPath == null) return;
    try {
      final dataDir = await ConfigManager.instance.dataDirPath;
      final destDir = Directory(p.join(dataDir, 'images', 'board'));
      if (!await destDir.exists()) {
        await destDir.create(recursive: true);
      }
      final destPath = p.join(destDir.path, p.basename(srcPath));
      await File(srcPath).copy(destPath);
      await _reloadDataBoards();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('棋盘已导入')),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('导入失败')),
        );
      }
    }
  }

  /// 导入棋子套系：选择目录，复制到数据目录 images/pieces/ 下。
  Future<void> _importPieceSet() async {
    final srcDirPath = await FilePicker.getDirectoryPath(
      dialogTitle: '选择棋子套系目录',
    );
    if (srcDirPath == null) return;
    try {
      final dataDir = await ConfigManager.instance.dataDirPath;
      final destDirPath = p.join(
          dataDir, 'images', 'pieces', p.basename(srcDirPath));
      final destDir = Directory(destDirPath);
      if (!await destDir.exists()) {
        await destDir.create(recursive: true);
      }
      // 复制目录下所有文件
      final srcDir = Directory(srcDirPath);
      await for (final entity in srcDir.list()) {
        if (entity is File) {
          await entity.copy(p.join(destDirPath, p.basename(entity.path)));
        }
      }
      await _reloadDataPieceSets();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('棋子套系已导入')),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('导入失败')),
        );
      }
    }
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
          return Column(
            children: [
              // 导入棋盘按钮
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: _importBoard,
                    icon: const Icon(Icons.add_photo_alternate, size: 20),
                    label: const Text('导入棋盘(请先改好图片名，同名会覆盖现有棋盘)'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppTheme.boardLine,
                      side: const BorderSide(color: AppTheme.boardLine),
                      padding: const EdgeInsets.symmetric(vertical: 22, horizontal: 22),
                    ),
                  ),
                ),
              ),
              Expanded(
                child: GridView.builder(
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
          ),
              ),
            ],
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
  /// （默认），之后为内置资源棋子套系，最后为数据目录
  /// （wuxingxiangqi/images/pieces/）下的自定义套系。
  /// 自定义套系额外带删除按钮（右下角）。
  Widget _buildPieceGrid() {
    final useImage = _cfg.pieceType == BoardConfig.kTypeImage;
    return FutureBuilder<List<String>>(
      future: _pieceSets,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator(strokeWidth: 2));
        }
        final assetSets = snap.data ?? const <String>[];
        final dataSets = _dataPieceSets;
        final total = assetSets.length + dataSets.length + 1;
        return CustomScrollView(
          slivers: [
            // 顶部：棋子大小与阴影设置
            const SliverToBoxAdapter(child: _PieceAdjustSettings()),
            // 导入棋子按钮
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 4),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: _importPieceSet,
                    icon: const Icon(Icons.create_new_folder, size: 20),
                    label: const Text('导入棋子(请先改好目录名， 同名目录会覆盖现有棋子)'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppTheme.boardLine,
                      side: const BorderSide(color: AppTheme.boardLine),
                      padding: const EdgeInsets.symmetric(vertical: 22, horizontal: 22),
                    ),
                  ),
                ),
              ),
            ),
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
                  childCount: total,
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
                    // 内置资源套系
                    if (i <= assetSets.length) {
                      final name = assetSets[i - 1];
                      return _OptionTile(
                        selected: useImage &&
                            _cfg.customPiecePath == null &&
                            _cfg.pieceStyle == name,
                        label: name,
                        onTap: () => _pickPieceSet(name),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            _piecePreviewAsset(name, Side.red),
                            const SizedBox(width: 4),
                            _piecePreviewAsset(name, Side.black),
                          ],
                        ),
                      );
                    }
                    // 数据目录自定义套系
                    final idx = i - assetSets.length - 1;
                    final dirPath = dataSets[idx];
                    final name = p.basename(dirPath);
                    final selected =
                        useImage && _cfg.customPiecePath == dirPath;
                    return _OptionTile(
                      selected: selected,
                      label: name,
                      onTap: () => _pickDataPieceSet(dirPath),
                      child: Stack(
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              _piecePreviewFile(dirPath, Side.red),
                              const SizedBox(width: 4),
                              _piecePreviewFile(dirPath, Side.black),
                            ],
                          ),
                          // 删除按钮：右下角
                          Positioned(
                            right: 0,
                            bottom: 0,
                            child: _DeleteBoardButton(
                              onPressed: () =>
                                  _deleteDataPieceSet(dirPath),
                            ),
                          ),
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

  /// 内置资源棋子预览。红方同时支持 w 和 r 前缀。
  Widget _piecePreviewAsset(String setName, Side side) {
    return Image.asset(
      AssetCatalog.pieceAsset(setName, side, PieceType.general),
      width: 32,
      height: 32,
      errorBuilder: (_, _, _) {
        if (side == Side.red) {
          return Image.asset(
            AssetCatalog.pieceAsset(setName, side, PieceType.general,
                useR: true),
            width: 32,
            height: 32,
            errorBuilder: (_, _, _) => const Icon(
              Icons.broken_image,
              size: 28,
              color: Color(0xFFB0A48A),
            ),
          );
        }
        return const Icon(
          Icons.broken_image,
          size: 28,
          color: Color(0xFFB0A48A),
        );
      },
    );
  }

  /// 数据目录棋子预览。红方同时支持 w 和 r 前缀，优先尝试存在的文件。
  Widget _piecePreviewFile(String dirPath, Side side) {
    var path =
        AssetCatalog.pieceFileAsset(dirPath, side, PieceType.general);
    if (side == Side.red) {
      final rPath = AssetCatalog.pieceFileAsset(dirPath, side,
          PieceType.general, useR: true);
      if (File(rPath).existsSync()) path = rPath;
    }
    return Image.file(
      File(path),
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
