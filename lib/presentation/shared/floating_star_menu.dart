import 'dart:math';

import 'package:flutter/material.dart';

import '../../core/config/app_config.dart';
import '../../core/config/config_manager.dart';
import '../../core/theme/app_theme.dart';
import 'adjustable_button_bar.dart';
import 'check_button.dart';

/// 浮动红星菜单：一个可拖动、始终浮于其它组件上方的红色五角星。
///
/// - 本体不参与页面布局（build 返回 [SizedBox.shrink]），通过
///   [OverlayEntry] 显示在所有组件之上；可用于任意页面。
/// - 拖动红星可停留在屏幕任意位置（不会拖出屏幕边界），位置持久化。
/// - 点击红星：在星周围一圈环形展开「常驻按钮」（圆形图标按钮）。
///   若红星离屏幕边缘太近导致内圈放不下，自动向外扩展第二圈、第三圈，
///   直到全部常驻按钮显示完毕。再次点击红星或点击空白处收起。
/// - 长按红星：打开浮动的设置面板，列出组件管理的全部按钮，
///   可拖动调整顺序、逐个切换是否常驻。
///
/// 按钮顺序、常驻列表、check button 状态与红星位置按 [id] 持久化到
/// 应用配置（复用 [ButtonBarConfig]，位置存于 starX/starY）。
class FloatingStarMenu extends StatefulWidget {
  const FloatingStarMenu({
    super.key,
    required this.id,
    required this.buttons,
    this.defaultPinnedIds = const <String>{},
    this.defaultAnchorKey,
    this.defaultAnchorFraction = const Offset(1 / 3, 1.0),
  });

  /// 实例稳定标识，用于持久化按钮顺序/常驻列表/选中状态/星位置。
  final String id;

  /// 全部受管按钮（顺序为初始顺序）；父组件每次 build 提供最新实例。
  final List<FreeButton> buttons;

  /// 默认常驻按钮 id 集合（无配置记录时使用）。
  final Set<String> defaultPinnedIds;

  /// 红星默认位置的锚点区域（如棋盘）。提供后，未保存过位置时红星
  /// 显示在锚点区域内 [defaultAnchorFraction] 指定的相对位置；
  /// 为 null 时默认屏幕右侧垂直居中。
  final GlobalKey? defaultAnchorKey;

  /// 默认位置在锚点区域内的相对坐标（0-1），默认 (1/3, 1.0) 即
  /// 下边缘横向 1/3 处。
  final Offset defaultAnchorFraction;

  @override
  State<FloatingStarMenu> createState() => _FloatingStarMenuState();
}

class _FloatingStarMenuState extends State<FloatingStarMenu> {
  /// 红星尺寸（像素）。
  static const double _starSize = 36;

  /// 环形按钮直径（像素）。
  static const double _btnSize = 44;

  /// 第一圈半径（星中心到按钮中心），向外每圈递增 [_ringStep]。
  static const double _ringRadius = 64;
  static const double _ringStep = 52;

  /// 按钮离屏幕边缘的最小留白。
  static const double _edgeMargin = 6;

  late List<String> _order;
  late Set<String> _pinned;
  late Map<String, bool> _checkedState;

  /// 红星中心在屏幕中的归一化位置（0-1）；null 表示尚未布局。
  Offset? _starPos;

  /// 环形菜单是否展开。
  bool _ringOpen = false;

  /// 设置面板是否打开。
  bool _settingsOpen = false;

  OverlayEntry? _entry;

  @override
  void initState() {
    super.initState();
    _reconcileFromConfig();
    ConfigManager.instance.addListener(_onConfigChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _entry == null) {
        _entry = OverlayEntry(builder: _buildOverlay);
        Overlay.of(context).insert(_entry!);
      }
    });
  }

  @override
  void dispose() {
    ConfigManager.instance.removeListener(_onConfigChanged);
    _entry?.remove();
    _entry = null;
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant FloatingStarMenu oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 父组件每次 build 都提供新按钮列表（enabled/onTap 可能变化）：
    // 保留既有顺序，追加新 id，丢弃已删除的 id
    final incoming = {for (final b in widget.buttons) b.id};
    _order = _order.where(incoming.contains).toList();
    for (final b in widget.buttons) {
      if (!_order.contains(b.id)) _order.add(b.id);
    }
    _pinned = _pinned.where(_order.contains).toSet();
    _refreshOverlay();
  }

  void _onConfigChanged() {
    // 设置页重置配置等外部改动后同步一次（位置/常驻可能被改）
    final cfg = ConfigManager.instance.buttonBarConfig(widget.id);
    if (cfg == null) return;
    _reconcileFromConfig();
    _refreshOverlay();
  }

  /// 从持久化配置恢复顺序/常驻/选中状态/星位置。
  void _reconcileFromConfig() {
    final currentIds = widget.buttons.map((b) => b.id).toList();
    final saved = ConfigManager.instance.buttonBarConfig(widget.id);
    if (saved != null && saved.order.isNotEmpty) {
      _order = saved.order.where(currentIds.contains).toList();
      for (final id in currentIds) {
        if (!_order.contains(id)) _order.add(id);
      }
      _pinned = saved.pinned.where(_order.contains).toSet();
    } else {
      _order = currentIds;
      _pinned = widget.defaultPinnedIds.where(_order.contains).toSet();
    }
    _checkedState = Map<String, bool>.of(saved?.checked ?? const {});
    if (saved?.starX != null && saved?.starY != null) {
      _starPos = Offset(saved!.starX!, saved.starY!);
    }
  }

  /// 把当前状态写入配置并落盘。
  void _persist() {
    ConfigManager.instance.saveButtonBar(
      widget.id,
      ButtonBarConfig(
        order: List<String>.of(_order),
        pinned: _pinned.toList(),
        checked: Map<String, bool>.of(_checkedState),
        starX: _starPos?.dx,
        starY: _starPos?.dy,
      ),
    );
  }

  void _refreshOverlay() {
    final entry = _entry;
    if (entry == null || !mounted) return;
    // 使用 Future.microtask 在当前事件循环结束后立即重建：
    // - 比 addPostFrameCallback 更早触发（在下一帧绘制前），
    //   保证 UI 能及时刷新；
    // - 又足够晚，不会打断正在进行的手势（如 onTap 的 pointer up）。
    // 桌面端若用 postFrameCallback，可能因帧时序导致 pointer up
    // 落在重建后、GestureDetector 被替换，从而 tap 丢失。
    Future.microtask(() {
      if (mounted) entry.markNeedsBuild();
    });
  }

  Map<String, FreeButton> get _btnMap =>
      {for (final b in widget.buttons) b.id: _withPersistedCheck(b)};

  /// check button 包一层持久化：显示值取 [_checkedState]，点击时翻转、
  /// 落盘并以新值回调父组件（语义与 [AdjustableButtonBar] 一致）。
  FreeButton _withPersistedCheck(FreeButton b) {
    if (b.checked == null && b.onCheckedChanged == null) return b;
    final displayed = _checkedState[b.id] ?? b.checked ?? false;
    return FreeButton(
      id: b.id,
      icon: b.icon,
      label: b.label,
      enabled: b.enabled,
      checked: displayed,
      showLabel: b.showLabel,
      iconColor: b.iconColor,
      flipIcon: b.flipIcon,
      closesDrawer: b.closesDrawer,
      onCheckedChanged: b.onCheckedChanged,
      onTap: () {
        final newVal = !displayed;
        _checkedState[b.id] = newVal;
        _persist();
        if (b.onCheckedChanged != null) {
          b.onCheckedChanged!(newVal);
        } else {
          b.onTap?.call();
        }
      },
    );
  }

  /// 未保存过位置时的默认归一化坐标。
  ///
  /// 有锚点 key 时取锚点区域内的 [defaultAnchorFraction] 相对位置；
  /// 无锚点或锚点尚未布局时回退到屏幕右侧垂直居中。
  Offset _defaultPos(Size screenSize) {
    final key = widget.defaultAnchorKey;
    if (key == null) return const Offset(0.92, 0.5);
    // 树重组期间 element 可能处于 inactive 状态：此时 currentContext
    // 非空、mounted 也为 true，但 findRenderObject 仍会抛
    // "Cannot get renderObject of inactive element"，只能 try-catch 兜底
    final box = _safeRenderBox(key);
    if (box == null || !box.attached) return const Offset(0.92, 0.5);
    final origin = box.localToGlobal(Offset.zero);
    final x = origin.dx +
        box.size.width * widget.defaultAnchorFraction.dx;
    final y = origin.dy +
        box.size.height * widget.defaultAnchorFraction.dy;
    return Offset(x / screenSize.width, y / screenSize.height);
  }

  /// 安全取 GlobalKey 的 RenderBox：element inactive / 未挂载时返回 null。
  static RenderBox? _safeRenderBox(GlobalKey key) {
    try {
      final ctx = key.currentContext;
      if (ctx == null || !ctx.mounted) return null;
      return ctx.findRenderObject() as RenderBox?;
    } catch (_) {
      return null;
    }
  }

  List<FreeButton> get _pinnedButtons => _order
      .where((id) => _pinned.contains(id))
      .map((id) => _btnMap[id])
      .whereType<FreeButton>()
      .toList();

  // ---- 浮层构建 -----------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    // 本体不参与布局，全部内容通过 OverlayEntry 浮在其它组件上方
    return const SizedBox.shrink();
  }

  Widget _buildOverlay(BuildContext overlayContext) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = Size(constraints.maxWidth, constraints.maxHeight);
        final pos = _starPos ?? _defaultPos(size);
        var center =
            Offset(pos.dx * size.width, pos.dy * size.height);
        center = _clampCenter(center, size);

        final children = <Widget>[];
        // 菜单/设置打开时：全屏透明遮罩，点击空白处收起
        if (_ringOpen || _settingsOpen) {
          children.add(Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () {
                _ringOpen = false;
                _settingsOpen = false;
                _refreshOverlay();
              },
              child: const SizedBox.expand(),
            ),
          ));
        }

        // 环形常驻按钮（在星下方层，星最后绘制在最上）
        if (_ringOpen) {
          for (final item in _layoutRing(center, size)) {
            children.add(item);
          }
        }

        // 设置浮层
        if (_settingsOpen) {
          children.add(_buildSettings(size));
        }

        // 红星本体
        children.add(Positioned(
          left: center.dx - _starSize / 2,
          top: center.dy - _starSize / 2,
          width: _starSize,
          height: _starSize,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            // 手势竞技场保证：拖动超阈值后 pan 胜出、tap 不再触发，
            // 因此无需用标志位手动区分点击与拖动。
            //
            // 注意：onPanUpdate 必须基于状态里的 _starPos 累加 delta，
            // 不能基于本闭包捕获的 center（上次构建时的旧值），
            // 否则同帧内多次 delta 相互覆盖，星几乎不动。
            onPanUpdate: (d) {
              // 直接读状态里的最新位置；未保存过位置时用锚点默认位置，
              // 不能回退到固定坐标，否则首次拖动会瞬移
              final curPos = _starPos ?? _defaultPos(size);
              final cur = Offset(
                curPos.dx * size.width,
                curPos.dy * size.height,
              );
              final next = _clampCenter(cur + d.delta, size);
              _starPos = Offset(next.dx / size.width, next.dy / size.height);
              _refreshOverlay();
            },
            onPanEnd: (_) => _persist(),
            onTap: () {
              _ringOpen = !_ringOpen;
              if (_ringOpen) _settingsOpen = false;
              _refreshOverlay();
            },
            onLongPress: () {
              _settingsOpen = true;
              _ringOpen = false;
              _refreshOverlay();
            },
            child: const Stack(
              alignment: Alignment.center,
              children: [
                // 深色描边底层，保证红星在任何背景上可见
                Icon(Icons.star, size: _starSize + 4, color: Color(0xFF5A1010)),
                Icon(Icons.star, size: _starSize, color: Color(0xFFD32F2F)),
              ],
            ),
          ),
        ));

        // Overlay 浮层内没有 Material 祖先，环形按钮的 InkWell/Tooltip
        // 等 Material 系控件需要它，这里提供透明 Material 兜底
        return Material(
          type: MaterialType.transparency,
          child: Stack(children: children),
        );
      },
    );
  }

  /// 把星中心坐标限制在屏幕内（星整体不超出边界）。
  Offset _clampCenter(Offset c, Size size) {
    const half = _starSize / 2;
    return Offset(
      c.dx.clamp(half + _edgeMargin, size.width - half - _edgeMargin),
      c.dy.clamp(half + _edgeMargin, size.height - half - _edgeMargin),
    );
  }

  /// 计算环形按钮布局：从第一圈开始放，放不下（超出屏幕）的按钮
  /// 顺延到下一圈，直到全部常驻按钮都有位置。
  List<Widget> _layoutRing(Offset center, Size size) {
    final buttons = _pinnedButtons;
    if (buttons.isEmpty) return [];
    final placed = <Widget>[];
    var index = 0;
    var ring = 0;
    while (index < buttons.length && ring < 6) {
      final radius = _ringRadius + ring * _ringStep;
      // 本圈按弧长能容纳的最大按钮数（按钮间至少留 10px 弧距）
      final capacity =
          max(4, (2 * pi * radius / (_btnSize + 10)).floor());
      // 本圈候选位置中「完整落在屏幕内」的槽位数
      final slots = <Offset>[];
      for (var s = 0; s < capacity; s++) {
        final angle = -pi / 2 + 2 * pi * s / capacity; // 从正上方开始顺时针
        final p = center +
            Offset(cos(angle) * radius, sin(angle) * radius);
        if (_fitsOnScreen(p, size)) slots.add(p);
      }
      for (final p in slots) {
        if (index >= buttons.length) break;
        placed.add(_ringButton(p, buttons[index]));
        index++;
      }
      ring++;
    }
    return placed;
  }

  /// 按钮（直径 [_btnSize] 的圆）以 p 为中心时是否完整落在屏幕内。
  bool _fitsOnScreen(Offset p, Size size) {
    const half = _btnSize / 2;
    return p.dx - half >= _edgeMargin &&
        p.dx + half <= size.width - _edgeMargin &&
        p.dy - half >= _edgeMargin &&
        p.dy + half <= size.height - _edgeMargin;
  }

  /// 环形菜单中的一个圆形常驻按钮。
  Widget _ringButton(Offset center, FreeButton b) {
    final isChecked = b.checked ?? false;
    final iconColor = !b.enabled
        ? const Color(0xFFD0C4A8)
        : (b.iconColor ?? AppTheme.boardLine);
    return Positioned(
      left: center.dx - _btnSize / 2,
      top: center.dy - _btnSize / 2,
      width: _btnSize,
      height: _btnSize,
      child: Tooltip(
        message: b.label,
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: b.enabled
              ? () {
                  // 点击后收起环形菜单，再执行按钮动作
                  _ringOpen = false;
                  _refreshOverlay();
                  b.onTap?.call();
                }
              : null,
          child: Container(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: isChecked
                  ? AppTheme.boardLine.withValues(alpha: 0.2)
                  : const Color(0xFFF5E6C8),
              border: Border.all(
                color: isChecked
                    ? AppTheme.boardLine
                    : const Color(0xFFC9B68C),
                width: isChecked ? 1.4 : 0.9,
              ),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x33000000),
                  blurRadius: 4,
                  offset: Offset(0, 2),
                ),
              ],
            ),
            child: Center(
              child: b.flipIcon
                  ? mirrored(Icon(b.icon, size: 22, color: iconColor))
                  : Icon(b.icon, size: 22, color: iconColor),
            ),
          ),
        ),
      ),
    );
  }

  // ---- 设置浮层 -----------------------------------------------------------

  /// 浮动设置面板：全部按钮可拖动排序 + 逐个切换常驻。
  Widget _buildSettings(Size size) {
    final all =
        _order.map((id) => _btnMap[id]).whereType<FreeButton>().toList();
    final width = min(320.0, size.width - 32);
    final height = min(400.0, size.height - 64);
    return Positioned(
      left: (size.width - width) / 2,
      top: (size.height - height) / 2,
      width: width,
      height: height,
      child: Material(
        color: const Color(0xFFFDF6E3),
        elevation: 12,
        borderRadius: BorderRadius.circular(12),
        clipBehavior: Clip.antiAlias,
        child: Column(
          children: [
            Container(
              color: const Color(0xFF8B5A2B),
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Row(
                children: [
                  const Icon(Icons.star, color: Color(0xFFFFD54F), size: 18),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text(
                      '红星按钮设置',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                      ),
                    ),
                  ),
                  InkWell(
                    onTap: () {
                      _settingsOpen = false;
                      _refreshOverlay();
                    },
                    child: const Padding(
                      padding: EdgeInsets.all(4),
                      child:
                          Icon(Icons.close, color: Colors.white, size: 18),
                    ),
                  ),
                ],
              ),
            ),
            const Padding(
              padding: EdgeInsets.fromLTRB(12, 8, 12, 0),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  '按住右端拖柄调整顺序 · 点星设为常驻',
                  style: TextStyle(fontSize: 12, color: Color(0xFF8B6B3D)),
                ),
              ),
            ),
            Expanded(
              child: ReorderableListView.builder(
                buildDefaultDragHandles: false,
                itemCount: all.length,
                // onReorderItem 已对移除元素做过 newIndex 修正，直接使用
                onReorderItem: (oldIndex, newIndex) {
                  final id = _order.removeAt(oldIndex);
                  _order.insert(newIndex, id);
                  _persist();
                  _refreshOverlay();
                },
                proxyDecorator: (child, index, anim) => Material(
                  color: Colors.transparent,
                  elevation: 4,
                  child: child,
                ),
                itemBuilder: (ctx, i) {
                  final b = all[i];
                  final isPinned = _pinned.contains(b.id);
                  return ListTile(
                    key: ValueKey(b.id),
                    dense: true,
                    contentPadding:
                        const EdgeInsets.fromLTRB(8, 0, 4, 0),
                    leading: b.flipIcon
                        ? mirrored(Icon(b.icon,
                            color: AppTheme.boardLine, size: 22))
                        : Icon(b.icon, color: AppTheme.boardLine, size: 22),
                    title: Text(
                      b.label,
                      style: const TextStyle(
                          fontSize: 14, color: Color(0xFF5A3A1A)),
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          onPressed: () {
                            if (isPinned) {
                              _pinned.remove(b.id);
                            } else {
                              _pinned.add(b.id);
                            }
                            _persist();
                            _refreshOverlay();
                          },
                          icon: Icon(
                            isPinned ? Icons.star : Icons.star_border,
                            size: 22,
                            color: isPinned
                                ? const Color(0xFFD4A017)
                                : const Color(0xFFB0A48A),
                          ),
                          tooltip: isPinned ? '取消常驻' : '设为常驻',
                          visualDensity: VisualDensity.compact,
                        ),
                        ReorderableDragStartListener(
                          index: i,
                          child: const Padding(
                            padding: EdgeInsets.symmetric(
                                horizontal: 6, vertical: 8),
                            child: Icon(
                              Icons.drag_indicator,
                              size: 20,
                              color: Color(0xFFB0A48A),
                            ),
                          ),
                        ),
                      ],
                    ),
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
