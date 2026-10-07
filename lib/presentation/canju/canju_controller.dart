import 'package:flutter/foundation.dart';

import '../../core/canju/canju_library.dart';
import '../../core/canju/canju_progress.dart';
import '../../core/config/config_manager.dart';
import '../../domain/game/game_result.dart';
import '../../domain/models/piece.dart';
import '../../domain/notation/notation_node.dart';
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
    // 标记为残局模式：退出打谱页时不保存会话
    gameController.isCanjuMode = true;
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
    // 从残局功能条的按钮配置恢复 check button 的上次状态
    // （与 AdjustableButtonBar 的持久化同源，配置不存在时用默认值）
    final checks =
        ConfigManager.instance.buttonBarConfig('canju_bar')?.checked;
    _autoHint = checks?['提示自动'] ?? false;
    _autoNext = checks?['自动下一局'] ?? false;
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

  /// 自动下一局开关：开启时本局结束后（红胜/黑胜/和棋）自动跳下一局。
  bool _autoNext = false;
  bool get autoNext => _autoNext;

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

  /// 当前库是否为收藏库（决定收藏按钮显示为收藏还是取消收藏）。
  bool get isFavoritesLibrary => library.name == CanjuFavorites.libraryName;

  /// 收藏当前残局：把当前局的初始 FEN 追加到收藏文件。
  /// 返回是否发生了变更（已在收藏中时为 false）。
  Future<bool> favoriteCurrent() async {
    if (isFavoritesLibrary) return false;
    return CanjuFavorites.add(currentFen);
  }

  /// 取消收藏当前局：从收藏文件中删除当前局的初始 FEN，
  /// 并重新载入收藏库（当前索引越界时收紧到末局）。
  ///
  /// 收藏库被清空时自动切换到第一个可用的其它库；没有任何可用库时
  /// 保持现状（盘面不动）。当前不在收藏库中时无操作。
  Future<void> unfavoriteCurrent() async {
    if (!isFavoritesLibrary) return;
    await CanjuFavorites.remove(library[_currentIndex]);
    CanjuLibrary lib;
    try {
      lib = await CanjuLibraryLoader.load(CanjuFavorites.libraryName);
    } catch (_) {
      lib = const CanjuLibrary(
          name: CanjuFavorites.libraryName, fens: []);
    }
    if (lib.isEmpty) {
      // 收藏已清空：自动切到第一个可用的其它库
      final all = await CanjuLibraryLoader.loadAll();
      final fallback = all.firstWhere(
        (l) => l.name != CanjuFavorites.libraryName && l.isNotEmpty,
        orElse: () => lib,
      );
      if (fallback.isNotEmpty) {
        await switchLibrary(fallback);
        return;
      }
      // 没有其它库可用：保持现状
      notifyListeners();
      return;
    }
    library = lib;
    _currentIndex = _currentIndex.clamp(0, lib.length - 1);
    _alreadyClearedForCurrent = false;
    _loadCurrent();
    notifyListeners();
    await store.setCurrentIndex(library.name, _currentIndex);
  }

  /// 切换「提示自动」开关。
  void setAutoHint(bool v) {
    _autoHint = v;
    notifyListeners();
  }

  /// 切换「自动下一局」开关。
  void setAutoNext(bool v) {
    _autoNext = v;
    notifyListeners();
  }

  /// 重开当前局：回到该局的初始 FEN 局面。
  void restartCurrent() {
    _alreadyClearedForCurrent = false;
    _loadCurrent();
  }

  /// 悔棋：回退到最近的应该红方行棋的节点。
  ///
  /// 残局模式下人类执红、AI 执黑，悔棋即撤销「黑方最后一步及其之前
  /// 的红方一步」，回到上一个轮到红方行棋的局面，让人可以换一种走法。
  /// 从当前节点的父节点开始向上查找（而非当前节点本身），否则当当前
  /// 局面正是黑方应着后到达的（红方行棋）时会原地不动、毫无反应。
  void undoToRedTurn() {
    NotationNode? node = gameController.currentNode.parent;
    while (node != null && !node.isRoot) {
      final move = node.move;
      if (move != null && move.moving.side == Side.black) break;
      var temp = node;
      node = node.parent;
      gameController.deleteMove(temp);
    }
    // node 为 null 仅当当前节点是根（无棋可悔）
    if (node != null) gameController.jumpTo(node);
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
  /// 空库（如清空后的收藏库）不切换。
  Future<void> switchLibrary(CanjuLibrary lib) async {
    if (lib.name == library.name) return;
    if (lib.isEmpty) return;
    library = lib;
    final rec = store.recordOf(lib.name);
    _currentIndex = rec.currentIndex.clamp(0, lib.length - 1);
    _alreadyClearedForCurrent = false;
    _loadCurrent();
    notifyListeners();
    await store.setLastLibrary(lib.name);
  }

  /// [GameController] 状态变化时检测：若当前局面"红方胜"，标记本局过关；
  /// 开启「自动下一局」时，本局结束（红胜/黑胜/和棋）后延时跳下一局。
  void _onGameControllerChanged() {
    final tick = gameController.resultTick;
    if (tick == _lastSeenResultTick) return;
    _lastSeenResultTick = tick;
    final result = gameController.result;
    if (!_alreadyClearedForCurrent &&
        result.status == GameResultStatus.redWins) {
      _alreadyClearedForCurrent = true;
      // 异步持久化，不阻塞 UI
      store.markCleared(library.name, _currentIndex).then((_) {
        notifyListeners();
      });
    }

    // 不是红胜的，不自动跳下一局
    if(result.status != GameResultStatus.redWins) return;

    // 终局自动跳下一局（延时给结果展示与音效留一点时间）
    if (_autoNext &&
        result.status != GameResultStatus.ongoing &&
        canNext &&
        !_autoNextScheduled) {
      _autoNextScheduled = true;
      Future.delayed(const Duration(milliseconds: 900), () {
        _autoNextScheduled = false;
        if (_disposed) return;
        final stillEnded =
            gameController.result.status != GameResultStatus.ongoing;
        if (stillEnded) goNext();
      });
    }
  }

  /// 是否已排定一次自动跳下一局（防止重复排程）。
  bool _autoNextScheduled = false;

  /// 本控制器是否已销毁（延时回调中防止误用）。
  bool _disposed = false;

  void _loadCurrent() {
    gameController.loadFen(library[_currentIndex]);
  }

  @override
  void dispose() {
    _disposed = true;
    gameController.removeListener(_onGameControllerChanged);
    super.dispose();
  }
}
