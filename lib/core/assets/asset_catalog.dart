import 'package:flutter/services.dart' show AssetManifest, rootBundle;

import '../../domain/models/piece.dart';

/// 图片资源目录：发现与映射棋盘 / 棋子图片资源。
///
/// 资源约定：
/// - 棋盘图片：`assets/images/boards/<名称>.png`，每张图一个可选项；
/// - 棋子套系：`assets/images/pieces/<套系名>/`，一个子目录一套棋子，
///   内含图片按 `<w|b><棋子字母>.png` 命名：
///   - 第 1 个字母：`w`=红方、`b`=黑方；
///   - 第 2 个字母：`k`=帅/将、`a`=士/仕、`b`=相/象、`n`=马、
///     `r`=车、`c`=炮、`p`=兵/卒。
///
/// 排序规则：名称含 "default" 的排第一（默认资源），其余按名称排序。
class AssetCatalog {
  AssetCatalog._();

  /// 棋盘图片根目录（含结尾斜杠）。
  static const String boardsDir = 'assets/images/boards/';

  /// 棋子套系根目录（含结尾斜杠）。
  static const String piecesDir = 'assets/images/pieces/';

  /// 棋子类型 → 图片文件名字母。
  static const Map<PieceType, String> _typeLetters = {
    PieceType.general: 'k',
    PieceType.advisor: 'a',
    PieceType.elephant: 'b',
    PieceType.horse: 'n',
    PieceType.chariot: 'r',
    PieceType.cannon: 'c',
    PieceType.soldier: 'p',
  };

  /// 套系内某棋子的资源路径。
  static String pieceAsset(String setName, Side side, PieceType type) =>
      '$piecesDir$setName/'
      '${side == Side.red ? 'w' : 'b'}${_typeLetters[type]}.png';

  /// 棋盘文件名 → 完整资源路径。
  static String boardAsset(String fileName) => '$boardsDir$fileName';

  /// 从打包资源清单中列出所有棋盘图片文件名（不含目录前缀）。
  ///
  /// 清单加载失败时返回空列表（设置页显示为空，不影响其他功能）。
  static Future<List<String>> loadBoards() async {
    try {
      final manifest = await AssetManifest.loadFromAssetBundle(rootBundle);
      final names = manifest
          .listAssets()
          .where((a) => a.startsWith(boardsDir) && _isImage(a))
          .map((a) => a.substring(boardsDir.length))
          .toList();
      _sortDefaultFirst(names);
      return names;
    } catch (_) {
      return const [];
    }
  }

  /// 从打包资源清单中列出所有棋子套系目录名。
  ///
  /// 清单加载失败时返回空列表。
  static Future<List<String>> loadPieceSets() async {
    try {
      final manifest = await AssetManifest.loadFromAssetBundle(rootBundle);
      final sets = <String>{};
      for (final a in manifest.listAssets()) {
        if (!a.startsWith(piecesDir) || !_isImage(a)) continue;
        final rest = a.substring(piecesDir.length);
        final slash = rest.indexOf('/');
        if (slash > 0) sets.add(rest.substring(0, slash));
      }
      final list = sets.toList();
      _sortDefaultFirst(list);
      return list;
    } catch (_) {
      return const [];
    }
  }

  /// 名称含 "default" 的排第一，其余按名称（忽略大小写）排序。
  static void _sortDefaultFirst(List<String> names) {
    names.sort((a, b) {
      final da = _isDefaultName(a);
      final db = _isDefaultName(b);
      if (da != db) return da ? -1 : 1;
      return a.toLowerCase().compareTo(b.toLowerCase());
    });
  }

  static bool _isDefaultName(String name) =>
      name.toLowerCase().contains('default');

  static bool _isImage(String asset) {
    final lower = asset.toLowerCase();
    return lower.endsWith('.png') ||
        lower.endsWith('.jpg') ||
        lower.endsWith('.jpeg') ||
        lower.endsWith('.webp') ||
        lower.endsWith('.gif');
  }
}
