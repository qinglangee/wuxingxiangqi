import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../domain/models/piece.dart';

/// 绘制单个棋子：圆形底 + 汉字 + 双层边框。
class PieceWidget extends StatelessWidget {
  const PieceWidget({
    super.key,
    required this.piece,
    required this.size,
    this.selected = false,
  });

  final Piece piece;
  final double size;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final color =
        piece.side == Side.red ? AppTheme.redPiece : AppTheme.blackPiece;
    return SizedBox(
      width: size,
      height: size,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: AppTheme.pieceBackground,
          shape: BoxShape.circle,
          border: Border.all(
            color: selected ? AppTheme.selectedHighlight : AppTheme.pieceBorder,
            width: selected ? 3 : 2,
          ),
          boxShadow: const [
            BoxShadow(
              color: Colors.black26,
              blurRadius: 3,
              offset: Offset(0, 2),
            ),
          ],
        ),
        child: Center(
          child: Text(
            piece.label,
            style: TextStyle(
              fontSize: size * 0.5,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
        ),
      ),
    );
  }
}
