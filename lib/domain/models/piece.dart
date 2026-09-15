/// 棋子类型(7 种)。
enum PieceType {
  general,    // 将/帅
  advisor,    // 士/仕
  elephant,   // 象/相
  horse,      // 马
  chariot,    // 车
  cannon,     // 炮
  soldier,    // 兵/卒
}

/// 阵营。
enum Side {
  red,
  black,
}

/// 单个棋子。
///
/// `piece` 与 `side` 的组合决定显示文字与规则。例如红将显示"帅"，黑将显示"将"。
class Piece {
  const Piece({required this.type, required this.side});

  final PieceType type;
  final Side side;

  /// 棋子显示的中文文字。
  String get label {
    const labels = <Side, Map<PieceType, String>>{
      Side.red: {
        PieceType.general: '帥',
        PieceType.advisor: '仕',
        PieceType.elephant: '相',
        PieceType.horse: '傌',
        PieceType.chariot: '俥',
        PieceType.cannon: '炮',
        PieceType.soldier: '兵',
      },
      Side.black: {
        PieceType.general: '將',
        PieceType.advisor: '士',
        PieceType.elephant: '象',
        PieceType.horse: '馬',
        PieceType.chariot: '車',
        PieceType.cannon: '砲',
        PieceType.soldier: '卒',
      },
    };
    return labels[side]![type]!;
  }

  Piece copyWith() => Piece(type: type, side: side);

  @override
  String toString() => '${side == Side.red ? "红" : "黑"}$label';

  @override
  bool operator ==(Object other) =>
      other is Piece && other.type == type && other.side == side;

  @override
  int get hashCode => Object.hash(type, side);
}
