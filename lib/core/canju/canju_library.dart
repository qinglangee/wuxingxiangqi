import 'dart:convert';

import 'package:flutter/services.dart' show AssetManifest, rootBundle;

/// 一个残局库：库名 + FEN 字符串列表（按文件中行序）。
class CanjuLibrary {
  const CanjuLibrary({required this.name, required this.fens});

  /// 库名（assets/canju/ 下文件名去扩展名）。
  final String name;

  /// 该库中所有残局 FEN，按文件行序；空行已剔除。
  final List<String> fens;

  int get length => fens.length;
  String operator [](int i) => fens[i];
}

/// 加载 `assets/canju/` 下的所有残局库。
///
/// 文件约定：每行一个 FEN，空行忽略；行内首尾空白会被 trim。
class CanjuLibraryLoader {
  static const String _rootDir = 'assets/canju';

  /// 列出所有库名（去扩展名），按名称排序；含 `default` 的优先。
  static Future<List<String>> listNames() async {
    final names = <String>{};
    final manifest = await AssetManifest.loadFromAssetBundle(rootBundle);
    for (final asset in manifest.listAssets()) {
      final rel = asset.replaceAll('\\', '/');
      if (!rel.startsWith('$_rootDir/')) continue;
      if (!rel.toLowerCase().endsWith('.txt')) continue;
      // 提取文件名（去掉目录前缀与 .txt 扩展名）
      final slash = rel.lastIndexOf('/');
      final nameWithExt = slash >= 0 ? rel.substring(slash + 1) : rel;
      final dot = nameWithExt.toLowerCase().lastIndexOf('.txt');
      final base = dot >= 0 ? nameWithExt.substring(0, dot) : nameWithExt;
      if (base.isEmpty) continue;
      names.add(base);
    }
    final list = names.toList()..sort((a, b) {
      final ad = a.toLowerCase().contains('default') ? 0 : 1;
      final bd = b.toLowerCase().contains('default') ? 0 : 1;
      if (ad != bd) return ad - bd;
      return a.compareTo(b);
    });
    return list;
  }

  /// 加载指定名称的库。库不存在时抛 [StateError]。
  static Future<CanjuLibrary> load(String name) async {
    final path = '$_rootDir/$name.txt';
    final data = await rootBundle.loadString(path);
    final fens = <String>[];
    for (final raw in const LineSplitter().convert(data)) {
      final line = raw.trim();
      if (line.isEmpty) continue;
      fens.add(line);
    }
    return CanjuLibrary(name: name, fens: fens);
  }

  /// 加载所有库（listNames + 逐个 load）。
  static Future<List<CanjuLibrary>> loadAll() async {
    final names = await listNames();
    return [for (final n in names) await load(n)];
  }
}
