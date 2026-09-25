import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../domain/engine/chessdb_service.dart';
import '../../../domain/engine/fen.dart';
import '../../../domain/models/piece.dart';
import '../../../domain/models/position.dart';
import '../../controllers/game_controller.dart';

/// 云库面板一条着法的展示模型。
class CloudMoveEntry {
  const CloudMoveEntry({
    required this.uci,
    required this.text,
    required this.score,
    required this.winRate,
    required this.from,
    required this.to,
  });

  final String uci;

  /// 中文记谱（如「炮二平五」）。
  final String text;

  /// 云库评分（走子方视角，越大越优）。
  final int score;

  /// 胜率百分比（0..100）。
  final double winRate;

  final Position from;
  final Position to;
}

/// 云库面板控制器。
///
/// 监听 [GameController] 的 notify，局面 FEN 变化时防抖后请求 ChessDB
/// `queryall`，结果按评分降序展示。点击条目即在棋盘上走子（若该着法合法）。
class CloudBaseController extends ChangeNotifier {
  CloudBaseController({required this.gameController}) {
    gameController.addListener(_onGameChanged);
    _refresh();
  }

  final GameController gameController;

  /// 最近请求的 FEN 与结果（null 表示未请求或请求失败）。
  String? _fen;
  List<CloudMoveEntry>? _moves;
  bool _loading = false;
  String? _error;
  Timer? _debounce;

  List<CloudMoveEntry>? get moves => _moves;
  bool get loading => _loading;
  String? get error => _error;

  /// 局面变化回调：防抖后请求云库。
  void _onGameChanged() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), _refresh);
  }

  /// 当前是否轮到 AI 走子（此时不查询云库）。
  bool get _isAiTurn {
    final gc = gameController;
    return gc.currentSide == Side.red ? gc.redIsAi : gc.blackIsAi;
  }

  Future<void> _refresh() async {
    // 轮到电脑 AI 时无需查询云库，避免无意义请求
    if (_isAiTurn) {
      _moves = null;
      _error = null;
      _loading = false;
      notifyListeners();
      return;
    }

    final fen = Fen.fromBoard(gameController.state.board, gameController.currentSide);
    if (fen == _fen && _moves != null) return; // 局面未变，不重复请求
    _fen = fen;
    _loading = true;
    _error = null;
    notifyListeners();

    final result = await ChessDbService.query(fen);
    _loading = false;
    if (result == null) {
      _error = '云库请求失败（网络或服务不可用）';
      _moves = null;
    } else if (result.isTerminal) {
      _moves = const [];
      _error = result.message;
    } else {
      final described = describeCloudMoves(fen, result.moves);
      // 云库返回的着法与中文记谱一一对应，但需按评分排序
      _moves = [
        for (var i = 0; i < result.moves.length && i < described.length; i++)
          CloudMoveEntry(
            uci: result.moves[i].uci,
            text: described[i].text,
            score: result.moves[i].score,
            winRate: result.moves[i].winRate,
            from: described[i].from,
            to: described[i].to,
          ),
      ];
      _error = null;
    }
    notifyListeners();
  }

  /// 点击一条云库着法，尝试在棋盘上走子。
  /// 返回 true 表示走子成功。
  bool applyMove(CloudMoveEntry entry) {
    if (gameController.isOver) return false;
    // 复用 GameController 的走子逻辑（含棋谱树记录与 AI 后续）
    final ok = gameController.applyMove(entry.from, entry.to);
    if (ok) {
      // 走子后局面已变，防抖刷新
      _onGameChanged();
    }
    return ok;
  }

  @override
  void dispose() {
    _debounce?.cancel();
    gameController.removeListener(_onGameChanged);
    super.dispose();
  }
}
