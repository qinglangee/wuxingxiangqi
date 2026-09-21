import 'package:flutter/material.dart';

import '../../../core/assets/asset_catalog.dart';
import '../../../core/config/app_config.dart';
import '../../../core/config/config_manager.dart';
import '../../../core/theme/app_theme.dart';
import '../../../domain/models/piece.dart';

/// 绘制单个棋子。
///
/// 根据配置选择显示方式：
/// - classic（默认）：圆形底 + 汉字 + 双层边框，代码绘制；
/// - image：直接显示 `assets/images/pieces/<套系>/<w|b><字母>.png` 图片，
///   图片缺失时回退到经典绘制。
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
    final bc = ConfigManager.instance.config.board;
    if (bc.pieceType == BoardConfig.kTypeImage && bc.pieceStyle.isNotEmpty) {
      return _buildImagePiece(bc.pieceStyle);
    }
    return _buildClassicPiece();
  }

  /// 图片棋子：套系图片裁圆显示，选中时加高亮描边。
  Widget _buildImagePiece(String setName) {
    final path = AssetCatalog.pieceAsset(setName, piece.side, piece.type);
    return SizedBox(
      width: size,
      height: size,
      child: DecoratedBox(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: selected
              ? Border.all(color: AppTheme.selectedHighlight, width: 3)
              : null,
          boxShadow: const [
            BoxShadow(
              color: Colors.black26,
              blurRadius: 3,
              offset: Offset(0, 2),
            ),
          ],
        ),
        child: ClipOval(
          child: Image.asset(
            path,
            fit: BoxFit.cover,
            // 图片缺失（套系不完整等）时回退为经典绘制，避免红屏
            errorBuilder: (_, __, ___) => _buildClassicPiece(),
          ),
        ),
      ),
    );
  }

  /// 经典绘制：圆形底 + 汉字 + 双层边框。
  Widget _buildClassicPiece() {
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
