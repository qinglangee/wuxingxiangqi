import 'package:flutter/material.dart';

import '../shared/markdown_view.dart';

/// 软件介绍页面：用通用 [MarkdownView] 展示
/// `assets/markdown/instruction.md` 的内容。
class InstructionScreen extends StatelessWidget {
  const InstructionScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('软件介绍')),
      body: const SafeArea(
        child: MarkdownView.asset(path: 'assets/markdown/instruction.md'),
      ),
    );
  }
}
