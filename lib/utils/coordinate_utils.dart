import 'package:flutter/material.dart';
import '../core/constants/board_constants.dart';

/// 棋盘逻辑坐标(col, row) 与屏幕像素坐标之间的换算。
///
/// [flipped] 为 true 时棋盘红黑方向上下互换（180° 视角）：
/// 逻辑列/行映射到对角镜像位置。
class CoordinateUtils {
  CoordinateUtils._();

  /// 逻辑坐标 → 显示坐标（翻转时做 180° 镜像）。
  static (int col, int row) _display(
    int col,
    int row,
    bool flipped,
  ) {
    if (!flipped) return (col, row);
    return (
      BoardConstants.columnCount - 1 - col,
      BoardConstants.rowCount - 1 - row,
    );
  }

  /// 将棋盘逻辑坐标换算为棋盘画布内中心点像素坐标。
  static Offset toPixel({
    required int col,
    required int row,
    required double cellWidth,
    required double cellHeight,
    required EdgeInsets padding,
    bool flipped = false,
  }) {
    final (dc, dr) = _display(col, row, flipped);
    return Offset(
      padding.left + dc * cellWidth,
      padding.top + dr * cellHeight,
    );
  }

  /// 将屏幕像素坐标反推为最近的棋盘逻辑坐标；越界返回 null。
  static (int col, int row)? fromPixel({
    required double x,
    required double y,
    required double cellWidth,
    required double cellHeight,
    required EdgeInsets padding,
    bool flipped = false,
  }) {
    var col = ((x - padding.left) / cellWidth).round();
    var row = ((y - padding.top) / cellHeight).round();
    if (col < 0 || col >= BoardConstants.columnCount) return null;
    if (row < 0 || row >= BoardConstants.rowCount) return null;
    if (flipped) {
      col = BoardConstants.columnCount - 1 - col;
      row = BoardConstants.rowCount - 1 - row;
    }
    return (col, row);
  }
}
