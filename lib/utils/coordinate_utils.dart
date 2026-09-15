import 'package:flutter/material.dart';
import '../core/constants/board_constants.dart';

/// 棋盘逻辑坐标(col, row) 与屏幕像素坐标之间的换算。
class CoordinateUtils {
  CoordinateUtils._();

  /// 将棋盘逻辑坐标换算为棋盘画布内中心点像素坐标。
  static Offset toPixel({
    required int col,
    required int row,
    required double cellWidth,
    required double cellHeight,
    required EdgeInsets padding,
  }) {
    return Offset(
      padding.left + col * cellWidth,
      padding.top + row * cellHeight,
    );
  }

  /// 将屏幕像素坐标反推为最近的棋盘逻辑坐标；越界返回 null。
  static (int col, int row)? fromPixel({
    required double x,
    required double y,
    required double cellWidth,
    required double cellHeight,
    required EdgeInsets padding,
  }) {
    final col = ((x - padding.left) / cellWidth).round();
    final row = ((y - padding.top) / cellHeight).round();
    if (col < 0 || col >= BoardConstants.columnCount) return null;
    if (row < 0 || row >= BoardConstants.rowCount) return null;
    return (col, row);
  }
}
