import 'package:flutter/foundation.dart';

import '../../core/canju/canju_library.dart';
import '../../core/canju/canju_progress.dart';
import '../../domain/game/game_result.dart';
import '../../domain/models/piece.dart';
import '../controllers/game_controller.dart';

/// 残局会话快照：作为路由参数传入 `/play`。
///
/// 不可变；包含 [library]、起始局索引与持久化用的 [store]。
class CanjuSession {
  const CanjuSession({
    required this.library,
    required this.initialIndex,
    required this.store,
  });

  final CanjuLibrary library;
  final int initialIndex;
  final CanjuStore store;
}

/// 残局模式状态控制器：在打谱页面被注入，提供上一局 / 下一局 / 跳转。
///
/// 内部持有 [GameController]，切换局时调用 [GameController.loadFen] 载入
/// 新起始局面，并通过 [CanjuStore] 持久化当前局索引。同时监听
/// [GameController] 的终局状态：当当前局面"红方胜"时自动标记本局过关。
class CanjuController extends ChangeNotifier {
  CanjuController({
    required this.gameController,
    required this.library,
    required this.store,
    required int initialIndex,
  })  : _currentIndex = initialIndex,
        _lastSeenResultTick = gameController.resultTick {
    // 本控制器在 MultiProvider 的 build 阶段被创建，此处若让
    // GameController.notifyListeners 会触发"build 期标记重建"异常，
    // 因此首次载入走静默路径：状态同步改好，首帧 build 直接读到残局
    // 局面即可，无需通知。
    gameController.loadFen(library[initialIndex], notify: false);
    // 残局模式：默认人类执红、AI 执黑。构造期间处于 Provider build 阶段，
    // 必须静默设置（notify: false），首帧 build 直接读到标志位即可。
    gameController.setRedAi(false, notify: false);
    gameController.setBlackAi(true, notify: false);
    gameController.addListener(_onGameControllerChanged);
  }

  final GameController gameController;

  /// 当前残局库（「题库」按钮换库后更新）。
  CanjuLibrary library;

  final CanjuStore store;
  int _currentIndex;
  int _lastSeenResultTick;
  bool _alreadyClearedForCurrent = false;

  /// 提示自动开关：开启时点击「提示」按钮直接让引擎走子，否则仅标记。
  bool _autoHint = false;
  bool get autoHint => _autoHint;

  /// 分析模式：残局页面点击「分析」后切换为分析状态显示
  /// （显示 _AiConfigRow 与 ReviewPanel，隐藏 AppBar 与 _CanjuBar）。
  bool _analysisMode = false;
  bool get analysisMode => _analysisMode;

  /// 进入分析模式。
  void enterAnalysisMode() {
    if (_analysisMode) return;
    _analysisMode = true;
    notifyListeners();
  }

  /// 退出分析模式，回到残局状态。
  void exitAnalysisMode() {
    if (!_analysisMode) return;
    _analysisMode = false;
    notifyListeners();
  }

  int get currentIndex => _currentIndex;
  int get total => library.length;
  bool get canPrev => _currentIndex > 0;
  bool get canNext => _currentIndex < library.length - 1;

  /// 当前局 FEN（方便 UI 显示或外部读取）。
  String get currentFen => library[_currentIndex];

  /// 切换「提示自动」开关。
  void setAutoHint(bool v) {
    _autoHint = v;
    notifyListeners();
  }

  /// 重开当前局：回到该局的初始 FEN 局面。
  void restartCurrent() {
    _alreadyClearedForCurrent = false;
    _loadCurrent();
  }

  /// 悔棋：回退到最近的应该红方行棋的节点（即撤销黑方最后一步）。
  ///
  /// 残局模式下人类执红、AI 执黑，因此悔棋就是回到黑走之前。
  void undoToRedTurn() {
    // 沿父链向上找，直到节点为根或该节点记录的走子是黑方走的
    var node = gameController.currentNode;
    while (!node.isRoot) {
      final move = node.move;
      if (move != null && move.moving.side == Side.black) break;
      node = node.parent!;
    }
    gameController.jumpTo(node);
  }

  /// 提示：把当前局面发给引擎，按 [autoHint] 决定直接走子还是标记。
  Future<void> requestHint() => gameController.requestHint(autoMove: _autoHint);

  /// 切换到上一局。已到首局时无操作。
  Future<void> goPrev() async {
    if (!canPrev) return;
    _currentIndex--;
    _alreadyClearedForCurrent = false;
    _loadCurrent();
    notifyListeners();
    await store.setCurrentIndex(library.name, _currentIndex);
  }

  /// 切换到下一局。已到末局时无操作。
  Future<void> goNext() async {
    if (!canNext) return;
    _currentIndex++;
    _alreadyClearedForCurrent = false;
    _loadCurrent();
    notifyListeners();
    await store.setCurrentIndex(library.name, _currentIndex);
  }

  /// 跳转到指定局索引。越界或与当前相同时无操作。
  Future<void> gotoIndex(int i) async {
    if (i < 0 || i >= library.length || i == _currentIndex) return;
    _currentIndex = i;
    _alreadyClearedForCurrent = false;
    _loadCurrent();
    notifyListeners();
    await store.setCurrentIndex(library.name, _currentIndex);
  }

  /// 切换残局库：载入该库记录的上次局索引，并持久化「上次打开的库」。
  Future<void> switchLibrary(CanjuLibrary lib) async {
    if (lib.name == library.name) return;
    library = lib;
    final rec = store.recordOf(lib.name);
    _currentIndex = rec.currentIndex.clamp(0, lib.length - 1);
    _alreadyClearedForCurrent = false;
    _loadCurrent();
    notifyListeners();
    await store.setLastLibrary(lib.name);
  }

  /// [GameController] 状态变化时检测：若当前局面"红方胜"，标记本局过关。
  void _onGameControllerChanged() {
    final tick = gameController.resultTick;
    if (tick == _lastSeenResultTick) return;
    _lastSeenResultTick = tick;
    if (_alreadyClearedForCurrent) return;
    final result = gameController.result;
    if (result.status == GameResultStatus.redWins) {
      _alreadyClearedForCurrent = true;
      // 异步持久化，不阻塞 UI
      store.markCleared(library.name, _currentIndex).then((_) {
        notifyListeners();
      });
    }
  }

  void _loadCurrent() {
    gameController.loadFen(library[_currentIndex]);
  }

  @override
  void dispose() {
    gameController.removeListener(_onGameControllerChanged);
    super.dispose();
  }
}
