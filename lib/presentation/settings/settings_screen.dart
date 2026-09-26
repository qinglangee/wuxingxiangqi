import 'package:flutter/material.dart';

import '../../core/assets/asset_catalog.dart';
import '../../core/config/app_config.dart';
import '../../core/config/config_manager.dart';
import '../../core/theme/app_theme.dart';
import '../../domain/models/piece.dart';
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

  BoardConfig get _cfg => ConfigManager.instance.config.board;

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
      return c;
    });
    if (mounted) setState(() {});
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

  /// 棋盘选择网格：第一项经典绘制（默认），之后为所有棋盘图片。
  Widget _buildBoardGrid() {
    final useImage = _cfg.boardType == BoardConfig.kTypeImage;
    return FutureBuilder<List<String>>(
      future: _boards,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator(strokeWidth: 2));
        }
        final files = snap.data ?? const <String>[];
        return GridView.builder(
          padding: const EdgeInsets.all(12),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 3,
            mainAxisSpacing: 10,
            crossAxisSpacing: 10,
            childAspectRatio: 0.72,
          ),
          itemCount: files.length + 1,
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
            final name = files[i - 1];
            return _OptionTile(
              selected: useImage && _cfg.boardStyle == name,
              label: _prettyName(name),
              onTap: () => _pickBoard(name),
              child: Image.asset(
                AssetCatalog.boardAsset(name),
                fit: BoxFit.contain,
                errorBuilder: (_, _, _) => const Icon(
                  Icons.broken_image,
                  size: 36,
                  color: Color(0xFFB0A48A),
                ),
              ),
            );
          },
        );
      },
    );
  }

  /// 棋子选择网格：第一项经典绘制（默认），之后为所有棋子套系。
  /// 每个套系用红帅 + 黑将两张图片预览。
  Widget _buildPieceGrid() {
    final useImage = _cfg.pieceType == BoardConfig.kTypeImage;
    return FutureBuilder<List<String>>(
      future: _pieceSets,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator(strokeWidth: 2));
        }
        final sets = snap.data ?? const <String>[];
        return GridView.builder(
          padding: const EdgeInsets.all(12),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 3,
            mainAxisSpacing: 10,
            crossAxisSpacing: 10,
            childAspectRatio: 0.72,
          ),
          itemCount: sets.length + 1,
          itemBuilder: (context, i) {
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
                    size: 18, color: Color(0xFF8B5A2B)),
              ),
          ],
        ),
      ),
    );
  }
}
