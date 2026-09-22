import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../core/config/config_manager.dart';
import '../../domain/notation/parsers/notation_exception.dart';
import '../../domain/notation/parsers/notation_loader.dart';
import '../../domain/notation/parsers/notation_replay.dart';
import '../../domain/notation/parsers/parsed_game.dart';

/// 首页：中国象棋水墨风主菜单。
///
/// 三个入口卡片：棋谱 / 残局 / 打谱。
/// - 「棋谱」打开棋谱仓库目录（未配置时引导用户选择目录）。
/// - 「打谱」跳转到对局页面（/play 路由）。
/// - 「残局」与右上角设置按钮暂用 SnackBar 占位。
class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          // 首屏背景图：整幅铺满
          image: DecorationImage(
            image: AssetImage('assets/images/bg/default.jpeg'),
            fit: BoxFit.cover,
          ),
        ),
        child: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: Column(
                children: [
                  const SizedBox(height: 56),
                  _buildTitleBar(context),
                  const SizedBox(height: 48),
                  Expanded(
                    child: ListView(
                      padding: const EdgeInsets.symmetric(horizontal: 28),
                      children: [
                        _MenuCard(
                          title: '棋谱',
                          subtitle: '收藏与浏览经典棋谱',
                          icon: const _BoardIcon(),
                          onTap: () => _openNotationLibrary(context),
                        ),
                        const SizedBox(height: 24),
                        _MenuCard(
                          title: '残局',
                          subtitle: '练习经典残局破解',
                          icon: const _PiecesIcon(),
                          onTap: () => _placeholder(context, '残局'),
                        ),
                        const SizedBox(height: 24),
                        _MenuCard(
                          title: '打谱',
                          subtitle: '开始一局新棋',
                          icon: const _BoardIcon(),
                          highlight: true,
                          onTap: () => Navigator.of(context).pushNamed('/play'),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 32),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTitleBar(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Row(
        children: [
          Container(width: 36, height: 2, color: const Color(0xFF8B6B3D)),
          const SizedBox(width: 12),
          const Expanded(
            child: Center(
              child: Text(
                '五星象棋',
                style: TextStyle(
                  fontSize: 34,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF2C3E2D),
                  letterSpacing: 6,
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          GestureDetector(
            onTap: () => Navigator.of(context).pushNamed('/settings'),
            child: const Icon(Icons.settings, color: Color(0xFF8B6B3D), size: 28),
          ),
          const SizedBox(width: 36),
        ],
      ),
    );
  }

  void _placeholder(BuildContext context, String name) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('$name 功能开发中')),
    );
  }

  // ---------------------------------------------------------------------------
  // 棋谱仓库：打开已配置目录或引导用户先选择目录
  // ---------------------------------------------------------------------------

  /// 点击「棋谱」按钮：
  /// 1. 读取配置中的 [LibraryConfig.notationLibraryPath]；
  /// 2. 已配置且目录可写入 → 用文件选择器从该目录起手让用户选择棋谱文件；
  /// 3. 未配置或目录失效 → 提示并引导用户选择目录，验证可写后保存配置，
  ///    再继续打开文件选择器。
  Future<void> _openNotationLibrary(BuildContext context) async {
    final mgr = ConfigManager.instance;
    var path = mgr.config.library.notationLibraryPath;

    // 已配置：检查目录仍存在且可写
    if (path != null && path.isNotEmpty) {
      final ok = await ConfigManager.isDirectoryWritable(path);
      if (!ok) {
        // 配置失效（目录被删/权限丢失），清空并走选择流程
        await mgr.updateLibrary((c) => c.copyWith()..notationLibraryPath = null);
        path = null;
      }
    }

    // 未配置：提示并引导用户选择目录
    if (path == null || path.isEmpty) {
      if (!context.mounted) return;
      final accepted = await _promptChooseDirectory(context);
      if (!accepted) return;
      final picked = await FilePicker.getDirectoryPath(
        dialogTitle: '选择棋谱仓库目录',
      );
      if (picked == null || picked.isEmpty) return;
      final writable = await ConfigManager.isDirectoryWritable(picked);
      if (!writable) {
        if (!context.mounted) return;
        await showDialog<void>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('目录不可用'),
            content: Text('所选目录不存在或不可写入：\n$picked\n请选择其它目录。'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('知道了'),
              ),
            ],
          ),
        );
        return;
      }
      await mgr.updateLibrary(
        (c) => c.copyWith()..notationLibraryPath = picked,
      );
      path = picked;
    }

    // 已配置：打开文件选择器，让用户在仓库目录中选择棋谱或进入子目录
    final file = await FilePicker.pickFiles(
      dialogTitle: '选择棋谱文件',
      initialDirectory: path,
      type: FileType.custom,
      allowedExtensions: const ['pgn', 'xqf', 'cbf', 'txt'],
    );
    if (file.isEmpty) return;
    final pickedPath = file.single.path;
    if (pickedPath == null || pickedPath.isEmpty) return;

    // 读取文件字节并交给解析器；解析后还会在内存中完整回放一遍校验，
    // 任何一步失败都弹窗提示，且不跳转到打谱页（避免在页面构建期抛异常）。
    final bytes = await File(pickedPath).readAsBytes();
    ParsedGame? parsed;
    ReplayData? replay;
    String? errMsg;
    try {
      parsed = NotationLoader.load(path: pickedPath, bytes: bytes);
      // 完整回放验证：起始 FEN、每步坐标反解与规则校验
      replay = NotationReplay.resolve(parsed);
    } on NotationParseException catch (e) {
      errMsg = e.message;
    } catch (e) {
      errMsg = '读取或解析文件时出错：$e';
    }

    if (!context.mounted) return;
    if (parsed != null && replay != null) {
      // 解析与回放均成功：把棋谱与已验证的坐标一起传给打谱页
      Navigator.of(context).pushNamed(
        '/play',
        arguments: (parsed, replay),
      );
    } else {
      // 解析/回放失败：弹出错误对话框显示详情，停留当前页
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('棋谱解析失败'),
          content: Text(errMsg ?? '未知错误'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('知道了'),
            ),
          ],
        ),
      );
    }
  }

  /// 弹出对话框提示用户先选择棋谱仓库目录。
  /// 返回 true 表示用户同意继续选择目录；false 表示取消。
  Future<bool> _promptChooseDirectory(BuildContext context) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('尚未配置棋谱仓库'),
        content: const Text('需要先选择一个目录作为棋谱仓库，是否现在选择？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('选择目录'),
          ),
        ],
      ),
    );
    return result ?? false;
  }
}

// ---------------------------------------------------------------------------
// 菜单卡片
// ---------------------------------------------------------------------------

class _MenuCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final Widget icon;
  final VoidCallback onTap;
  final bool highlight;

  const _MenuCard({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.onTap,
    this.highlight = false,
  });

  @override
  Widget build(BuildContext context) {
    final borderColor =
        highlight ? const Color(0xFF8B5A2B) : const Color(0xFFC9B68C);
    final buttonBg = highlight ? const Color(0xFF8B5A2B) : const Color(0xFF2C3E2D);

    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 168,
        decoration: BoxDecoration(
          color: const Color(0xFFFDF6E3),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: borderColor, width: 1.2),
          boxShadow: const [
            BoxShadow(
              color: Color(0x20000000),
              blurRadius: 10,
              offset: Offset(0, 4),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              // 左侧插画
              Expanded(
                flex: 2,
                child: Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF5E6C8),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: icon,
                ),
              ),
              const SizedBox(width: 16),
              // 右侧大按钮
              Expanded(
                flex: 3,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 22, vertical: 12),
                      decoration: BoxDecoration(
                        color: buttonBg,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        title,
                        style: const TextStyle(
                          fontSize: 26,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFFFDF6E3),
                          letterSpacing: 4,
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        fontSize: 13,
                        color: Color(0xFF8B6B3D),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// 左侧插画：棋盘缩略
// ---------------------------------------------------------------------------

class _BoardIcon extends StatelessWidget {
  const _BoardIcon();

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _BoardPainter(),
      size: const Size(double.infinity, double.infinity),
    );
  }
}

class _BoardPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final linePaint = Paint()
      ..color = const Color(0xFF5A3A1A)
      ..strokeWidth = 1.0;

    const cols = 8;
    const rows = 9;
    final pad = 4.0;
    final gridW = size.width - pad * 2;
    final gridH = size.height - pad * 2;
    final cellW = gridW / cols;
    final cellH = gridH / rows;

    // 竖线
    for (var c = 0; c <= cols; c++) {
      canvas.drawLine(
        Offset(pad + c * cellW, pad),
        Offset(pad + c * cellW, pad + rows * cellH),
        linePaint,
      );
    }
    // 横线
    for (var r = 0; r <= rows; r++) {
      canvas.drawLine(
        Offset(pad, pad + r * cellH),
        Offset(pad + cols * cellW, pad + r * cellH),
        linePaint,
      );
    }

    // 上九宫斜线
    canvas.drawLine(
      Offset(pad + 3 * cellW, pad),
      Offset(pad + 5 * cellW, pad + 2 * cellH),
      linePaint,
    );
    canvas.drawLine(
      Offset(pad + 5 * cellW, pad),
      Offset(pad + 3 * cellW, pad + 2 * cellH),
      linePaint,
    );
    // 下九宫斜线
    canvas.drawLine(
      Offset(pad + 3 * cellW, pad + 7 * cellH),
      Offset(pad + 5 * cellW, pad + rows * cellH),
      linePaint,
    );
    canvas.drawLine(
      Offset(pad + 5 * cellW, pad + 7 * cellH),
      Offset(pad + 3 * cellW, pad + rows * cellH),
      linePaint,
    );

    // 象征性棋子
    final redPaint = Paint()..color = const Color(0xFFC62828);
    const positions = [
      (0, 0), (4, 0), (8, 0),
      (2, 4), (6, 4),
      (3, 7), (5, 7),
      (0, 9), (4, 9), (8, 9),
    ];
    for (final (r, c) in positions) {
      canvas.drawCircle(
        Offset(pad + c * cellW, pad + r * cellH),
        3.5,
        redPaint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

// ---------------------------------------------------------------------------
// 左侧插画：散落棋子
// ---------------------------------------------------------------------------

class _PiecesIcon extends StatelessWidget {
  const _PiecesIcon();

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _PiecesPainter(),
      size: const Size(double.infinity, double.infinity),
    );
  }
}

class _PiecesPainter extends CustomPainter {
  static const _pieces = [
    _Piece(0.25, 0.30, 8.0, Color(0xFFC62828), '帅'),
    _Piece(0.55, 0.22, 7.0, Color(0xFF2C3E2D), '将'),
    _Piece(0.72, 0.38, 8.0, Color(0xFFC62828), '车'),
    _Piece(0.30, 0.55, 9.0, Color(0xFF2C3E2D), '马'),
    _Piece(0.55, 0.62, 8.0, Color(0xFFC62828), '炮'),
    _Piece(0.20, 0.78, 7.0, Color(0xFF2C3E2D), '兵'),
    _Piece(0.68, 0.80, 7.0, Color(0xFFC62828), '相'),
  ];

  @override
  void paint(Canvas canvas, Size size) {
    for (final p in _pieces) {
      final cx = size.width * p.x;
      final cy = size.height * p.y;

      // 阴影
      canvas.drawCircle(
        Offset(cx + 1.5, cy + 1.5),
        p.radius,
        Paint()..color = const Color(0x30000000),
      );
      // 棋子底
      canvas.drawCircle(
        Offset(cx, cy),
        p.radius,
        Paint()
          ..color = const Color(0xFFFDF6E3)
          ..style = PaintingStyle.fill,
      );
      // 棋子边框
      canvas.drawCircle(
        Offset(cx, cy),
        p.radius,
        Paint()
          ..color = const Color(0xFF8B5A2B)
          ..style = PaintingStyle.stroke,
      );
      // 棋子文字
      final tp = TextPainter(
        text: TextSpan(
          text: p.char,
          style: TextStyle(
            color: p.color,
            fontSize: p.radius * 1.1,
            fontWeight: FontWeight.bold,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(
        canvas,
        Offset(cx - tp.width / 2, cy - tp.height / 2),
      );
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _Piece {
  final double x;
  final double y;
  final double radius;
  final Color color;
  final String char;

  const _Piece(this.x, this.y, this.radius, this.color, this.char);
}
