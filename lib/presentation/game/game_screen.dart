import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../domain/models/piece.dart';
import '../../domain/models/position.dart';
import '../../core/config/app_config.dart';
import '../../core/config/config_manager.dart';
import '../canju/canju_controller.dart';
import '../canju/canju_level_dialog.dart';
import '../canju/canju_selector_dialog.dart';
import '../../core/canju/canju_library.dart';
import '../../core/services/sound_service.dart';
import '../controllers/game_controller.dart';
import '../shared/adjustable_button_bar.dart';
import '../shared/board_grid_painter.dart';
import '../shared/floating_toast.dart';
import '../shared/effect_image_player.dart';
import 'widgets/board_widget.dart';
import 'widgets/move_arrow_painter.dart';
import 'widgets/review_panel.dart';

/// 打谱页主状态。
enum GameScreenMode {
  /// 分析状态：打谱/棋谱浏览。
  analysis,

  /// 对弈状态：目前与分析状态作同样的处理。
  play,

  /// 残局状态。
  canju,
}

/// 主页面：拼装棋盘 + 结束弹窗。
///
/// 页面组件按状态分组：
/// - 残局专用：AppBar（含返回与残局标题）、_CanjuBar（上一局/下一局）；
/// - 分析专用：_AiConfigRow（AI 开关/重开/返回）、ReviewPanel
///   （棋谱注释 / 引擎 / 云库三标签）。
///
/// 残局状态显示 AppBar + 棋盘 + _CanjuBar；分析与对弈状态显示
/// _AiConfigRow + 棋盘 + ReviewPanel。
class GameScreen extends StatelessWidget {
  GameScreen({super.key});

  /// 棋盘组件的全局键，用于在绝杀时定位特效到棋盘中心。
  final boardKey = GlobalKey();

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<GameController>();
    final state = controller.state;
    // 残局模式下注入了 CanjuController；分析/对弈模式下未注入，这里取不到。
    final canju = _tryWatchCanju(context);
    // 对弈暂未单独入口，非残局一律按分析状态处理
    final mode =
        canju != null && !canju.analysisMode ? GameScreenMode.canju : GameScreenMode.analysis;
    final isCanju = mode == GameScreenMode.canju;
    return Scaffold(
      appBar: isCanju
          ? AppBar(
              leading: IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: () => Navigator.of(context).maybePop(),
              ),
              title: Text(
                  '${canju!.library.name} · 第 ${canju.currentIndex + 1}/${canju.total} 局'),
              actions: [
                if (controller.aiThinking)
                  const Padding(
                    padding: EdgeInsets.only(right: 16),
                    child: Center(
                      child: SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    ),
                  ),
              ],
            )
          : null,
      body: SafeArea(
        child: Column(
          children: [
            if (!isCanju)
              _AiConfigRow(
                controller: controller,
              ),
            // 上半部分：棋盘（整体可缩放，五角星把手上下拖动调整大小）
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 0, vertical: 4),
              child: _ScalableBoard(
                showHandle: !isCanju,
                child: BoardWidget(
                  key: boardKey,
                  board: state.board,
                  selected: state.selected,
                  hints: controller.selectedHints.toSet(),
                  onTap: controller.onTap,
                  branchMarkers: _buildBranchMarkers(controller),
                  analysisArrows: _buildAnalysisArrows(controller),
                  lastMove: _lastMoveOf(controller),
                  hintArrow: controller.hintMark,
                  flipped: controller.boardFlipped,
                  moveAnim: controller.moveAnim,
                ),
              ),
            ),
            // 残局切换条（上一局/下一局），位于棋盘下方
            if (isCanju) _CanjuBar(controller: canju!),
            // 下半部分：三标签打谱面板（占据棋盘外剩余的全部空间）
            if (!isCanju)
              Expanded(
                child: ReviewPanel(controller: controller),
              ),
          ],
        ),
      ),
      // 监听结束态，触发弹窗
      floatingActionButton: _ResultWatcher(boardKey: boardKey),
    );
  }

  /// 取可选的 [CanjuController]：残局模式返回实例，其它模式返回 null。
  /// 用 try/catch 是因为 [Provider.of] 在未注册时会抛 ProviderNotFoundException。
  CanjuController? _tryWatchCanju(BuildContext context) {
    try {
      return Provider.of<CanjuController>(context, listen: true);
    } on ProviderNotFoundException {
      return null;
    }
  }

  /// 在分支点（多于一条候选续着）为每条候选分支生成一支带序号的箭头。
  /// 单一续着或无续着时不显示任何标记。
  List<MoveArrow> _buildBranchMarkers(GameController controller) {
    final options = controller.branchOptions;
    if (options.length <= 1) return const [];
    return [
      for (var i = 0; i < options.length; i++)
        MoveArrow(
          from: options[i].move!.from,
          to: options[i].move!.to,
          color: MoveArrowPainter.palette[i % MoveArrowPainter.palette.length],
          label: branchLetter(i),
        ),
    ];
  }

  /// 当前局面节点对应的上一步走法（根节点/开局返回 null）。
  (Position, Position)? _lastMoveOf(GameController controller) {
    final m = controller.currentNode.move;
    if (m == null) return null;
    return (m.from, m.to);
  }

  /// 无限分析 PV1 前两步的指示箭头：红方红色、黑方黑色。
  List<MoveArrow> _buildAnalysisArrows(GameController controller) {
    return [
      for (final (from, to, side) in controller.analysisArrows)
        MoveArrow(
          from: from,
          to: to,
          color: side == Side.red
              ? const Color(0xFFC62828)
              : const Color(0xFF1A1A1A),
        ),
    ];
  }
}

/// 残局功能条：上一局/下一局 + 提示自动/重开/悔棋/提示/分析/题库/选棋。
class _CanjuBar extends StatelessWidget {
  const _CanjuBar({required this.controller});

  final CanjuController controller;

  @override
  Widget build(BuildContext context) {
    return AdjustableButtonBar(
      id: 'canju_bar',
      defaultPinnedIds: const {'上一局', '下一局', '提示', '重开', '悔棋'},
      buttons: [
        FreeButton(
          id: '上一局',
          icon: Icons.chevron_left,
          label: '上一局',
          enabled: controller.canPrev,
          onTap: controller.goPrev,
        ),
        FreeButton(
          id: '下一局',
          icon: Icons.chevron_right,
          label: '下一局',
          enabled: controller.canNext,
          onTap: controller.goNext,
        ),
        FreeButton(
          id: '提示自动',
          icon: Icons.auto_awesome,
          label: '提示自动',
          checked: controller.autoHint,
          onCheckedChanged: controller.setAutoHint,
        ),
        FreeButton(
          id: '自动下一局',
          icon: Icons.skip_next,
          label: '自动下一局',
          checked: controller.autoNext,
          onCheckedChanged: controller.setAutoNext,
        ),
        FreeButton(
          id: '重开',
          icon: Icons.refresh,
          label: '重开',
          onTap: controller.restartCurrent,
        ),
        FreeButton(
          id: '悔棋',
          icon: Icons.undo,
          label: '悔棋',
          onTap: controller.undoToRedTurn,
        ),
        FreeButton(
          id: '提示',
          icon: Icons.lightbulb_outline,
          label: '提示',
          onTap: controller.requestHint,
        ),
        FreeButton(
          id: '分析',
          icon: Icons.analytics_outlined,
          label: '分析',
          onTap: () {
            // 先播放切换音效，再进入分析状态
            SoundService.playChua();
            controller.enterAnalysisMode();
          },
        ),
        FreeButton(
          id: '题库',
          icon: Icons.menu_book_outlined,
          label: '题库',
          // 选择后弹窗与按钮栏抽屉都关闭，棋盘直接显示局面
          closesDrawer: true,
          onTap: () => _pickLibrary(context),
        ),
        FreeButton(
          id: '选棋',
          icon: Icons.grid_view,
          label: '选棋',
          closesDrawer: true,
          onTap: () => _pickLevel(context),
        ),
      ],
    );
  }

  /// 打开题库选择弹窗，选择后切换残局库。
  Future<void> _pickLibrary(BuildContext context) async {
    final libs = await CanjuLibraryLoader.loadAll();
    if (!context.mounted) return;
    final chosen = await CanjuSelectorDialog.show(
      context,
      libraries: libs,
      store: controller.store,
      currentLibraryName: controller.library.name,
    );
    if (chosen != null && chosen.name != controller.library.name) {
      await controller.switchLibrary(chosen);
    }
  }

  /// 打开选棋弹窗，选择后跳转到对应局。
  Future<void> _pickLevel(BuildContext context) async {
    final rec = controller.store.recordOf(controller.library.name);
    final chosen = await CanjuLevelDialog.show(
      context,
      count: controller.total,
      progress: rec.progress,
      currentIndex: controller.currentIndex,
    );
    if (chosen != null) {
      await controller.gotoIndex(chosen);
    }
  }
}

/// AI 配置行：红方电脑 / 黑方电脑 两个 check button + 文字显隐 + 返回。
/// 用 [AdjustableButtonBar] 布局，位于页面顶部。
class _AiConfigRow extends StatefulWidget {
  const _AiConfigRow({required this.controller});

  final GameController controller;

  @override
  State<_AiConfigRow> createState() => _AiConfigRowState();
}

class _AiConfigRowState extends State<_AiConfigRow> {
  @override
  Widget build(BuildContext context) {
    final ctrl = widget.controller;
    // 「显示文字」切换由 AdjustableButtonBar 内置按钮负责（默认不常驻）
    return AdjustableButtonBar(
      id: 'ai_config_bar',
      defaultPinnedIds: const {
        '返回','重开', '红AI', '黑AI', '分析', '出招', '分支', '反转',
      },
      buttons: [
        FreeButton(
          id: '返回',
          icon: Icons.arrow_back,
          label: '返回',
          onTap: () => Navigator.of(context).maybePop(),
        ),
        FreeButton(
          id: '重开',
          icon: Icons.refresh,
          label: '重开',
          onTap: ctrl.restart,
        ),
        FreeButton(
          id: '红AI',
          icon: Icons.computer,
          label: '红AI',
          checked: ctrl.redIsAi,
          onCheckedChanged: ctrl.setRedAi,
          iconColor: const Color(0xFFC62828),
        ),
        FreeButton(
          id: '黑AI',
          icon: Icons.computer,
          label: '黑AI',
          checked: ctrl.blackIsAi,
          onCheckedChanged: ctrl.setBlackAi,
          iconColor: const Color(0xFF1A1A1A),
        ),
        FreeButton(
          id: '分析',
          icon: Icons.search,
          label: '分析',
          checked: ctrl.isAnalysisOn,
          onCheckedChanged: ctrl.setAnalysis,
        ),
        FreeButton(
          id: '出招',
          icon: Icons.bolt,
          label: '出招',
          onTap: ctrl.playBestMove,
        ),
        FreeButton(
          id: '分支',
          icon: Icons.account_tree_outlined,
          label: '分支',
          onTap: ctrl.searchBranch,
        ),
        FreeButton(
          id: '反转',
          icon: Icons.swap_vert,
          label: '反转',
          checked: ctrl.boardFlipped,
          onCheckedChanged: ctrl.setBoardFlipped,
        ),
      ],
    );
  }
}

/// 监听 controller 结束态并显示浮动结果提示。
///
/// 自身不可见(返回 SizedBox.shrink)，仅用于副作用。
class _ResultWatcher extends StatefulWidget {
  const _ResultWatcher({required this.boardKey});

  /// 棋盘的 GlobalKey，用于把绝杀特效定位到棋盘中心。
  final GlobalKey boardKey;

  @override
  State<_ResultWatcher> createState() => _ResultWatcherState();
}

class _ResultWatcherState extends State<_ResultWatcher> {
  int _lastTick = 0;
  int _lastWinTick = 0;

  @override
  void initState() {
    super.initState();
    // 监听「游戏结束」音效：每次播放 win.mp3 同步播放绝杀动画，
    // 保证动画与音效在任何终局场景下都同时出现。
    _lastWinTick = SoundService.winTick.value;
    SoundService.winTick.addListener(_onWinTick);
  }

  @override
  void dispose() {
    SoundService.winTick.removeListener(_onWinTick);
    super.dispose();
  }

  void _onWinTick() {
    final tick = SoundService.winTick.value;
    if (tick == _lastWinTick) return;
    _lastWinTick = tick;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final box =
          widget.boardKey.currentContext?.findRenderObject() as RenderBox?;
      final center = box?.localToGlobal(
          Offset(box.size.width / 2, box.size.height / 2));
      EffectImagePlayer.show(
        context,
        'assets/images/app/over.png',
        boardCenter: center,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<GameController>();
    final tick = controller.resultTick;
    if (tick != _lastTick) {
      _lastTick = tick;
      // 仅在「新走子将死」时提示；前进/后退浏览已记录的终局不弹。
      // 使用非模式浮动提示，3 秒后自动消失，不阻断操作。
      if (controller.isOver) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          FloatingToast.show(
            context,
            '对局结束：${controller.result}',
            icon: Icons.flag_outlined,
          );
        });
      }
    }
    return const SizedBox.shrink();
  }
}

/// 可整体缩放的棋盘容器。
///
/// 棋盘宽度 = 可用宽度 × 配置缩放比例（[BoardConfig.boardScale]，默认 1.0
/// 占满）。棋盘下边缘横向 1/3 处浮着一个黄色五角星把手，上下拖动可整体
/// 缩放棋盘：向下放大、向上缩小；拖动结束后写入配置持久化。
class _ScalableBoard extends StatefulWidget {
  const _ScalableBoard({required this.child, this.showHandle = true});

  /// 棋盘组件（[BoardWidget]），按缩放后的宽度约束显示。
  final Widget child;

  /// 是否显示五角星缩放把手（残局模式不显示，但仍按配置缩放）。
  final bool showHandle;

  @override
  State<_ScalableBoard> createState() => _ScalableBoardState();
}

class _ScalableBoardState extends State<_ScalableBoard> {
  /// 把手尺寸（像素）。
  static const double _handleSize = 28;

  /// 拖动灵敏度：拖动 300 像素对应缩放 1.0。
  static const double _dragPixelsPerScale = 300;

  /// 拖动过程中的临时缩放值；非拖动状态为 null（跟随配置）。
  double? _draggingScale;

  @override
  Widget build(BuildContext context) {
    // 监听配置：设置页重置配置或拖动结束写盘后同步最新缩放
    return ListenableBuilder(
      listenable: ConfigManager.instance,
      builder: (context, _) {
        final scale = _draggingScale ??
            ConfigManager.instance.config.board.boardScale;
        return LayoutBuilder(
          builder: (context, constraints) {
            final boardWidth = constraints.maxWidth * scale;
            final boardHeight = BoardLayout.sizeForWidth(boardWidth).height;
            return Stack(
              children: [
                Align(
                  alignment: Alignment.topCenter,
                  child: SizedBox(
                    width: boardWidth,
                    height: boardHeight,
                    child: widget.child,
                  ),
                ),
                if (widget.showHandle)
                  Positioned(
                    // 棋盘下边缘横向 1/3 处，把手中心压在边缘线上
                    left: (constraints.maxWidth - boardWidth) / 2 +
                        boardWidth / 3 -
                        _handleSize / 2,
                    top: boardHeight - _handleSize / 2,
                    width: _handleSize,
                    height: _handleSize,
                    child: GestureDetector(
                      behavior: HitTestBehavior.translucent,
                      onVerticalDragUpdate: (d) {
                        setState(() {
                          final next = (_draggingScale ??
                                  ConfigManager
                                      .instance.config.board.boardScale) +
                              d.delta.dy / _dragPixelsPerScale;
                          _draggingScale = next.clamp(
                              BoardConfig.kMinBoardScale,
                              BoardConfig.kMaxBoardScale);
                        });
                      },
                      onVerticalDragEnd: (_) {
                        final v = _draggingScale;
                        _draggingScale = null;
                        if (v != null &&
                            v !=
                                ConfigManager
                                    .instance.config.board.boardScale) {
                          ConfigManager.instance.updateBoard((b) {
                            b.boardScale = v;
                            return b;
                          });
                        }
                      },
                      child: const Stack(
                        alignment: Alignment.center,
                        children: [
                          // 深色描边底层，保证黄色五角星在浅色棋盘上可见
                          Icon(Icons.star, size: _handleSize + 4,
                              color: Color(0xFF7A5C1E)),
                          Icon(Icons.star, size: _handleSize,
                              color: Color(0xFFFFD54F)),
                        ],
                      ),
                    ),
                  ),
              ],
            );
          },
        );
      },
    );
  }
}
