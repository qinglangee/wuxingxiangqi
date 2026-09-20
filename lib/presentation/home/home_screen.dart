import 'package:flutter/material.dart';

/// 首页：中国象棋水墨风主菜单。
///
/// 三个入口卡片：棋谱 / 残局 / 打谱。
/// - 「打谱」跳转到对局页面（/play 路由）。
/// - 其余按钮暂用 SnackBar 占位。
class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          // 米黄宣纸底色
          color: Color(0xFFF5EDD8),
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
                          onTap: () => _placeholder(context, '棋谱'),
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
            onTap: () => _placeholder(context, '设置'),
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
