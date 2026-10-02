import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_markdown/flutter_markdown.dart';

import '../../core/theme/app_theme.dart';

/// 通用 Markdown 展示控件。
///
/// 两种用法：
/// - [MarkdownView.asset]：从 assets 路径异步加载 `.md` 文件内容；
/// - [MarkdownView.text]：直接展示给定的 Markdown 文本。
///
/// 内置水墨风自定义样式（[defaultStyleSheet]），也可通过 [styleSheet]
/// 覆盖；内容默认可选择、整体可滚动。其它页面需要展示 Markdown 时
/// 直接复用本控件即可。
class MarkdownView extends StatelessWidget {
  /// 直接展示 Markdown 文本。
  const MarkdownView.text({
    super.key,
    required this.data,
    this.styleSheet,
    this.padding = const EdgeInsets.all(20),
    this.onTapLink,
  })  : assetPath = null;

  /// 从 assets 加载 Markdown 文件（如 `assets/markdown/xxx.md`）。
  const MarkdownView.asset({
    super.key,
    required String path,
    this.styleSheet,
    this.padding = const EdgeInsets.all(20),
    this.onTapLink,
  })  : data = null,
        assetPath = path;

  /// 直接传入的 Markdown 文本（与 [assetPath] 二选一）。
  final String? data;

  /// assets 中的 Markdown 文件路径。
  final String? assetPath;

  /// 自定义样式表；为空时使用 [defaultStyleSheet]。
  final MarkdownStyleSheet? styleSheet;

  /// 内容区内边距。
  final EdgeInsets padding;

  /// 点击链接回调（href、文本均会传入）；为空时链接不可点击。
  final void Function(String href, String title)? onTapLink;

  /// 应用水墨风的默认 Markdown 样式：深棕标题、米色引用块、棕色链接。
  static MarkdownStyleSheet defaultStyleSheetOf(BuildContext context) {
    final base = Theme.of(context);
    const ink = Color(0xFF3E2F1C); // 正文墨色
    const titleBrown = AppTheme.boardLine; // 标题深棕
    const accentBrown = Color(0xFF8B5A2B); // 次级标题/链接棕
    return MarkdownStyleSheet.fromTheme(base).copyWith(
      p: const TextStyle(fontSize: 15, height: 1.75, color: ink),
      h1: const TextStyle(
        fontSize: 24,
        fontWeight: FontWeight.w700,
        color: titleBrown,
        height: 1.4,
      ),
      h1Padding: const EdgeInsets.only(top: 12, bottom: 12),
      h2: const TextStyle(
        fontSize: 20,
        fontWeight: FontWeight.w700,
        color: accentBrown,
        height: 1.4,
      ),
      h2Padding: const EdgeInsets.only(top: 20, bottom: 8),
      h3: const TextStyle(
        fontSize: 17,
        fontWeight: FontWeight.w700,
        color: titleBrown,
        height: 1.4,
      ),
      h3Padding: const EdgeInsets.only(top: 16, bottom: 6),
      h4: const TextStyle(
        fontSize: 16,
        fontWeight: FontWeight.w700,
        color: ink,
      ),
      strong: const TextStyle(color: titleBrown, fontWeight: FontWeight.w700),
      em: const TextStyle(fontStyle: FontStyle.italic),
      listBullet: const TextStyle(fontSize: 15, color: accentBrown),
      listIndent: 24,
      blockSpacing: 12,
      // 链接：棕色下划线
      a: const TextStyle(
        color: accentBrown,
        decoration: TextDecoration.underline,
        decorationColor: accentBrown,
        fontSize: 15,
      ),
      // 引用块：米色底 + 左侧棕色竖条
      blockquote: const TextStyle(
        fontSize: 14,
        height: 1.7,
        color: Color(0xFF6B5638),
      ),
      blockquoteDecoration: BoxDecoration(
        color: const Color(0x33F5E6C8),
        borderRadius: BorderRadius.circular(6),
        border: const Border(
          left: BorderSide(color: accentBrown, width: 3),
        ),
      ),
      blockquotePadding:
          const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      // 行内代码
      code: const TextStyle(
        fontFamily: 'monospace',
        fontSize: 13,
        color: Color(0xFF5A3A1A),
        backgroundColor: Color(0x1A8B5A2B),
      ),
      // 代码块
      codeblockDecoration: BoxDecoration(
        color: const Color(0xFFF5E6C8),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFC9B68C)),
      ),
      codeblockPadding: const EdgeInsets.all(12),
      horizontalRuleDecoration: const BoxDecoration(
        border: Border(
          top: BorderSide(color: Color(0xFFC9B68C), width: 0.8),
        ),
      ),
      tableHead: const TextStyle(
        fontWeight: FontWeight.w700,
        color: titleBrown,
      ),
      tableBorder: TableBorder.all(color: const Color(0xFFC9B68C)),
      tableCellsPadding:
          const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
    );
  }

  @override
  Widget build(BuildContext context) {
    final inline = data;
    if (inline != null) {
      return _buildMarkdown(context, inline);
    }
    return FutureBuilder<String>(
      future: rootBundle.loadString(assetPath!),
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text(
                '内容加载失败：${snapshot.error}',
                style: const TextStyle(color: Colors.red),
              ),
            ),
          );
        }
        return _buildMarkdown(context, snapshot.data ?? '');
      },
    );
  }

  Widget _buildMarkdown(BuildContext context, String content) {
    return Markdown(
      data: content,
      selectable: true,
      padding: padding,
      styleSheet: styleSheet ?? defaultStyleSheetOf(context),
      onTapLink: (text, href, title) {
        if (href != null && href.isNotEmpty) {
          onTapLink?.call(href, title.isEmpty ? text : title);
        }
      },
    );
  }
}
