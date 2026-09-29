import 'package:flutter/material.dart';

import '../../core/config/app_config.dart';
import '../../core/config/config_manager.dart';

/// 浮动切换星：一个可拖动、始终浮于其它组件上方的五角星多态开关。
///
/// - 本体不参与页面布局（build 返回 [SizedBox.shrink]），通过
///   [OverlayEntry] 显示在所有组件之上；可用于任意页面。
/// - 拖动可停留在屏幕任意位置（不会拖出屏幕边界），位置按 [id] 持久化。
/// - 点击在 0..N-1 共 N 个状态间循环切换并回调 [onChanged]；
///   星星颜色随状态取 [colors] 中对应项。
/// - 未保存过位置时，默认显示在 [defaultAnchorKey] 锚点区域的
///   [defaultAnchorFraction] + [defaultAnchorOffset] 处（如棋盘下方偏左）。
class FloatingToggleStar extends StatefulWidget {
  const FloatingToggleStar({
    super.key,
    required this.id,
    required this.state,
    required this.onChanged,
    this.colors = const [
      Color(0xFF1B5E20), // 深绿
      Color(0xFF66BB6A), // 浅绿
      Color(0xFF9EAE8E), // 灰绿
    ],
    this.defaultAnchorKey,
    this.defaultAnchorFraction = const Offset(0.05, 1.0),
    this.defaultAnchorOffset = const Offset(0, 20),
  });

  /// 实例稳定标识，用于持久化星位置。
  final String id;

  /// 当前状态（0..colors.length-1），星星颜色取 [colors][state]。
  final int state;

  /// 点击后以新状态回调（在状态数内循环）。
  final ValueChanged<int> onChanged;

  /// 各状态对应的颜色（至少一项）。
  final List<Color> colors;

  /// 默认位置的锚点区域（如棋盘）。为 null 时默认屏幕左下角附近。
  final GlobalKey? defaultAnchorKey;

  /// 默认位置在锚点区域内的相对坐标（0-1）。
  final Offset defaultAnchorFraction;

  /// 默认位置相对锚点坐标的额外偏移（像素）。
  final Offset defaultAnchorOffset;

  @override
  State<FloatingToggleStar> createState() => _FloatingToggleStarState();
}

class _FloatingToggleStarState extends State<FloatingToggleStar> {
  /// 星尺寸（像素）。
  static const double _starSize = 30;

  /// 星离屏幕边缘的最小留白。
  static const double _edgeMargin = 6;

  /// 星中心在屏幕中的归一化位置（0-1）；null 表示尚未保存过。
  Offset? _starPos;

  OverlayEntry? _entry;

  @override
  void initState() {
    super.initState();
    final saved = ConfigManager.instance.buttonBarConfig(widget.id);
    if (saved?.starX != null && saved?.starY != null) {
      _starPos = Offset(saved!.starX!, saved.starY!);
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _entry == null) {
        _entry = OverlayEntry(builder: _buildOverlay);
        Overlay.of(context).insert(_entry!);
      }
    });
  }

  @override
  void didUpdateWidget(covariant FloatingToggleStar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.state != widget.state) _refreshOverlay();
  }

  @override
  void dispose() {
    _entry?.remove();
    _entry = null;
    super.dispose();
  }

  /// 刷新浮层（延迟到当前事件结束，避免在 build/手势中重建）。
  void _refreshOverlay() {
    final entry = _entry;
    if (entry == null || !mounted) return;
    Future.microtask(() {
      if (mounted) entry.markNeedsBuild();
    });
  }

  /// 把当前位置写入配置并落盘。
  void _persist() {
    ConfigManager.instance.saveButtonBar(
      widget.id,
      ButtonBarConfig(starX: _starPos?.dx, starY: _starPos?.dy),
    );
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

  /// 未保存过位置时的默认归一化坐标。
  Offset _defaultPos(Size screenSize) {
    final key = widget.defaultAnchorKey;
    if (key != null) {
      final box = _safeRenderBox(key);
      if (box != null && box.attached) {
        final origin = box.localToGlobal(Offset.zero);
        final x = origin.dx +
            box.size.width * widget.defaultAnchorFraction.dx +
            widget.defaultAnchorOffset.dx;
        final y = origin.dy +
            box.size.height * widget.defaultAnchorFraction.dy +
            widget.defaultAnchorOffset.dy;
        return Offset(x / screenSize.width, y / screenSize.height);
      }
    }
    // 回退：屏幕左下角附近
    return const Offset(0.08, 0.8);
  }

  /// 把星中心坐标限制在屏幕内。
  Offset _clampCenter(Offset c, Size size) {
    const half = _starSize / 2;
    return Offset(
      c.dx.clamp(half + _edgeMargin, size.width - half - _edgeMargin),
      c.dy.clamp(half + _edgeMargin, size.height - half - _edgeMargin),
    );
  }

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
        final center = _clampCenter(
          Offset(pos.dx * size.width, pos.dy * size.height),
          size,
        );
        final color = widget.colors.isEmpty
            ? const Color(0xFF2E7D32)
            : widget.colors[widget.state % widget.colors.length];
        return Stack(
          children: [
            Positioned(
              left: center.dx - _starSize / 2,
              top: center.dy - _starSize / 2,
              width: _starSize,
              height: _starSize,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                // 拖动基于状态里的最新位置累加 delta（闭包捕获的是旧值）
                onPanUpdate: (d) {
                  final curPos = _starPos ?? _defaultPos(size);
                  final cur = Offset(
                    curPos.dx * size.width,
                    curPos.dy * size.height,
                  );
                  final next = _clampCenter(cur + d.delta, size);
                  _starPos =
                      Offset(next.dx / size.width, next.dy / size.height);
                  _refreshOverlay();
                },
                onPanEnd: (_) => _persist(),
                onTap: () {
                  final count =
                      widget.colors.isEmpty ? 1 : widget.colors.length;
                  widget.onChanged((widget.state + 1) % count);
                  _refreshOverlay();
                },
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    // 深色描边底层，保证星在任何背景上可见
                    const Icon(Icons.star,
                        size: _starSize + 4, color: Color(0xFF3A4A2E)),
                    Icon(Icons.star, size: _starSize, color: color),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}
