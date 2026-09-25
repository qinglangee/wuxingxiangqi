import 'package:flutter/foundation.dart';

/// 局面变化专用通知器。
///
/// 与 [GameController] 自身的高频 notify（选中棋子、引擎 info 流、
/// AI 思考标志等）分离：仅在「初始化局面」和「走棋方改变」（走子
/// 完成、跳转棋谱节点）时由 GameController 主动触发，供云库等只对
/// 真实局面变化敏感的模块订阅。
class BoardChangeNotifier extends ChangeNotifier {
  /// 发送一次局面变化通知。
  void emit() => notifyListeners();
}
