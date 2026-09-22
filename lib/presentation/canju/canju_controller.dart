import 'package:flutter/foundation.dart';

import '../../core/canju/canju_library.dart';
import '../../core/canju/canju_progress.dart';
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
/// 新起始局面，并通过 [CanjuStore] 持久化当前局索引。
class CanjuController extends ChangeNotifier {
  CanjuController({
    required this.gameController,
    required this.library,
    required this.store,
    required int initialIndex,
  })  : _currentIndex = initialIndex {
    _loadCurrent();
  }

  final GameController gameController;
  final CanjuLibrary library;
  final CanjuStore store;
  int _currentIndex;
  int get currentIndex => _currentIndex;
  int get total => library.length;
  bool get canPrev => _currentIndex > 0;
  bool get canNext => _currentIndex < library.length - 1;

  /// 当前局 FEN（方便 UI 显示或外部读取）。
  String get currentFen => library[_currentIndex];

  /// 切换到上一局。已到首局时无操作。
  Future<void> goPrev() async {
    if (!canPrev) return;
    _currentIndex--;
    _loadCurrent();
    notifyListeners();
    await store.setCurrentIndex(library.name, _currentIndex);
  }

  /// 切换到下一局。已到末局时无操作。
  Future<void> goNext() async {
    if (!canNext) return;
    _currentIndex++;
    _loadCurrent();
    notifyListeners();
    await store.setCurrentIndex(library.name, _currentIndex);
  }

  /// 跳转到指定局索引。越界或与当前相同时无操作。
  Future<void> gotoIndex(int i) async {
    if (i < 0 || i >= library.length || i == _currentIndex) return;
    _currentIndex = i;
    _loadCurrent();
    notifyListeners();
    await store.setCurrentIndex(library.name, _currentIndex);
  }

  /// 标记当前局第 [level] 关已过关（0..3）。
  Future<void> markCleared(int level) async {
    await store.markCleared(library.name, _currentIndex, level);
    notifyListeners();
  }

  void _loadCurrent() {
    gameController.loadFen(library[_currentIndex]);
  }
}
