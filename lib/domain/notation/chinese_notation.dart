import '../models/board.dart';
import '../models/piece.dart';
import '../models/position.dart';

/// 象棋中文记谱解析器（中文招法 → 起终点坐标）。
///
/// 记谱规则（与 [NotationText.describe] 互为逆操作）：
/// - 红方用汉字数字（一…九），列号从红方右手边起：棋盘 col 8 = 一。
/// - 黑方用阿拉伯数字（1…9），列号从黑方右手边起：棋盘 col 0 = 1。
/// - 普通形式：`棋子名 + 起点列号 + 平/进/退 + 数字`（如「炮二平五」）。
///   - 平：末位为目标列号；
///   - 直线子（帅/车/炮/兵）进退：末位为步数，列不变；
///   - 斜走子（马/士/象）进退：末位为目标列号。
/// - 同列多子消歧形式：`前/后(+中/二/三/四) + 棋子名 + 平/进/退 + 数字`
///   （如「前车平六」「后马进三」）。
///
/// 解析必须结合走子前盘面（消歧与目标推算都依赖棋盘）。
class ChineseNotation {
  ChineseNotation._();

  static const List<String> redNums = [
    '一', '二', '三', '四', '五', '六', '七', '八', '九',
  ];
  static const List<String> blackNums = [
    '１', '２', '３', '４', '５', '６', '７', '８', '９','1','2','3','4','5','6','7','8','9',
  ];

  /// 棋子名 → (类型, 阵营)；阵营为 null 表示双方同名（马/车/炮）。
  static const Map<String, (PieceType, Side?)> _pieceNames = {
    '帅': (PieceType.general, Side.red),
    '将': (PieceType.general, Side.black),
    '仕': (PieceType.advisor, Side.red),
    '士': (PieceType.advisor, Side.black),
    '相': (PieceType.elephant, Side.red),
    '象': (PieceType.elephant, Side.black),
    '马': (PieceType.horse, null),
    '车': (PieceType.chariot, null),
    '炮': (PieceType.cannon, null),
    '兵': (PieceType.soldier, Side.red),
    '卒': (PieceType.soldier, Side.black),
  };

  static const Set<String> _ordinalChars = {'前', '后', '中', '二', '三', '四'};

  /// 判断一个 token 是否像中文招法（首字符为棋子名或前后消歧字）。
  static bool looksLikeChinese(String token) {
    if (token.isEmpty) return false;
    final first = token[0];
    return _pieceNames.containsKey(first) || _ordinalChars.contains(first);
  }

  /// 字符是否为棋子名（帅/将/仕/士/相/象/马/车/炮/兵/卒）。
  static bool isPieceName(String ch) => _pieceNames.containsKey(ch);

  /// 字符是否为同列多子消歧字（前/后/中/二/三/四）。
  static bool isOrdinal(String ch) => _ordinalChars.contains(ch);

  /// 字符是否为红方汉字数字（一..九）。
  static bool isRedDigit(String ch) => redNums.contains(ch);
  /// 字符是否为黑方阿拉伯数字（1..9）。
  static bool isBlackDigit(String ch) => blackNums.contains(ch);

  /// 粗校验一个 4 字中文招法的结构是否完整。
  ///
  /// - 普通形式：棋子名 + 列号 + 平/进/退 + 数字
  /// - 消歧形式：消歧字 + 棋子名 + 平/进/退 + 数字
  static bool isValidToken(String t) {
    if (t.length != 4) return false;
    if (t[2] != '平' && t[2] != '进' && t[2] != '退') return false;
    final tailOk = isRedDigit(t[3]) || isBlackDigit(t[3]);
    if (!tailOk) return false;
    if (isOrdinal(t[0])) {
      return isPieceName(t[1]);
    }
    if (isPieceName(t[0])) {
      return isRedDigit(t[1]) || isBlackDigit(t[1]);
    }
    return false;
  }

  /// 解析中文招法 [token]，结合走子前盘面 [board] 与走子方 [side]，
  /// 返回 (起点, 终点)。
  ///
  /// 失败时抛出 [FormatException]，message 可直接展示给用户。
  static (Position, Position) parse(Board board, Side side, String token) {
    final t = token.trim();
    if (t.length < 4) {
      throw FormatException('招法文字过短："$token"');
    }

    final PieceType type;
    final Position from;
    final String action;
    final int tailValue; // 动词后的数字（1..9）

    if (_ordinalChars.contains(t[0])) {
      // —— 多子同列消歧形式：前/后/中/二/三/四 + 棋子名 + 动词 + 数字 ——
      final ordinal = t[0];
      final nameChar = t[1];
      final entry = _pieceNames[nameChar];
      if (entry == null) {
        throw FormatException('无法识别的棋子名："$nameChar"（招法 $token）');
      }
      type = entry.$1;
      _checkSide(entry.$2, side, token);
      action = t[2];
      tailValue = _parseTailNumber(t.substring(3), side);
      from = _findByOrdinal(board, side, type, ordinal, action, tailValue, token);
    } else {
      // —— 普通形式：棋子名 + 起点列号 + 动词 + 数字 ——
      final nameChar = t[0];
      final entry = _pieceNames[nameChar];
      if (entry == null) {
        throw FormatException('无法识别的棋子名："$nameChar"（招法 $token）');
      }
      type = entry.$1;
      _checkSide(entry.$2, side, token);
      final fileValue = _parseTailNumber(t[1], side);
      action = t[2];
      tailValue = _parseTailNumber(t.substring(3), side);
      final fromCol = fileLabelToCol(side, fileValue);
      final candidates = <Position>[];
      for (var r = 0; r < 10; r++) {
        final p = Position(fromCol, r);
        final piece = board.pieceAt(p);
        if (piece != null && piece.side == side && piece.type == type) {
          candidates.add(p);
        }
      }
      if (candidates.isEmpty) {
        throw FormatException('第 $fileValue 路找不到 $nameChar（招法 $token）');
      }
      if (candidates.length == 1) {
        from = candidates.single;
      } else {
        // 同列多子却没用消歧形式：尝试找唯一目标在棋盘内的候选
        final valid = candidates
            .where((p) {
              final to = _computeTarget(p, type, side, action, tailValue);
              return to != null && to.isValid;
            })
            .toList();
        if (valid.length != 1) {
          throw FormatException('同列多子，需用前/后消歧（招法 $token）');
        }
        from = valid.single;
      }
    }

    final to = _computeTarget(from, type, side, action, tailValue);
    if (to == null || !to.isValid) {
      throw FormatException('目标位置超出棋盘（招法 $token）');
    }
    return (from, to);
  }

  // -------------------------------------------------------------------------

  static void _checkSide(Side? nameSide, Side toMove, String token) {
    if (nameSide != null && nameSide != toMove) {
      throw FormatException('棋子阵营与走子方不符（招法 $token）');
    }
  }

  /// 解析一位数字（红方汉字 一..九，黑方阿拉伯 1..9）为 1..9。
  static int _parseTailNumber(String s, Side side) {
    final t = s.trim();
    if (t.isEmpty) throw FormatException('缺少数字："$s"');
    final ch = t[0];
    if (side == Side.red) {
      final idx = redNums.indexOf(ch);
      if (idx < 0) {
        throw FormatException('红方招法数字应为汉字一..九，实际 "$ch"');
      }
      return idx + 1;
    }
    final n = int.tryParse(ch);
    if (n == null || n < 1 || n > 9) {
      throw FormatException('黑方招法数字应为 1..9，实际 "$ch"');
    }
    return n;
  }

  /// 列号（1..9，按走子方右手边起）转换为棋盘 col。
  static int fileLabelToCol(Side side, int fileValue) {
    if (side == Side.red) return 9 - fileValue; // 一(1) → col 8
    return fileValue - 1; // 1 → col 0
  }

  /// 同列多子消歧：搜索所有有多枚同类棋子的列，按 [ordinal] 选取，
  /// 并要求推导出的目标在棋盘内。多个候选都可行时抛歧义异常。
  static Position _findByOrdinal(
    Board board,
    Side side,
    PieceType type,
    String ordinal,
    String action,
    int tailValue,
    String token,
  ) {
    Position? matched;
    for (var col = 0; col < 9; col++) {
      final sameFile = <Position>[];
      for (var r = 0; r < 10; r++) {
        final p = Position(col, r);
        final piece = board.pieceAt(p);
        if (piece != null && piece.side == side && piece.type == type) {
          sameFile.add(p);
        }
      }
      if (sameFile.length < 2) continue;
      // 前→后排序：红方 row 小在前，黑方 row 大在前
      sameFile.sort((a, b) =>
          side == Side.red ? a.row.compareTo(b.row) : b.row.compareTo(a.row));
      final idx = _ordinalIndex(ordinal, sameFile.length);
      if (idx < 0 || idx >= sameFile.length) continue;
      final candidate = sameFile[idx];
      final to = _computeTarget(candidate, type, side, action, tailValue);
      if (to != null && to.isValid) {
        if (matched != null) {
          throw FormatException('招法起点存在歧义（$token），请检查棋谱');
        }
        matched = candidate;
      }
    }
    if (matched == null) {
      throw FormatException('找不到符合 "$ordinal" 消歧的棋子（招法 $token）');
    }
    return matched;
  }

  /// 消歧字在 n 个棋子（前→后）中的索引。
  static int _ordinalIndex(String ordinal, int n) {
    switch (n) {
      case 2:
        {
          const map = {'前': 0, '后': 1};
          return map[ordinal] ?? -1;
        }
      case 3:
        {
          const map = {'前': 0, '中': 1, '后': 2};
          return map[ordinal] ?? -1;
        }
      case 4:
        {
          const map = {'前': 0, '二': 1, '三': 2, '后': 3};
          return map[ordinal] ?? -1;
        }
      default:
        {
          const map = {'前': 0, '二': 1, '中': 2, '三': 3, '四': 4};
          if (ordinal == '后') return n - 1;
          return map[ordinal] ?? -1;
        }
    }
  }

  /// 根据动词与末位数字计算终点。
  ///
  /// - 平：横移到目标列；
  /// - 直线子进退：列不变，行按走子方向变化 tailValue 步；
  /// - 斜走子进退：列变为目标列，行按棋子几何变化（士 1、象/马 2）。
  static Position? _computeTarget(
    Position from,
    PieceType type,
    Side side,
    String action,
    int tailValue,
  ) {
    if (action == '平') {
      final col = fileLabelToCol(side, tailValue);
      return Position(col, from.row);
    }

    final forward = action == '进';
    if (!forward && action != '退') return null;

    // 红方向上（row 减小）为进，黑方向下（row 增大）为进
    final sign = forward
        ? (side == Side.red ? -1 : 1)
        : (side == Side.red ? 1 : -1);

    if (_isDiagonal(type)) {
      final col = fileLabelToCol(side, tailValue);
      final deltaRow = type == PieceType.advisor ? 1 : 2;
      return Position(col, from.row + sign * deltaRow);
    } else {
      return Position(from.col, from.row + sign * tailValue);
    }
  }

  static bool _isDiagonal(PieceType type) =>
      type == PieceType.horse ||
      type == PieceType.advisor ||
      type == PieceType.elephant;
}
