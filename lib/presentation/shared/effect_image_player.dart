import 'dart:math' as math;

import 'package:flutter/material.dart';

/// 通用特效图片播放器：把一张图片在屏幕中央播放一段特效动画后自动消失。
///
/// 动画时序（总时长约 2650ms）：
/// 1. 0~250ms：图片宽度从屏幕宽度的 70% 快速缩小到 30%（easeOut）；
/// 2. 250~750ms：在 30% 宽度下左右抖动几下（振幅渐弱的正弦位移）；
/// 3. 750~2250ms：停在屏幕中央展示 1.5 秒；
/// 4. 2250~2650ms：渐退消失。
///
/// 通过 [EffectImagePlayer.show] 以 Overlay 形式播放，不阻断界面操作；
/// 可用于绝杀提示等场景，也可在任何时刻播放任意特效图片。
class EffectImagePlayer {
  EffectImagePlayer._();

  /// 各阶段时长（停顿阶段 = 总时长减去其余阶段，无需单独常量）。
  static const Duration _shrinkDuration = Duration(milliseconds: 250);
  static const Duration _shakeDuration = Duration(milliseconds: 500);
  static const Duration _fadeDuration = Duration(milliseconds: 400);

  static const Duration _totalDuration = Duration(milliseconds: 2650);

  /// 图片初始宽度占屏幕宽度的比例。
  static const double _startWidthFraction = 0.70;

  /// 图片最终宽度占屏幕宽度的比例。
  static const double _endWidthFraction = 0.30;

  /// 抖动次数与最大振幅（像素）。
  static const int _shakeCount = 3;
  static const double _shakeAmplitude = 10;

  /// 在 [context] 上播放特效图片 [assetPath]（如 `assets/images/app/over.png`）。
  ///
  /// 图片宽度为屏幕宽度的 70%→30%，高度按图片原始宽高比自适应。
  /// 播放结束后自动移除，无需调用方管理生命周期。
  ///
  /// [boardCenter] 为特效的中心目标点（全局坐标）；不传则默认在屏幕
  /// 正中。用于把特效精确对齐到棋盘中心等场景。
  static void show(
    BuildContext context,
    String assetPath, {
    Offset? boardCenter,
  }) {
    _insert(
      context,
      boardCenter: boardCenter,
      content: Image.asset(
        assetPath,
        width: double.infinity,
        fit: BoxFit.contain,
      ),
      widthFractionOfScreen: true,
    );
  }

  /// 在 [context] 上播放一段特效文字消息（如「干得不错」「恭喜通关」）。
  ///
  /// 动画时序与 [show] 完全相同（70%→30% 缩放、抖动、停留、渐退），
  /// 文字以大号粗体描边样式居中显示。[color] 为文字颜色。
  static void showText(
    BuildContext context,
    String text, {
    Color color = const Color(0xFFE6A817),
    Offset? boardCenter,
  }) {
    _insert(
      context,
      boardCenter: boardCenter,
      widthFractionOfScreen: false,
      content: _EffectText(text: text, color: color),
    );
  }

  static void _insert(
    BuildContext context, {
    required Widget content,
    required bool widthFractionOfScreen,
    Offset? boardCenter,
  }) {
    final overlay = Overlay.maybeOf(context);
    if (overlay == null) return;
    late final OverlayEntry entry;
    entry = OverlayEntry(
      builder: (_) => _EffectImageWidget(
        boardCenter: boardCenter,
        widthFractionOfScreen: widthFractionOfScreen,
        onFinished: entry.remove,
        child: content,
      ),
    );
    overlay.insert(entry);
  }
}

/// 特效文字内容：大号粗体、带深色描边与阴影，保证在任意棋盘背景上清晰。
class _EffectText extends StatelessWidget {
  const _EffectText({required this.text, required this.color});

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    const fontSize = 52.0;
    return Text(
      text,
      textAlign: TextAlign.center,
      style: TextStyle(
        fontSize: fontSize,
        fontWeight: FontWeight.w900,
        color: color,
        letterSpacing: 4,
        shadows: const [
          Shadow(color: Color(0x99000000), blurRadius: 12, offset: Offset(0, 4)),
        ],
      ),
    );
  }
}

/// 特效内容动画组件（由 [EffectImagePlayer.show] / [EffectImagePlayer.showText]
/// 内部使用）。
class _EffectImageWidget extends StatefulWidget {
  const _EffectImageWidget({
    required this.onFinished,
    required this.child,
    required this.widthFractionOfScreen,
    this.boardCenter,
  });

  /// 要播放的内容（图片或文字）。
  final Widget child;

  /// 内容尺寸是否按屏幕宽度比例（true：图片 70%→30%；false：文字
  /// 按自身固定大小，缩放通过 Transform 完成）。
  final bool widthFractionOfScreen;

  /// 特效中心目标点（全局坐标）；为 null 时居中于屏幕。
  final Offset? boardCenter;

  /// 动画播放完成后的回调（用于移除 OverlayEntry）。
  final VoidCallback onFinished;

  @override
  State<_EffectImageWidget> createState() => _EffectImageWidgetState();
}

class _EffectImageWidgetState extends State<_EffectImageWidget>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: EffectImagePlayer._totalDuration,
    )..addStatusListener((status) {
        if (status == AnimationStatus.completed) {
          widget.onFinished();
        }
      });
    _ctrl.forward();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  /// 当前时间轴位置（毫秒）。
  double get _elapsedMs =>
      _ctrl.value * EffectImagePlayer._totalDuration.inMilliseconds;

  /// 宽度比例：缩小阶段 0.7→0.5（easeOut），之后固定 0.5。
  double _widthFraction() {
    final shrinkMs = EffectImagePlayer._shrinkDuration.inMilliseconds;
    final t = (_elapsedMs / shrinkMs).clamp(0.0, 1.0);
    const curve = Curves.easeOut;
    final v = curve.transform(t);
    return EffectImagePlayer._startWidthFraction +
        (EffectImagePlayer._endWidthFraction -
                EffectImagePlayer._startWidthFraction) *
            v;
  }

  /// 抖动水平位移：仅在抖动阶段，振幅随时间衰减的正弦波。
  double _shakeDx() {
    final shrinkMs = EffectImagePlayer._shrinkDuration.inMilliseconds;
    final shakeMs = EffectImagePlayer._shakeDuration.inMilliseconds;
    final t = (_elapsedMs - shrinkMs) / shakeMs;
    if (t <= 0 || t >= 1) return 0;
    final decay = 1 - t;
    return math.sin(t * math.pi * 2 * EffectImagePlayer._shakeCount) *
        EffectImagePlayer._shakeAmplitude *
        decay;
  }

  /// 不透明度：渐退阶段 1→0，其余为 1。
  double _opacity() {
    final fadeStartMs = EffectImagePlayer._totalDuration.inMilliseconds -
        EffectImagePlayer._fadeDuration.inMilliseconds;
    final t = (_elapsedMs - fadeStartMs) /
        EffectImagePlayer._fadeDuration.inMilliseconds;
    if (t <= 0) return 1;
    return (1 - t.clamp(0.0, 1.0));
  }

  @override
  Widget build(BuildContext context) {
    final screenW = MediaQuery.of(context).size.width;
    final screenH = MediaQuery.of(context).size.height;
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (_, _) {
        final center = widget.boardCenter;
        final alignment = center == null
            ? Alignment.center
            : Alignment(
                (center.dx / screenW) * 2 - 1,
                (center.dy / screenH) * 2 - 1,
              );
        // 图片：宽度 70%→30%；文字：同宽度的 FittedBox 等比缩放，
        // 使最终文字宽度约为屏幕宽度的 30%。
        final scale = _widthFraction();
        final content = widget.widthFractionOfScreen
            ? SizedBox(width: screenW * scale, child: widget.child)
            : SizedBox(
                width: screenW * scale,
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: widget.child,
                ),
              );
        return IgnorePointer(
          child: Opacity(
            opacity: _opacity(),
            child: Align(
              alignment: alignment,
              child: Transform.translate(
                offset: Offset(_shakeDx(), 0),
                child: content,
              ),
            ),
          ),
        );
      },
    );
  }
}
