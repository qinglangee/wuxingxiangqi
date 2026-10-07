import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart' show AssetManifest, rootBundle;

import '../config/config_manager.dart';

/// 一个残局库：库名 + FEN 字符串列表（按文件中行序）。
class CanjuLibrary {
  const CanjuLibrary({required this.name, required this.fens});

  /// 库名（assets/canju/ 或数据目录 canju/ 下文件名去扩展名）。
  final String name;

  /// 该库中所有残局 FEN，按文件行序；空行已剔除。
  final List<String> fens;

  int get length => fens.length;
  bool get isEmpty => fens.isEmpty;
  bool get isNotEmpty => fens.isNotEmpty;
  String operator [](int i) => fens[i];
}

/// 加载 `assets/canju/` 与数据目录 `canju/` 下的所有残局库。
///
/// 文件约定：每行一个 FEN，空行忽略；行内首尾空白会被 trim。
/// 内置库优先读 assets；assets 中不存在的库再读数据目录下的
/// `canju/` 子目录（该目录不存在时自动创建）。
class CanjuLibraryLoader {
  static const String _rootDir = 'assets/canju';

  /// 数据目录下的 canju 扩展题库目录（收藏等用户库所在）。
  /// 目录不存在时自动创建。
  static Future<Directory> dataCanjuDir() async {
    final dir = Directory('${await ConfigManager.instance.dataDirPath}'
        '${Platform.pathSeparator}canju');
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  /// 列出所有库名（去扩展名），按名称排序；含 `default` 的优先。
  /// 合并 assets 与数据目录 canju/ 下的 .txt 文件。
  static Future<List<String>> listNames() async {
    final names = <String>{};
    final manifest = await AssetManifest.loadFromAssetBundle(rootBundle);
    for (final asset in manifest.listAssets()) {
      final rel = asset.replaceAll('\\', '/');
      if (!rel.startsWith('$_rootDir/')) continue;
      if (!rel.toLowerCase().endsWith('.txt')) continue;
      final base = _baseNameOf(rel);
      if (base.isEmpty) continue;
      names.add(base);
    }
    // 数据目录 canju/ 下的扩展库（失败时忽略，只保留内置库）
    try {
      final dir = await dataCanjuDir();
      await for (final e in dir.list()) {
        if (e is! File) continue;
        if (!e.path.toLowerCase().endsWith('.txt')) continue;
        names.add(_baseNameOf(e.path));
      }
    } catch (_) {}
    final list = names.toList()..sort((a, b) {
      final ad = a.toLowerCase().contains('default') ? 0 : 1;
      final bd = b.toLowerCase().contains('default') ? 0 : 1;
      if (ad != bd) return ad - bd;
      return a.compareTo(b);
    });
    return list;
  }

  /// 加载指定名称的库。assets 与数据目录中都不存在时抛 [StateError]。
  static Future<CanjuLibrary> load(String name) async {
    String? data;
    try {
      data = await rootBundle.loadString('$_rootDir/$name.txt');
    } catch (_) {
      // assets 中没有该库，继续尝试数据目录
    }
    if (data == null) {
      String? fileData;
      try {
        final dir = await dataCanjuDir();
        final file =
            File('${dir.path}${Platform.pathSeparator}$name.txt');
        if (await file.exists()) fileData = await file.readAsString();
      } catch (_) {}
      if (fileData == null) throw StateError('残局库不存在: $name');
      data = fileData;
    }
    return CanjuLibrary(name: name, fens: _parseFens(data));
  }

  /// 加载所有库（listNames + 逐个 load）。
  static Future<List<CanjuLibrary>> loadAll() async {
    final names = await listNames();
    return [for (final n in names) await load(n)];
  }

  /// 从路径/资源名中提取去 .txt 扩展名的文件名。
  static String _baseNameOf(String path) {
    // Windows 下 Directory.list 返回反斜杠路径，先统一成正斜杠
    // 再取文件名，否则会把整个路径当成文件名。
    final normalized = path.replaceAll('\\', '/');
    final slash = normalized.lastIndexOf('/');
    final nameWithExt =
        slash >= 0 ? normalized.substring(slash + 1) : normalized;
    final dot = nameWithExt.toLowerCase().lastIndexOf('.txt');
    return dot >= 0 ? nameWithExt.substring(0, dot) : nameWithExt;
  }

  static List<String> _parseFens(String data) {
    final fens = <String>[];
    for (final raw in const LineSplitter().convert(data)) {
      final line = raw.trim();
      if (line.isEmpty) continue;
      fens.add(line);
    }
    return fens;
  }
}

/// 残局收藏：数据目录 canju/ 下的 `残局收藏.txt`，每行一个 FEN。
///
/// 收藏文件本身就是一个残局库（库名 [libraryName]），会随
/// [CanjuLibraryLoader.listNames]/load 一并出现与加载。
class CanjuFavorites {
  CanjuFavorites._();

  /// 收藏库的库名（即数据目录 canju/ 下的文件名，去扩展名）。
  static const String libraryName = '残局收藏';

  static Future<File> _file() async {
    final dir = await CanjuLibraryLoader.dataCanjuDir();
    return File('${dir.path}${Platform.pathSeparator}$libraryName.txt');
  }

  /// 当前收藏的所有 FEN（文件不存在时为空列表；返回可增长列表，
  /// 便于 add 直接追加）。
  static Future<List<String>> loadFens() async {
    final file = await _file();
    if (!await file.exists()) return <String>[];
    return CanjuLibraryLoader._parseFens(await file.readAsString());
  }

  /// 收藏一个残局 FEN（已存在时不重复添加）。返回是否发生了变更。
  static Future<bool> add(String fen) async {
    final f = fen.trim();
    final fens = await loadFens();
    if (fens.contains(f)) return false;
    fens.add(f);
    await _write(fens);
    return true;
  }

  /// 取消收藏：删除收藏文件中所有与 [fen] 相同的行。返回是否发生了变更。
  static Future<bool> remove(String fen) async {
    final f = fen.trim();
    final fens = await loadFens();
    final next = fens.where((e) => e != f).toList();
    if (next.length == fens.length) return false;
    await _write(next);
    return true;
  }

  static Future<void> _write(List<String> fens) async {
    final file = await _file();
    await file.writeAsString(fens.isEmpty ? '' : '${fens.join('\n')}\n');
  }
}
