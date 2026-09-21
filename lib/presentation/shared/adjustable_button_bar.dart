import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';

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
  });

  /// 稳定标识，用于在重建间保持顺序与常驻状态。
  final String id;
  final IconData icon;
  final String label;
  final bool enabled;
  final VoidCallback onTap;
}

/// 通用的「可调整窗口控件」。
///
/// 由两部分组成：
/// - **常驻容器**（底部一行）：左侧 Row 展示被设为常驻的自由按钮，
///   右侧一个操作按钮，点击展开/收起抽屉。
/// - **抽屉容器**（常驻容器上方，展开时显示）：默认显示未设为常驻的
///   自由按钮（多行 Wrap）；点击抽屉自带的编辑按钮后，显示全部自由
///   按钮，可拖动调整顺序，并可逐个切换是否常驻。常驻容器也按此
///   顺序显示常驻按钮。
///
/// 抽屉展开时控件整体变高，把上方内容（通常是 Expanded 区域）顶高，
/// 因此无需 Overlay 即可浮在内容之上。
class AdjustableButtonBar extends StatefulWidget {
  const AdjustableButtonBar({
    super.key,
    required this.buttons,
    this.defaultPinnedIds = const <String>{},
    this.maxPinnedCount = 4,
  });

  /// 全部自由按钮（顺序为初始顺序）。
  final List<FreeButton> buttons;

  /// 默认设为常驻的按钮 id 集合。
  final Set<String> defaultPinnedIds;

  /// 常驻按钮数量上限（防止常驻行溢出）。
  final int maxPinnedCount;

  @override
  State<AdjustableButtonBar> createState() => _AdjustableButtonBarState();
}

class _AdjustableButtonBarState extends State<AdjustableButtonBar> {
  late List<String> _order;
  late Set<String> _pinned;
  bool _drawerOpen = false;
  bool _editMode = false;

  @override
  void initState() {
    super.initState();
    _order = widget.buttons.map((b) => b.id).toList();
    _pinned = widget.defaultPinnedIds.where(_order.contains).toSet();
    // 超裁到上限
    while (_pinned.length > widget.maxPinnedCount) {
      _pinned.remove(_pinned.last);
    }
  }

  @override
  void didUpdateWidget(covariant AdjustableButtonBar old) {
    super.didUpdateWidget(old);
    // 父组件每次 build 都会提供新的按钮列表（enabled/onTap 可能变化），
    // 这里按 id 对齐：保留既有顺序，追加新 id，丢弃已删除的 id。
    final incoming = {for (final b in widget.buttons) b.id};
    _order = _order.where(incoming.contains).toList();
    for (final b in widget.buttons) {
      if (!_order.contains(b.id)) _order.add(b.id);
    }
    _pinned = _pinned.where(_order.contains).toSet();
  }

  Map<String, FreeButton> get _btnMap => {
        for (final b in widget.buttons) b.id: b,
      };

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

  void _toggleDrawer() => setState(() {
        _drawerOpen = !_drawerOpen;
        // 收起抽屉时退出编辑态
        if (!_drawerOpen) _editMode = false;
      });

  void _toggleEdit() => setState(() => _editMode = !_editMode);

  void _togglePin(String id) => setState(() {
        if (_pinned.contains(id)) {
          _pinned.remove(id);
        } else if (_pinned.length < widget.maxPinnedCount) {
          _pinned.add(id);
        }
      });

  void _reorder(int oldIndex, int newIndex) {
    setState(() {
      if (newIndex > oldIndex) newIndex -= 1;
      final id = _order.removeAt(oldIndex);
      _order.insert(newIndex, id);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFFF5E6C8),
        border: Border(
          top: BorderSide(color: Color(0xFFC9B68C), width: 0.8),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AnimatedSize(
            alignment: Alignment.bottomCenter,
            duration: const Duration(milliseconds: 180),
            child: _drawerOpen ? _buildDrawer() : const SizedBox.shrink(),
          ),
          _buildPersistentBar(),
        ],
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
                        Expanded(child: _BarButton(button: b)),
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

  // ---- 抽屉容器 -----------------------------------------------------------

  Widget _buildDrawer() {
    if (_editMode) return _buildEditDrawer();
    return _buildNormalDrawer();
  }

  /// 普通抽屉：未常驻按钮的多行 Wrap + 顶部编辑按钮。
  Widget _buildNormalDrawer() {
    final unpinned = _unpinnedButtons;
    return Container(
      constraints: const BoxConstraints(maxHeight: 220),
      padding: const EdgeInsets.fromLTRB(10, 6, 6, 8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
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
          Flexible(
            child: unpinned.isEmpty
                ? const Center(
                    child: Padding(
                      padding: EdgeInsets.symmetric(vertical: 12),
                      child: Text(
                        '所有按钮都已设为常驻',
                        style: TextStyle(
                          fontSize: 12,
                          color: Color(0xFFB0A48A),
                          fontStyle: FontStyle.italic,
                        ),
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
                          for (final b in unpinned) _DrawerChip(button: b),
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
  Widget _buildEditDrawer() {
    final all = _order
        .map((id) => _btnMap[id])
        .whereType<FreeButton>()
        .toList();
    return Container(
      constraints: const BoxConstraints(maxHeight: 210),
      padding: const EdgeInsets.fromLTRB(10, 6, 6, 8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              const Text(
                '拖动右端调整顺序 · 点星设为常驻',
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
          Flexible(
            child: ReorderableListView.builder(
              buildDefaultDragHandles: true,
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
                  button: b,
                  pinned: isPinned,
                  canPin: isPinned || _pinned.length < widget.maxPinnedCount,
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

/// 常驻行中的按钮（图标在上、文字在下，填满分配宽度）。
class _BarButton extends StatelessWidget {
  const _BarButton({required this.button});
  final FreeButton button;

  @override
  Widget build(BuildContext context) {
    final color =
        button.enabled ? AppTheme.boardLine : const Color(0xFFD0C4A8);
    return InkWell(
      onTap: button.enabled ? button.onTap : null,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(button.icon, size: 26, color: color),
            const SizedBox(height: 2),
            Text(
              button.label,
              style: TextStyle(
                fontSize: 11,
                color: button.enabled
                    ? const Color(0xFF8B6B3D)
                    : const Color(0xFFD0C4A8),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 普通抽屉中的按钮 chip（图标 + 文字，横向）。
class _DrawerChip extends StatelessWidget {
  const _DrawerChip({required this.button});
  final FreeButton button;

  @override
  Widget build(BuildContext context) {
    final color =
        button.enabled ? AppTheme.boardLine : const Color(0xFFD0C4A8);
    return InkWell(
      onTap: button.enabled ? button.onTap : null,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.6),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: const Color(0xFFD8C69A), width: 0.6),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(button.icon, size: 18, color: color),
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
        ),
      ),
    );
  }
}

/// 编辑抽屉中的一行：图标 + 标签 + 常驻星标，长按拖动。
class _EditRow extends StatelessWidget {
  const _EditRow({
    required super.key,
    required this.button,
    required this.pinned,
    required this.canPin,
    required this.onTogglePin,
  });

  final FreeButton button;
  final bool pinned;
  final bool canPin;
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
      trailing: IconButton(
        onPressed: canPin ? onTogglePin : null,
        icon: Icon(
          pinned ? Icons.star : Icons.star_border,
          size: 22,
          color: pinned ? const Color(0xFFD4A017) : const Color(0xFFB0A48A),
        ),
        tooltip: pinned ? '取消常驻' : '设为常驻',
        visualDensity: VisualDensity.compact,
      ),
      contentPadding: const EdgeInsets.fromLTRB(8, 0, 44, 0),
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
