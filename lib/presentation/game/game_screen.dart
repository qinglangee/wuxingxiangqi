import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../domain/models/piece.dart';
import '../../domain/models/position.dart';
import '../../core/config/app_config.dart';
import '../../core/config/config_manager.dart';
import '../../core/constants/board_constants.dart';
import '../../core/theme/app_theme.dart';
import '../canju/canju_controller.dart';
import '../canju/canju_level_dialog.dart';
import '../canju/canju_selector_dialog.dart';
import '../../core/canju/canju_library.dart';
import '../../core/services/sound_service.dart';
import '../controllers/game_controller.dart';
import '../shared/adjustable_button_bar.dart';
import '../shared/board_grid_painter.dart';
import '../shared/effect_image_player.dart';
import 'widgets/board_widget.dart';
import 'widgets/move_arrow_painter.dart';
import 'widgets/opponent_dialog.dart';
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

/// 主页面：拼装棋盘 + 结束弹窗，自适应横竖屏布局。
///
/// 页面组件按状态分组：
/// - 残局专用：AppBar（含返回与残局标题）、_CanjuBar（上一局/下一局）；
/// - 分析专用：_AiConfigRow（AI 开关/重开/返回）、ReviewPanel
///   （棋谱注释 / 引擎 / 云库三标签）。
///
/// 自适应布局（[LayoutBuilder] 判定）：
/// - 竖屏（高 ≥ 宽）：保持上下布局——顶部条 + 棋盘 + 底部条 + 打谱面板；
/// - 横屏（宽 > 高）：棋盘独占左侧尽量放大，其余组件按原顺序放右侧，
///   形成左右主要布局。
class GameScreen extends StatelessWidget {
  GameScreen({super.key});

  /// 棋盘组件的全局键，用于在绝杀时定位特效到棋盘中心。
  final boardKey = GlobalKey();

  /// 棋盘区域（缩放后）的定位键：黄星缩放把手与打谱页浮动红星
  /// 都据此计算默认/当前位置。
  final boardAreaKey = GlobalKey();

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<GameController>();
    // 残局模式下注入了 CanjuController；分析/对弈模式下未注入，这里取不到。
    final canju = _tryWatchCanju(context);
    // 对弈模式：由 GameController.playMode 控制，隐藏全部工具条与面板
    final isPlay = controller.playMode;
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
      body: Container(
        // 打谱页背景图
        decoration: const BoxDecoration(
          image: DecorationImage(
            image: AssetImage('assets/images/bg/default.jpeg'),
            fit: BoxFit.cover,
          ),
        ),
        child: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) {
              // 提取的通用组件
              final topBar = _buildTopBar(controller, isPlay, isCanju);
              final bottomBar =
                  _buildBottomBar(controller, canju, isPlay, isCanju);
              final review =
                  (!isCanju && !isPlay) ? _buildReviewPanel(controller) : null;
              final board = _buildBoard(controller, isPlay, isCanju);

              // 竖屏（高 ≥ 宽）：保持原有上下布局
              if (constraints.maxWidth <= constraints.maxHeight) {
                return Column(
                  children: [
                    ?topBar,
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 0),
                      child: board,
                    ),
                    ?bottomBar,
                    if (review != null) Expanded(child: review),
                  ],
                );
              }

              // 横屏（宽 > 高）：棋盘独占左侧放大，其余组件按原顺序放右侧
              return Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: SizedBox(
                      width: _landscapeBoardWidth(constraints),
                      child: board,
                    ),
                  ),
                  const VerticalDivider(
                    width: 1,
                    thickness: 1,
                    color: Color(0x44C9B68C),
                  ),
                  Expanded(
                    child: Column(
                      children: [
                        ?topBar,
                        ?bottomBar,
                        if (review != null) Expanded(child: review),
                      ],
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
      // 监听结束态，触发弹窗
      floatingActionButton: _ResultWatcher(boardKey: boardKey),
    );
  }

  /// 顶部工具条：对弈模式显示对手头像框，分析模式显示 AI 配置条，
  /// 残局模式无顶部条（残局标题在 AppBar 中）。
  Widget? _buildTopBar(GameController controller, bool isPlay, bool isCanju) {
    if (isPlay) return _PlayOpponentBar(controller: controller);
    if (!isCanju && !isPlay) return _AiConfigRow(controller: controller);
    return null;
  }

  /// 棋盘下方组件：残局切换条 / 对弈控制区；分析模式为 null。
  Widget? _buildBottomBar(GameController controller, CanjuController? canju,
      bool isPlay, bool isCanju) {
    if (isCanju) return _CanjuBar(controller: canju!);
    if (isPlay) return _PlayControls(controller: controller);
    return null;
  }

  /// 打谱面板（棋谱注释 / 引擎 / 云库三标签），仅分析模式显示。
  Widget _buildReviewPanel(GameController controller) {
    return ReviewPanel(controller: controller, boardAreaKey: boardAreaKey);
  }

  /// 棋盘区域（可整体缩放 + 滑动翻谱），竖屏横屏共用。
  Widget _buildBoard(GameController controller, bool isPlay, bool isCanju) {
    final state = controller.state;
    return _ScalableBoard(
      showHandle: !isCanju && !isPlay,
      boardAreaKey: boardAreaKey,
      // 打谱页棋盘滑动：上滑前进一步，下滑后退一步
      onSwipeUp: (!isCanju && !isPlay) ? controller.goForward : null,
      onSwipeDown: (!isCanju && !isPlay) ? controller.goBack : null,
      child: BoardWidget(
        key: boardKey,
        board: state.board,
        selected: state.selected,
        hints: controller.selectedHints.toSet(),
        onTap: controller.onTap,
        branchMarkers: _buildBranchMarkers(controller),
        onBranchTap: controller.selectBranch,
        analysisArrows: _buildAnalysisArrows(controller),
        lastMove: _lastMoveOf(controller),
        hintArrow: controller.hintMark,
        flipped: controller.boardFlipped,
        moveAnim: controller.moveAnim,
      ),
    );
  }

  /// 横屏模式下左侧棋盘区的宽度：按可用高度反推棋盘最大宽度，使
  /// 棋盘尽量占满高度；同时不超过总宽度的一半。
  ///
  /// 棋盘画布高 = (宽 - 2×边距) × (行数-1+棋子比例) / (列数-1+棋子比例)
  /// + 2×边距（[BoardLayout.sizeForWidth] 的反推）。
  double _landscapeBoardWidth(BoxConstraints constraints) {
    const cols = BoardConstants.columnCount - 1 + BoardLayout.pieceRatio;
    const rows = BoardConstants.rowCount - 1 + BoardLayout.pieceRatio;
    // 扣除棋盘区上下各 4px 边距与 2px 余量
    final availH = constraints.maxHeight - 10;
    var w = (availH - BoardLayout.outerMargin * 2) * cols / rows +
        BoardLayout.outerMargin * 2;
    final maxW = constraints.maxWidth * 0.5;
    return w > maxW ? maxW : w;
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
          id: '选谱',
          icon: Icons.grid_view,
          label: '选谱',
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

  /// 打开选谱弹窗，选择后跳转到对应局。
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
        '返回', '重开', '红AI', '黑AI', '分析', '出招', '反转',
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
          closesDrawer: true,
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
          // FloatingToast.show(
          //   context,
          //   '对局结束：${controller.result}',
          //   icon: Icons.flag_outlined,
          // );
        });
      }
    }
    return const SizedBox.shrink();
  }
}

// ---------------------------------------------------------------------------
// 对弈模式：对手头像框 + 控制区（悔棋 / 执子方选择 / 退出）
// ---------------------------------------------------------------------------

/// 对弈模式顶部：电脑对手头像框。
///
/// 显示对手名称与首字头像，点击打开对手选择窗口。
/// AI 思考中时头像旁显示加载指示器。
class _PlayOpponentBar extends StatelessWidget {
  const _PlayOpponentBar({required this.controller});

  final GameController controller;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final name = controller.playOpponent;
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          color: const Color(0xFFEFE0B8),
          child: Row(
            children: [
              // 对手头像：点击打开对手选择窗口
              GestureDetector(
                onTap: () async {
                  final chosen = await OpponentDialog.show(
                    context,
                    current: name,
                  );
                  if (chosen != null) controller.setPlayOpponent(chosen);
                },
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: 20,
                      backgroundColor: AppTheme.boardLine,
                      child: Text(
                        name.isNotEmpty ? name.substring(0, 1) : '?',
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Text(
                      name,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.boardLine,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              // AI 思考中指示器
              if (controller.aiThinking)
                const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              const Spacer(),
              // 退出对弈按钮
              IconButton(
                icon: const Icon(Icons.exit_to_app, color: Color(0xFF8B6B3D)),
                tooltip: '退出对弈',
                onPressed: () => controller.exitPlayMode(),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// 对弈模式底部控制区：悔棋按钮 + 执子方选择（或对局中提示）。
class _PlayControls extends StatelessWidget {
  const _PlayControls({required this.controller});

  final GameController controller;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final started = controller.playStarted;
        final userSide = controller.playUserSide;
        // 悔棋仅在用户行棋且有棋可悔时可用
        final canUndo = started &&
            !controller.isOver &&
            !controller.aiThinking &&
            userSide == controller.currentSide &&
            controller.canGoBack;
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: const BoxDecoration(
            color: Color(0xFFEFE0B8),
            border: Border(
              top: BorderSide(color: Color(0xFFC9B68C), width: 0.8),
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // 悔棋按钮：仅在用户行棋时可用
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: canUndo ? controller.playUndo : null,
                  icon: const Icon(Icons.undo),
                  label: const Text('悔棋'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppTheme.boardLine,
                    side: const BorderSide(color: AppTheme.boardLine),
                    padding: const EdgeInsets.symmetric(vertical: 10),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              // 执子方选择：未开始时显示「执红」「执黑」按钮；
              // 已开始时显示当前执子方与行棋提示
              if (!started)
                Row(
                  children: [
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: () => controller.startPlay(Side.red),
                        icon: const Icon(Icons.circle, color: Colors.white),
                        label: const Text('执红先行'),
                        style: FilledButton.styleFrom(
                          backgroundColor: AppTheme.redPiece,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: () => controller.startPlay(Side.black),
                        icon: const Icon(Icons.circle, color: Colors.white),
                        label: const Text('执黑后行'),
                        style: FilledButton.styleFrom(
                          backgroundColor: AppTheme.blackPiece,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                        ),
                      ),
                    ),
                  ],
                )
              else
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      userSide == Side.red ? Icons.circle : Icons.circle,
                      color: userSide == Side.red
                          ? AppTheme.redPiece
                          : AppTheme.blackPiece,
                      size: 14,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      controller.isOver
                          ? '对局结束：${controller.result}'
                          : '您执${userSide == Side.red ? '红' : '黑'}  ·  '
                              '${controller.currentSide == userSide ? '轮到您行棋' : '电脑思考中…'}',
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.boardLine,
                      ),
                    ),
                  ],
                ),
            ],
          ),
        );
      },
    );
  }
}

/// 可整体缩放的棋盘容器。
///
/// 棋盘宽度 = 可用宽度 × 配置缩放比例（[BoardConfig.boardScale]，默认 1.0
/// 占满）。缩放把手是一个黄色五角星，通过 [OverlayEntry] 浮动显示——
/// 不参与页面布局，绘制在所有组件之上；位置跟随棋盘下边缘横向 2/3 处，
/// 上下拖动可整体缩放棋盘：向下放大、向上缩小；拖动结束后写入配置持久化。
class _ScalableBoard extends StatefulWidget {
  const _ScalableBoard({
    required this.child,
    required this.boardAreaKey,
    this.showHandle = true,
    this.onSwipeUp,
    this.onSwipeDown,
  });

  /// 棋盘组件（[BoardWidget]），按缩放后的宽度约束显示。
  final Widget child;

  /// 棋盘区域定位键：由外部创建并传入，黄星把手据此定位，
  /// 打谱页浮动红星也用它计算默认位置（棋盘下边缘 1/3 处）。
  final GlobalKey boardAreaKey;

  /// 是否显示五角星缩放把手（残局模式不显示，但仍按配置缩放）。
  final bool showHandle;

  /// 向上滑动回调（棋谱前进一步）。
  final VoidCallback? onSwipeUp;

  /// 向下滑动回调（棋谱后退一步）。
  final VoidCallback? onSwipeDown;

  @override
  State<_ScalableBoard> createState() => _ScalableBoardState();
}

class _ScalableBoardState extends State<_ScalableBoard> {
  /// 把手尺寸（像素）。
  static const double _handleSize = 28;

  /// 拖动灵敏度：拖动 300 像素对应缩放 1.0。
  static const double _dragPixelsPerScale = 300;

  /// 棋盘区域定位键（由 [widget] 传入）：浮层把手据此计算屏幕坐标。
  GlobalKey get _boardAreaKey => widget.boardAreaKey;

  /// 浮动五角星的 Overlay 入口。
  OverlayEntry? _handleEntry;

  /// 拖动过程中的临时缩放值；非拖动状态为 null（跟随配置）。
  double? _draggingScale;

  /// 滑动检测：累积的竖直拖动距离（像素）。
  double _swipeDy = 0;

  /// 竖直滑动判定阈值：至少滑动 40 像素才触发。
  static const double _swipeThreshold = 40;

  double get _scale =>
      _draggingScale ?? ConfigManager.instance.config.board.boardScale;

  @override
  void initState() {
    super.initState();
    // 首帧布局完成后再插入浮层，确保棋盘 RenderBox 可用
    WidgetsBinding.instance.addPostFrameCallback((_) => _syncHandle());
  }

  @override
  void didUpdateWidget(covariant _ScalableBoard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.showHandle != widget.showHandle) _syncHandle();
  }

  @override
  void dispose() {
    _handleEntry?.remove();
    _handleEntry = null;
    super.dispose();
  }

  /// 把手是否应显示：父组件开关 + 界面设置「缩放星」开关共同决定。
  bool get _handleVisible =>
      widget.showHandle && ConfigManager.instance.config.ui.showScaleStar;

  /// 按把手可见性插入或移除浮层。
  void _syncHandle() {
    if (!mounted) return;
    if (_handleVisible && _handleEntry == null) {
      _handleEntry = OverlayEntry(builder: _buildHandle);
      Overlay.of(context).insert(_handleEntry!);
    } else if (!_handleVisible && _handleEntry != null) {
      _handleEntry!.remove();
      _handleEntry = null;
    }
  }

  /// 刷新浮层把手位置（拖动/配置变化/棋盘重排后调用）。
  void _refreshHandle() {
    final entry = _handleEntry;
    if (entry == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) entry.markNeedsBuild();
    });
  }

  /// 构建浮动五角星：定位在棋盘下边缘横向 2/3 处，中心压在边缘线上。
  ///
  /// 把手默认禁用（灰色）：点击与拖动均无效，仅长按可切换为启用（黄色）。
  /// 启用后：点击在最大/最小缩放之间切换；上下拖动连续调整缩放。
  Widget _buildHandle(BuildContext context) {
    // 树重组期间 element 可能 inactive：currentContext 非空、mounted
    // 也为 true，但 findRenderObject 仍抛异常，只能 try-catch 兜底
    RenderBox? box;
    try {
      final areaCtx = _boardAreaKey.currentContext;
      if (areaCtx == null || !areaCtx.mounted) return const SizedBox.shrink();
      box = areaCtx.findRenderObject() as RenderBox?;
    } catch (_) {
      return const SizedBox.shrink();
    }
    if (box == null || !box.attached) return const SizedBox.shrink();
    final origin = box.localToGlobal(Offset.zero);
    final boardWidth = box.size.width;
    final boardHeight = box.size.height;
    final boardCfg = ConfigManager.instance.config.board;
    final enabled = boardCfg.boardHandleEnabled;
    // 禁用灰 / 启用黄
    final starColor =
        enabled ? const Color(0xFFFFD54F) : const Color(0xFF9E9E9E);
    return Positioned(
      left: origin.dx + boardWidth * 2 / 3 - _handleSize / 2,
      top: origin.dy + boardHeight - _handleSize / 2,
      width: _handleSize,
      height: _handleSize,
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        // 长按切换启用状态（禁用态下唯一可用的手势）
        onLongPress: () {
          ConfigManager.instance.updateBoard((b) {
            b.boardHandleEnabled = !b.boardHandleEnabled;
            return b;
          });
        },
        // 启用后点击：在最大与最小缩放之间切换
        onTap: enabled
            ? () {
                final cur = _scale;
                final mid = (BoardConfig.kMinBoardScale +
                        BoardConfig.kMaxBoardScale) /
                    2;
                _applyScale(cur >= mid
                    ? BoardConfig.kMinBoardScale
                    : BoardConfig.kMaxBoardScale);
              }
            : null,
        // 启用后上下拖动：连续调整缩放（下拖放大、上拖缩小）
        onVerticalDragUpdate: enabled
            ? (d) {
                final next = _scale + d.delta.dy / _dragPixelsPerScale;
                setState(() {
                  _draggingScale = next.clamp(
                      BoardConfig.kMinBoardScale, BoardConfig.kMaxBoardScale);
                });
                // 棋盘尺寸变化后跟随移动把手
                _refreshHandle();
              }
            : null,
        onVerticalDragEnd: enabled
            ? (_) {
                final v = _draggingScale;
                _draggingScale = null;
                if (v != null) _applyScale(v);
              }
            : null,
        child: Stack(
          alignment: Alignment.center,
          children: [
            // 深色描边底层，保证五角星在浅色棋盘上可见
            const Icon(Icons.star,
                size: _handleSize + 4, color: Color(0xFF7A5C1E)),
            Icon(Icons.star, size: _handleSize, color: starColor),
          ],
        ),
      ),
    );
  }

  /// 应用缩放值并写入配置持久化（点击切换与拖动结束共用）。
  void _applyScale(double v) {
    if (v == ConfigManager.instance.config.board.boardScale) return;
    ConfigManager.instance.updateBoard((b) {
      b.boardScale = v;
      return b;
    });
  }

  @override
  Widget build(BuildContext context) {
    // 监听配置：设置页重置配置或拖动结束写盘后同步最新缩放
    return ListenableBuilder(
      listenable: ConfigManager.instance,
      builder: (context, _) {
        final scale = _scale;
        // 「缩放星」显隐开关可能在设置页被切换，下一帧重新同步把手
        WidgetsBinding.instance.addPostFrameCallback((_) => _syncHandle());
        return LayoutBuilder(
          builder: (context, constraints) {
            final boardWidth = constraints.maxWidth * scale;
            final boardHeight = BoardLayout.sizeForWidth(boardWidth).height;
            // 布局/尺寸可能变化，下一帧刷新浮层把手位置
            _refreshHandle();
            return Align(
              alignment: Alignment.topCenter,
              child: SizedBox(
                key: _boardAreaKey,
                width: boardWidth,
                height: boardHeight,
                // 滑动检测：上滑前进一步，下滑后退一步；
                // 仅当外部提供了回调时才启用（打谱页启用，残局/对弈不启用）。
                child: (widget.onSwipeUp != null || widget.onSwipeDown != null)
                    ? GestureDetector(
                        behavior: HitTestBehavior.translucent,
                        onVerticalDragStart: (_) => _swipeDy = 0,
                        onVerticalDragUpdate: (d) => _swipeDy += d.delta.dy,
                        onVerticalDragEnd: (_) {
                          if (_swipeDy <= -_swipeThreshold &&
                              widget.onSwipeUp != null) {
                            widget.onSwipeUp!();
                          } else if (_swipeDy >= _swipeThreshold &&
                              widget.onSwipeDown != null) {
                            widget.onSwipeDown!();
                          }
                          _swipeDy = 0;
                        },
                        onVerticalDragCancel: () => _swipeDy = 0,
                        child: widget.child,
                      )
                    : widget.child,
              ),
            );
          },
        );
      },
    );
  }
}
