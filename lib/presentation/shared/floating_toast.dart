import 'package:flutter/material.dart';

/// 非模式浮动提示：在页面上层短暂显示一条信息，不阻挡用户操作，
/// 约 3 秒后自动消失（带淡入/淡出与轻微上移动画）。
///
/// 用法：
/// ```dart
/// FloatingToast.show(context, '保存成功');
/// ```
///
/// 连续调用时新提示会替换当前提示并重新计时；一般无需手动关闭，
/// 确需提前关闭可调用 [FloatingToast.dismiss]。
class FloatingToast {
  FloatingToast._();

  /// 默认展示时长。
  static const Duration duration = Duration(seconds: 3);

  /// 当前正在显示的提示（同一时刻最多一条）。
  static OverlayEntry? _entry;

  /// 弹出一条浮动提示。
  ///
  /// [message] 为提示文本；[icon] 可选，显示在文本左侧。
  static void show(BuildContext context, String message, {IconData? icon}) {
    final overlay = Overlay.maybeOf(context, rootOverlay: true);
    if (overlay == null) return;

    // 新提示直接替换旧提示（旧提示不再播放淡出）
    _entry?.remove();

    late final OverlayEntry entry;
    entry = OverlayEntry(
      builder: (_) => _ToastView(
        message: message,
        icon: icon,
        onFinished: () {
          // 仅当回调来自当前提示时才移除（已被新提示替换则忽略）
          if (identical(_entry, entry)) {
            _entry = null;
            entry.remove();
          }
        },
      ),
    );
    _entry = entry;
    overlay.insert(entry);
  }

  /// 立即关闭当前浮动提示（无提示时为空操作）。
  static void dismiss() {
    _entry?.remove();
    _entry = null;
  }
}

/// 提示外观与动画：顶部居中的悬浮卡片，自行负责计时与淡出。
class _ToastView extends StatefulWidget {
  const _ToastView({
    required this.message,
    required this.onFinished,
    this.icon,
  });

  final String message;
  final IconData? icon;

  /// 展示（含淡出动画）结束后回调，由 [FloatingToast] 移除 OverlayEntry。
  final VoidCallback onFinished;

  @override
  State<_ToastView> createState() => _ToastViewState();
}

class _ToastViewState extends State<_ToastView>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 220),
  );

  bool _finishing = false;

  @override
  void initState() {
    super.initState();
    _ctrl.forward();
    // 停留 3 秒后淡出，再通知上层移除
    Future.delayed(FloatingToast.duration, _close);
  }

  Future<void> _close() async {
    if (_finishing || !mounted) return;
    _finishing = true;
    await _ctrl.reverse();
    widget.onFinished();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Positioned(
      top: MediaQuery.of(context).padding.top + 56,
      left: 0,
      right: 0,
      child: IgnorePointer(
        // 非模式：不拦截任何手势
        child: Center(
          child: FadeTransition(
            opacity: _ctrl,
            child: SlideTransition(
              position: Tween<Offset>(
                begin: const Offset(0, -0.25),
                end: Offset.zero,
              ).animate(CurvedAnimation(
                parent: _ctrl,
                curve: Curves.easeOut,
              )),
              child: Material(
                color: Colors.transparent,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 20, vertical: 12),
                  decoration: BoxDecoration(
                    color: const Color(0xEE2C3E2D),
                    borderRadius: BorderRadius.circular(24),
                    boxShadow: const [
                      BoxShadow(
                        color: Color(0x33000000),
                        blurRadius: 12,
                        offset: Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (widget.icon != null) ...[
                        Icon(widget.icon, color: Colors.white, size: 20),
                        const SizedBox(width: 8),
                      ],
                      Flexible(
                        child: Text(
                          widget.message,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
