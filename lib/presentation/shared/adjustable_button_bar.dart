import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import 'check_button.dart';

/// 一个可添加到 [AdjustableButtonBar] 的「自由按钮」定义。
///
/// 不可变；由父组件每次 build 时提供（携带最新的 [enabled] 与 [onTap]）。
/// 控件内部按 [id] 维护顺序与是否常驻，因此 [id] 必须稳定。
class FreeButton {
  const FreeButton({
    required this.id,
    required this.icon,
    required this.label,
    required this.onTap,
    this.enabled = true,
    this.checked,
    this.showLabel = true,
    this.iconColor,
  });

  /// 稳定标识，用于在重建间保持顺序与常驻状态。
  final String id;
  final IconData icon;
  final String label;
  final bool enabled;
  final VoidCallback onTap;

  /// 选中态：null 为普通按钮；非 null 时作为 check button 渲染，
  /// 选中时带高亮底框（如「红方电脑」开关）。
  final bool? checked;

  /// 是否显示文字；false 时仅显示图标。
  final bool showLabel;

  /// 图标颜色；null 时使用主题默认色（如红黑方用各自的颜色）。
  final Color? iconColor;
}

/// 通用的「可调整窗口控件」。
///
/// 由两部分组成：
/// - **常驻容器**（一行）：左侧 Row 展示被设为常驻的自由按钮，
///   右侧一个操作按钮，点击展开/收起抽屉。
/// - **抽屉容器**（展开时显示）：默认显示未设为常驻的自由按钮
///   （多行 Wrap）；点击抽屉自带的编辑按钮后，显示全部自由按钮，
///   可拖动调整顺序，并可逐个切换是否常驻。常驻容器也按此顺序
///   显示常驻按钮。
///
/// 抽屉通过 OverlayPortal 浮在界面之上，不占据布局空间；展开方向
/// 随常驻栏位置自动调整：常驻栏位于屏幕上半部（如页面顶部的配置
/// 条）时向下展开，位于下半部（如底部导航条）时向上展开。
///
/// 组件自带一个默认不常驻的「显示文字」按钮（追加在按钮列表末尾）：
/// 点击可切换其它按钮的文字显示/隐藏，自身文字始终显示以便找回；
/// 需要该功能时可将其设为常驻。
class AdjustableButtonBar extends StatefulWidget {
  const AdjustableButtonBar({
    super.key,
    required this.buttons,
    this.defaultPinnedIds = const <String>{},
  });

  /// 全部自由按钮（顺序为初始顺序）。
  final List<FreeButton> buttons;

  /// 默认设为常驻的按钮 id 集合。
  final Set<String> defaultPinnedIds;

  @override
  State<AdjustableButtonBar> createState() => _AdjustableButtonBarState();
}

class _AdjustableButtonBarState extends State<AdjustableButtonBar> {
  late List<String> _order;
  late Set<String> _pinned;
  bool _drawerOpen = false;
  bool _editMode = false;

  /// 其它按钮是否显示文字；由内置的「显示文字」按钮切换。
  bool _showLabels = true;

  /// 内置「显示文字」切换按钮的稳定 id（默认不常驻，可像普通按钮一样
  /// 排序与设为常驻）。
  static const String _toggleLabelsId = '__toggle_labels__';

  /// 内置「显示文字」切换按钮：始终显示自身文字，方便在文字隐藏后找回。
  FreeButton get _toggleLabelsButton => FreeButton(
        id: _toggleLabelsId,
        icon: Icons.text_fields,
        label: _showLabels ? '显示文字' : '隐藏文字',
        checked: _showLabels,
        onTap: () => setState(() => _showLabels = !_showLabels),
      );

  /// 全部按钮：外部传入按钮 + 末尾内置的「显示文字」按钮。
  List<FreeButton> get _allButtons => [...widget.buttons, _toggleLabelsButton];

  /// 抽屉的 OverlayPortal 控制器。用 overlayChildLayoutBuilder 命名构造，
  /// 在布局阶段即可拿到常驻栏可靠的 paint transform 进行定位
  ///（不经过 FollowerLayer，可避开 ReorderableListView 的 transform 报错）。
  final OverlayPortalController _portalController = OverlayPortalController();

  // 注意：dispose 中不要调用 _portalController.hide()。
  // OverlayPortal 随 widget 销毁时会自动移除浮层；销毁后控制器已与
  // portal state 断开，此时再 hide() 会触发 SDK 的 _zOrderIndex 断言。

  @override
  void initState() {
    super.initState();
    _order = _allButtons.map((b) => b.id).toList();
    // 常驻数量不设上限：用户愿意放多少就放多少
    _pinned = widget.defaultPinnedIds.where(_order.contains).toSet();
  }

  @override
  void didUpdateWidget(covariant AdjustableButtonBar old) {
    super.didUpdateWidget(old);
    // 父组件每次 build 都会提供新的按钮列表（enabled/onTap 可能变化），
    // 这里按 id 对齐：保留既有顺序，追加新 id，丢弃已删除的 id。
    final incoming = {for (final b in _allButtons) b.id};
    _order = _order.where(incoming.contains).toList();
    for (final b in _allButtons) {
      if (!_order.contains(b.id)) _order.add(b.id);
    }
    _pinned = _pinned.where(_order.contains).toSet();
  }

  Map<String, FreeButton> get _btnMap => {
        for (final b in _allButtons) b.id: b,
      };

  /// 按钮实际是否显示文字：内置切换按钮始终显示，其余受 [_showLabels] 控制。
  bool _effectiveShowLabel(FreeButton b) =>
      b.id == _toggleLabelsId || (b.showLabel && _showLabels);

  List<FreeButton> get _pinnedButtons => _order
      .where((id) => _pinned.contains(id))
      .map((id) => _btnMap[id])
      .whereType<FreeButton>()
      .toList();

  List<FreeButton> get _unpinnedButtons => _order
      .where((id) => !_pinned.contains(id))
      .map((id) => _btnMap[id])
      .whereType<FreeButton>()
      .toList();

  void _toggleDrawer() {
    if (_drawerOpen) {
      _closeDrawer();
    } else {
      setState(() => _drawerOpen = true);
      // 待常驻栏完成本帧布局后再插入浮层（此时能拿到准确位置尺寸）
      WidgetsBinding.instance.addPostFrameCallback((_) => _showOverlay());
    }
  }

  void _closeDrawer() {
    _removeOverlay();
    setState(() {
      _drawerOpen = false;
      // 收起抽屉时退出编辑态
      _editMode = false;
    });
  }

  void _showOverlay() {
    if (!mounted || _portalController.isShowing) return;
    _portalController.show();
  }

  void _removeOverlay() {
    _portalController.hide();
  }

  void _toggleEdit() {
    // OverlayPortal 会随本 State 重建而重建浮层内容与尺寸
    setState(() => _editMode = !_editMode);
  }

  void _togglePin(String id) {
    setState(() {
      if (_pinned.contains(id)) {
        _pinned.remove(id);
      } else {
        _pinned.add(id);
      }
    });
  }

  void _reorder(int oldIndex, int newIndex) {
    // onReorderItem 已对移除元素做过 newIndex 修正，直接使用
    setState(() {
      final id = _order.removeAt(oldIndex);
      _order.insert(newIndex, id);
    });
  }

  @override
  Widget build(BuildContext context) {
    // 常驻栏留在正常布局流中；抽屉面板与遮罩通过 OverlayPortal 浮在
    // 其正上方，不占据布局空间，出现/编辑都不会影响原有布局。
    return OverlayPortal.overlayChildLayoutBuilder(
      controller: _portalController,
      overlayChildBuilder: (context, info) => _buildOverlay(context, info),
      child: Container(
        decoration: const BoxDecoration(
          color: Color(0xFFF5E6C8),
          border: Border(
            top: BorderSide(color: Color(0xFFC9B68C), width: 0.8),
          ),
        ),
        child: _buildPersistentBar(),
      ),
    );
  }

  // ---- 常驻容器 -----------------------------------------------------------

  Widget _buildPersistentBar() {
    final pinned = _pinnedButtons;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      child: Row(
        children: [
          Expanded(
            child: pinned.isEmpty
                ? const Align(
                    alignment: Alignment.centerLeft,
                    child: Padding(
                      padding: EdgeInsets.symmetric(horizontal: 6),
                      child: Text(
                        '点击右侧按钮展开更多操作',
                        style: TextStyle(
                          fontSize: 12,
                          color: Color(0xFFB0A48A),
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                    ),
                  )
                : Row(
                    children: [
                      for (final b in pinned)
                        Expanded(
                          child: IconCheckButton(
                            icon: b.icon,
                            label: b.label,
                            checked: b.checked,
                            enabled: b.enabled,
                            showLabel: _effectiveShowLabel(b),
                            iconColor: b.iconColor,
                            onTap: b.onTap,
                          ),
                        ),
                    ],
                  ),
          ),
          const SizedBox(width: 4),
          _OperationButton(
            open: _drawerOpen,
            onTap: _toggleDrawer,
          ),
        ],
      ),
    );
  }

  // ---- 抽屉浮层 -----------------------------------------------------------

  /// 浮层内容：透明遮罩 + 贴住常驻栏的面板。
  ///
  /// 在布局阶段通过 [info] 直接拿到常驻栏尺寸与其在 Overlay 坐标系中的
  /// paint transform（不经过 FollowerLayer），用 [Positioned] 定位：
  /// 宽度与常驻栏一致；常驻栏在屏幕上半部时面板从其底部向下展开，
  /// 在下半部时面板从其顶部向上展开。
  Widget _buildOverlay(BuildContext context, OverlayChildLayoutInfo info) {
    // 常驻栏左上角在 Overlay 坐标系中的位置
    final origin =
        MatrixUtils.transformPoint(info.childPaintTransform, Offset.zero);
    final barWidth = info.childSize.width;
    final barHeight = info.childSize.height;

    // 按常驻栏纵向中心与 Overlay 中线比较，自动选择抽屉展开方向
    final downward =
        origin.dy + barHeight / 2 < info.overlaySize.height / 2;

    // 编辑态：不超过应用高度的一半；普通态：最高 220
    final maxHeight = _editMode ? info.overlaySize.height / 2 : 220.0;
    // 展开方向上的可用高度（边界留 8px）
    final available = (downward
            ? info.overlaySize.height - origin.dy - barHeight - 8
            : origin.dy - 8)
        .clamp(120.0, 100000.0)
        .toDouble();
    final panelHeight = available < maxHeight ? available : maxHeight;
    // 面板始终与常驻栏贴合：向下展开顶边贴栏底，向上展开底边贴栏顶
    final panelTop =
        downward ? origin.dy + barHeight : origin.dy - panelHeight;

    return Stack(
      children: [
        // 透明遮罩：点击抽屉外任意位置即关闭（非模式，不锁页面）
        Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: _closeDrawer,
            child: const SizedBox.expand(),
          ),
        ),
        Positioned(
          left: origin.dx,
          top: panelTop,
          width: barWidth,
          height: panelHeight,
          child: Material(
            color: const Color(0xFFF5E6C8),
            elevation: 10,
            borderRadius: downward
                ? const BorderRadius.vertical(bottom: Radius.circular(8))
                : const BorderRadius.vertical(top: Radius.circular(8)),
            clipBehavior: Clip.antiAlias,
            child: _editMode ? _buildEditDrawer() : _buildNormalDrawer(),
          ),
        ),
      ],
    );
  }

  /// 普通抽屉：未常驻按钮的多行 Wrap + 顶部编辑按钮。
  ///
  /// 宽高由浮层 [Positioned] 给定（紧约束），这里只负责布局。
  Widget _buildNormalDrawer() {
    final unpinned = _unpinnedButtons;
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 6, 6, 8),
      child: Column(
        children: [
          Row(
            children: [
              const Text(
                '更多操作',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF8B6B3D),
                ),
              ),
              const Spacer(),
              IconButton(
                onPressed: _toggleEdit,
                icon: const Icon(Icons.edit, size: 18),
                color: AppTheme.boardLine,
                tooltip: '编辑按钮',
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(
                  minWidth: 32,
                  minHeight: 32,
                ),
              ),
            ],
          ),
          const SizedBox(height: 2),
          Expanded(
            child: unpinned.isEmpty
                ? const Center(
                    child: Text(
                      '所有按钮都已设为常驻',
                      style: TextStyle(
                        fontSize: 12,
                        color: Color(0xFFB0A48A),
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  )
                : SingleChildScrollView(
                    child: Align(
                      alignment: Alignment.topLeft,
                      child: Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          for (final b in unpinned)
                            _DrawerChip(
                              button: b,
                              showLabel: _effectiveShowLabel(b),
                            ),
                        ],
                      ),
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  /// 编辑抽屉：全部按钮可拖动排序 + 逐个切换常驻。
  ///
  /// 宽高由浮层 [Positioned] 给定（编辑态为常驻栏以上全部可用空间）。
  Widget _buildEditDrawer() {
    final all = _order
        .map((id) => _btnMap[id])
        .whereType<FreeButton>()
        .toList();
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 6, 6, 8),
      child: Column(
        children: [
          Row(
            children: [
              const Text(
                '按住右端拖柄调整顺序 · 点星设为常驻',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF8B6B3D),
                ),
              ),
              const Spacer(),
              TextButton.icon(
                onPressed: _toggleEdit,
                icon: const Icon(Icons.check, size: 18),
                label: const Text('完成', style: TextStyle(fontSize: 13)),
                style: TextButton.styleFrom(
                  foregroundColor: AppTheme.boardLine,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                ),
              ),
            ],
          ),
          const SizedBox(height: 2),
          Expanded(
            child: ReorderableListView.builder(
              // 关闭默认拖柄（桌面显示图标/移动端长按的不一致行为），
              // 统一由 _EditRow 右侧的 ReorderableDragStartListener 拖柄负责，
              // 各平台均为按下拖柄即拖、图标可见。
              buildDefaultDragHandles: false,
              itemCount: all.length,
              onReorderItem: _reorder,
              proxyDecorator: (child, index, anim) => Material(
                color: Colors.transparent,
                elevation: 4,
                child: child,
              ),
              itemBuilder: (ctx, i) {
                final b = all[i];
                final isPinned = _pinned.contains(b.id);
                return _EditRow(
                  key: ValueKey(b.id),
                  index: i,
                  button: b,
                  pinned: isPinned,
                  onTogglePin: () => _togglePin(b.id),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

// ---- 子控件 ----------------------------------------------------------------

/// 普通抽屉中的按钮 chip（图标 + 文字，横向）。
class _DrawerChip extends StatelessWidget {
  const _DrawerChip({required this.button, required this.showLabel});
  final FreeButton button;

  /// 是否显示文字（由 AdjustableButtonBar 统一计算后传入）。
  final bool showLabel;

  @override
  Widget build(BuildContext context) {
    final isChecked = button.checked ?? false;
    final color =
        button.enabled ? AppTheme.boardLine : const Color(0xFFD0C4A8);
    return InkWell(
      onTap: button.enabled ? button.onTap : null,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: isChecked
              ? AppTheme.boardLine.withValues(alpha: 0.15)
              : Colors.white.withValues(alpha: 0.6),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isChecked
                ? AppTheme.boardLine.withValues(alpha: 0.55)
                : const Color(0xFFD8C69A),
            width: isChecked ? 0.9 : 0.6,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(button.icon, size: 18, color: color),
            if (showLabel) ...[
              const SizedBox(width: 6),
              Text(
                button.label,
                style: TextStyle(
                  fontSize: 13,
                  color: button.enabled
                      ? const Color(0xFF8B6B3D)
                      : const Color(0xFFD0C4A8),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// 编辑抽屉中的一行：图标 + 标签 + 常驻星标 + 右侧拖柄，按住拖柄拖动排序。
class _EditRow extends StatelessWidget {
  const _EditRow({
    required super.key,
    required this.index,
    required this.button,
    required this.pinned,
    required this.onTogglePin,
  });

  /// 该项在 ReorderableListView 中的下标，供拖柄监听使用。
  final int index;
  final FreeButton button;
  final bool pinned;
  final VoidCallback onTogglePin;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      key: key,
      leading: Icon(button.icon, color: AppTheme.boardLine, size: 22),
      title: Text(
        button.label,
        style: const TextStyle(fontSize: 14, color: Color(0xFF5A3A1A)),
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            onPressed: onTogglePin,
            icon: Icon(
              pinned ? Icons.star : Icons.star_border,
              size: 22,
              color:
                  pinned ? const Color(0xFFD4A017) : const Color(0xFFB0A48A),
            ),
            tooltip: pinned ? '取消常驻' : '设为常驻',
            visualDensity: VisualDensity.compact,
          ),
          // 显式拖柄：桌面与移动端一致可见，按住即拖（移动端无需长按）
          ReorderableDragStartListener(
            index: index,
            child: const Padding(
              padding: EdgeInsets.symmetric(horizontal: 6, vertical: 8),
              child: Icon(
                Icons.drag_indicator,
                size: 20,
                color: Color(0xFFB0A48A),
              ),
            ),
          ),
        ],
      ),
      contentPadding: const EdgeInsets.fromLTRB(8, 0, 4, 0),
      dense: true,
    );
  }
}

/// 常驻容器右侧的操作按钮，点击展开/收起抽屉。
class _OperationButton extends StatelessWidget {
  const _OperationButton({required this.open, required this.onTap});

  final bool open;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: open ? '收起抽屉' : '展开抽屉',
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: AppTheme.boardLine.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: AppTheme.boardLine.withValues(alpha: 0.4),
              width: 0.8,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                open ? Icons.expand_less : Icons.expand_more,
                size: 22,
                color: AppTheme.boardLine,
              ),
              const SizedBox(width: 4),
              Icon(
                Icons.apps,
                size: 18,
                color: AppTheme.boardLine.withValues(alpha: 0.8),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
