import '../models/board.dart';
import '../models/piece.dart';
import '../models/position.dart';

/// 象棋中文记谱生成器。
///
/// 规则要点：
/// - 红方用汉字数字（一二…九），列号从红方右手边起：棋盘 col 8 = 一。
/// - 黑方用阿拉伯数字（1…9），列号从黑方右手边起：棋盘 col 0 = 1。
/// - 直线子（帅将/车/炮/兵卒）：平走报目标列号，进退报步数。
/// - 斜走子（马/士/象）：进退报目标列号。
/// - 同列有两个以上同类棋子时，用「前/后（/中）」+ 棋子名消歧。
class NotationText {
  NotationText._();

  static const List<String> _redNums = [
    '一', '二', '三', '四', '五', '六', '七', '八', '九',
  ];

  static const Map<PieceType, String> _redNames = {
    PieceType.general: '帅',
    PieceType.advisor: '仕',
    PieceType.elephant: '相',
    PieceType.horse: '马',
    PieceType.chariot: '车',
    PieceType.cannon: '炮',
    PieceType.soldier: '兵',
  };

  static const Map<PieceType, String> _blackNames = {
    PieceType.general: '将',
    PieceType.advisor: '士',
    PieceType.elephant: '象',
    PieceType.horse: '马',
    PieceType.chariot: '车',
    PieceType.cannon: '炮',
    PieceType.soldier: '卒',
  };

  /// 根据走子前的盘面生成中文记谱。
  static String describe(Board before, Position from, Position to) {
    final piece = before.pieceAt(from);
    if (piece == null) {
      throw ArgumentError('起点无棋子: $from');
    }
    final side = piece.side;
    final type = piece.type;
    final name = side == Side.red ? _redNames[type]! : _blackNames[type]!;

    final dRow = to.row - from.row;
    final forward = side == Side.red ? dRow < 0 : dRow > 0;

    // 同列同类棋子（前→后排序：红方 row 小在前，黑方 row 大在前）
    final sameFile = <Position>[];
    for (final (:position, :piece) in before.pieces(of: side)) {
      if (piece.type == type && position.col == from.col) {
        sameFile.add(position);
      }
    }
    sameFile.sort((a, b) =>
        side == Side.red ? a.row.compareTo(b.row) : b.row.compareTo(a.row));

    final String head;
    if (sameFile.length > 1) {
      // 前车平六 / 后马进三 形式：省略起点列号
      final idx = sameFile.indexWhere((p) => p == from);
      head = '${_ordinals(sameFile.length)[idx]}$name';
    } else {
      head = '$name${_fileLabel(side, from.col)}';
    }

    final String tail;
    if (dRow == 0) {
      // 平移
      tail = '平${_fileLabel(side, to.col)}';
    } else {
      final verb = forward ? '进' : '退';
      if (_isDiagonal(piece.type)) {
        // 斜走子进退报目标列号
        tail = '$verb${_fileLabel(side, to.col)}';
      } else {
        // 直线子进退报步数
        tail = '$verb${_numberLabel(side, dRow.abs())}';
      }
    }

    return '$head$tail';
  }

  static bool _isDiagonal(PieceType type) =>
      type == PieceType.horse ||
      type == PieceType.advisor ||
      type == PieceType.elephant;

  /// 列号标签：红 col 8→一 … col 0→九；黑 col 0→1 … col 8→9。
  static String _fileLabel(Side side, int col) {
    if (side == Side.red) return _redNums[8 - col];
    return '${col + 1}';
  }

  /// 数量标签：红用汉字，黑用阿拉伯数字。
  static String _numberLabel(Side side, int n) {
    if (side == Side.red) return _redNums[n - 1];
    return '$n';
  }

  /// 同列多子的前后称谓（双方都用汉字）。
  static List<String> _ordinals(int n) {
    switch (n) {
      case 2:
        return const ['前', '后'];
      case 3:
        return const ['前', '中', '后'];
      case 4:
        return const ['前', '二', '三', '后'];
      default:
        return const ['前', '二', '中', '四', '后'];
    }
  }
}
