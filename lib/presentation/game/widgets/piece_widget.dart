import 'dart:io';

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
      // 数据目录自定义套系优先用 customPiecePath
      if (bc.customPiecePath != null && bc.customPiecePath!.isNotEmpty) {
        return _buildImagePieceFile(bc.customPiecePath!);
      }
      return _buildImagePiece(bc.pieceStyle);
    }
    return _buildClassicPiece();
  }

  /// 按配置生成棋子阴影；开关关闭时返回空列表（不绘制阴影）。
  ///
  /// 阴影圆半径 = 棋子半径 × [BoardConfig.shadowRadiusFactor]
  /// （通过 spreadRadius 调整），偏移量为棋子半径的倍数，
  /// 模糊程度 [BoardConfig.shadowBlur] 为绝对像素值。
  List<BoxShadow> _pieceShadows() {
    final bc = ConfigManager.instance.config.board;
    if (!bc.pieceShadow) return const [];
    final r = size / 2;
    return [
      BoxShadow(
        color: Colors.black26,
        blurRadius: bc.shadowBlur,
        spreadRadius: (bc.shadowRadiusFactor - 1) * r,
        offset: Offset(
          bc.shadowOffsetXFactor * r,
          bc.shadowOffsetYFactor * r,
        ),
      ),
    ];
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
          boxShadow: _pieceShadows(),
        ),
        child: ClipOval(
          child: Image.asset(
            path,
            fit: BoxFit.cover,
            // 图片缺失（套系不完整等）时回退为经典绘制，避免红屏
            errorBuilder: (_, _, _) => _buildClassicPiece(),
          ),
        ),
      ),
    );
  }

  /// 图片棋子（数据目录版本）：从文件路径加载，逻辑与内置版一致。
  Widget _buildImagePieceFile(String dirPath) {
    final path =
        AssetCatalog.pieceFileAsset(dirPath, piece.side, piece.type);
    return SizedBox(
      width: size,
      height: size,
      child: DecoratedBox(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: selected
              ? Border.all(color: AppTheme.selectedHighlight, width: 3)
              : null,
          boxShadow: _pieceShadows(),
        ),
        child: ClipOval(
          child: Image.file(
            File(path),
            fit: BoxFit.cover,
            errorBuilder: (_, _, _) => _buildClassicPiece(),
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
          boxShadow: _pieceShadows(),
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
