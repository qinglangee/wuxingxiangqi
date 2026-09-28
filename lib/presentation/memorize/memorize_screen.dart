import 'package:flutter/material.dart';

import '../../core/services/sound_service.dart';
import '../../domain/models/piece.dart';
import '../../domain/notation/parsers/parsed_game.dart';
import '../game/widgets/board_widget.dart';
import '../game/widgets/move_arrow_painter.dart';
import '../shared/effect_image_player.dart';
import 'memorize_controller.dart';

/// 背谱页面：接收一份 [ParsedGame]，由 [MemorizeController] 驱动按谱背棋。
///
/// 棋盘居中，棋盘下方为控制面板（选择执方 / 行棋状态 / 完成提示）。
class MemorizeScreen extends StatefulWidget {
  const MemorizeScreen({super.key, required this.game});

  /// 打开背谱页面（由复盘导航条的「背谱」按钮调用）。
  static Future<void> open(BuildContext context, ParsedGame game) {
    return Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => MemorizeScreen(game: game),
      ),
    );
  }

  final ParsedGame game;

  @override
  State<MemorizeScreen> createState() => _MemorizeScreenState();
}

class _MemorizeScreenState extends State<MemorizeScreen> {
  late final MemorizeController _controller = MemorizeController(widget.game);

  /// 棋盘组件键：用于把「干得不错/恭喜」特效定位到棋盘中心。
  final GlobalKey _boardKey = GlobalKey();

  int _lastLineTick = 0;
  int _lastFinishTick = 0;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// 0 → A、1 → B … 的分支字母（与复盘面板保持一致）。
  String _branchLetter(int i) =>
      String.fromCharCode(i < 26 ? 65 + i : 97 + (i - 26));

  /// 当前分支点的候选续着标记：未走过的按调色板着色并标分支字母，
  /// 已走过的置灰并打勾。
  List<MoveArrow> _buildMarkers() {
    final node = _controller.currentNode;
    if (node.children.length <= 1) return const [];
    final markers = <MoveArrow>[];
    for (var i = 0; i < node.children.length; i++) {
      final child = node.children[i];
      final m = child.move!;
      final walked = _controller.isWalked(child);
      markers.add(MoveArrow(
        from: m.from,
        to: m.to,
        color: walked
            ? const Color(0x889E9E9E)
            : MoveArrowPainter.palette[i % MoveArrowPainter.palette.length],
        label: walked ? '✓' : _branchLetter(i),
      ));
    }
    return markers;
  }

  void _handleTickChanges() {
    final lineTick = _controller.lineCompleteTick;
    if (lineTick != _lastLineTick) {
      _lastLineTick = lineTick;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        EffectImagePlayer.showText(
          context,
          '干得不错',
          color: const Color(0xFF2E7D32),
          boardCenter: _boardCenter(),
        );
      });
    }
    final finishTick = _controller.allCompleteTick;
    if (finishTick != _lastFinishTick) {
      _lastFinishTick = finishTick;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        SoundService.playWin();
        EffectImagePlayer.showText(
          context,
          '恭喜通关',
          color: const Color(0xFFE6A817),
          boardCenter: _boardCenter(),
        );
      });
    }
  }

  Offset? _boardCenter() {
    final box =
        _boardKey.currentContext?.findRenderObject() as RenderBox?;
    return box?.localToGlobal(
        Offset(box.size.width / 2, box.size.height / 2));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('背谱'),
        actions: [
          IconButton(
            tooltip: '重开',
            icon: const Icon(Icons.replay),
            onPressed:
                _controller.phase == MemorizePhase.choosing ? null : _restart,
          ),
        ],
      ),
      body: SafeArea(
        child: AnimatedBuilder(
          animation: _controller,
          builder: (context, _) {
            _handleTickChanges();
            return Column(
              children: [
                // 棋盘区：占据页面中部
                Expanded(
                  child: Center(
                    child: BoardWidget(
                      key: _boardKey,
                      board: _controller.state.board,
                      selected: _controller.state.selected,
                      hints: _controller.selectedHints.toSet(),
                      onTap: _controller.onTap,
                      branchMarkers: _buildMarkers(),
                      lastMove: _controller.currentNode.move == null
                          ? null
                          : (
                              _controller.currentNode.move!.from,
                              _controller.currentNode.move!.to,
                            ),
                      flipped: _controller.userSide == Side.black,
                      moveAnim: _controller.moveAnim,
                    ),
                  ),
                ),
                _buildBottomPanel(),
              ],
            );
          },
        ),
      ),
    );
  }

  void _restart() {
    _lastLineTick = 0;
    _lastFinishTick = 0;
    _controller.restart();
  }

  /// 棋盘下方控制面板。
  Widget _buildBottomPanel() {
    final phase = _controller.phase;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
      decoration: const BoxDecoration(
        color: Color(0xFFFBF3DF),
        border: Border(top: BorderSide(color: Color(0xFFD8C69A), width: 0.6)),
      ),
      child: switch (phase) {
        MemorizePhase.choosing => _buildChoosingPanel(),
        MemorizePhase.running => _buildRunningPanel(),
        MemorizePhase.finished => _buildFinishedPanel(),
      },
    );
  }

  /// 选择执红 / 执黑。
  Widget _buildChoosingPanel() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Padding(
          padding: EdgeInsets.only(bottom: 12),
          child: Text(
            '请选择你要执的一方，另一方由程序按棋谱陪练',
            style: TextStyle(fontSize: 14, color: Color(0xFF8B6B3D)),
          ),
        ),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _SideButton(
              label: '执红（红方先手）',
              color: const Color(0xFFC62828),
              icon: Icons.circle,
              onTap: () => _controller.start(Side.red),
            ),
            const SizedBox(width: 20),
            _SideButton(
              label: '执黑',
              color: const Color(0xFF262626),
              icon: Icons.circle,
              onTap: () => _controller.start(Side.black),
            ),
          ],
        ),
      ],
    );
  }

  /// 进行中：行棋状态 + 已练习进度。
  Widget _buildRunningPanel() {
    final userSide = _controller.userSide!;
    final sideText = userSide == Side.red ? '红方' : '黑方';
    final status = _controller.busy
        ? '电脑思考中…'
        : '轮到你走棋（执$sideText）';
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          status,
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: Color(0xFF5D4423),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          '已练习 ${_controller.walkedCount}/${_controller.totalEdges} 步'
          '（✓ 为已走过的变着）',
          style: const TextStyle(fontSize: 13, color: Color(0xFF8B6B3D)),
        ),
      ],
    );
  }

  /// 全树走完：完成提示 + 再来一次。
  Widget _buildFinishedPanel() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Padding(
          padding: EdgeInsets.only(bottom: 10),
          child: Text(
            '棋谱中的全部变着都已背完！',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: Color(0xFF5D4423),
            ),
          ),
        ),
        FilledButton.icon(
          onPressed: _restart,
          icon: const Icon(Icons.replay),
          label: const Text('重开，重新选择执方'),
        ),
      ],
    );
  }
}

/// 执方选择大按钮。
class _SideButton extends StatelessWidget {
  const _SideButton({
    required this.label,
    required this.color,
    required this.icon,
    required this.onTap,
  });

  final String label;
  final Color color;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return FilledButton.icon(
      onPressed: onTap,
      icon: Icon(icon, size: 18),
      label: Text(label),
      style: FilledButton.styleFrom(
        backgroundColor: color,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      ),
    );
  }
}
