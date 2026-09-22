import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

/// 单库的过关位图（16 进制字符串，末尾 '0' 字符省略）。
///
/// 约定：每一局就是一关，无多关卡概念。位图按"每局 1 bit"编码，
/// 每 4 局压缩为 1 个 16 进制字符——
///   字符串第 i 个字符对应第 4i、4i+1、4i+2、4i+3 局的过关状态，
/// 低位在前：第 0 个 bit 表示第 4i 局，第 1 个 bit 表示第 4i+1 局，依此
/// 类推。字符串末尾连续的 '0' 字符（即后续连续 4 局全没过）可省略。
@immutable
class CanjuProgress {
  const CanjuProgress([this.hex = '']);

  final String hex;

  /// 第 [index] 局（0-based）是否已过关。
  bool isCleared(int index) {
    if (index < 0) return false;
    final charIdx = index ~/ 4;
    final bitInChar = index % 4;
    if (charIdx >= hex.length) return false;
    final v = _hexToInt(hex[charIdx]);
    return (v & (1 << bitInChar)) != 0;
  }

  /// 把第 [index] 局置为已过关，返回新的 [CanjuProgress]。
  /// 末尾连续的 '0' 字符会被裁掉。
  CanjuProgress setCleared(int index) {
    if (index < 0) return this;
    final charIdx = index ~/ 4;
    final bitInChar = index % 4;
    final needed = charIdx + 1;
    final chars = List<String>.generate(
      needed > hex.length ? needed : hex.length,
      (i) => i < hex.length ? hex[i] : '0',
    );
    var v = _hexToInt(chars[charIdx]);
    v |= (1 << bitInChar);
    chars[charIdx] = v.toRadixString(16);
    var end = chars.length;
    while (end > 0 && chars[end - 1] == '0') {
      end--;
    }
    return CanjuProgress(chars.sublist(0, end).join());
  }

  /// 已过关的最大连续局数（从第 0 局起连续过关的局数）。
  int get clearedCount {
    var c = 0;
    while (isCleared(c)) {
      c++;
    }
    return c;
  }

  static int _hexToInt(String ch) {
    final v = int.tryParse(ch, radix: 16);
    return v ?? 0;
  }

  CanjuProgress copyWith(String hex) => CanjuProgress(hex);

  @override
  bool operator ==(Object other) =>
      other is CanjuProgress && other.hex == hex;

  @override
  int get hashCode => hex.hashCode;
}

/// 单个库的记录：上次选到第几局 + 过关位图。
@immutable
class LibraryRecord {
  const LibraryRecord({this.currentIndex = 0, this.progress = const CanjuProgress()});

  final int currentIndex;
  final CanjuProgress progress;

  LibraryRecord copyWith({int? currentIndex, CanjuProgress? progress}) =>
      LibraryRecord(
        currentIndex: currentIndex ?? this.currentIndex,
        progress: progress ?? this.progress,
      );

  Map<String, dynamic> toJson() => {
        'currentIndex': currentIndex,
        'progress': progress.hex,
      };

  factory LibraryRecord.fromJson(Map<String, dynamic> json) => LibraryRecord(
        currentIndex: (json['currentIndex'] as num?)?.toInt() ?? 0,
        progress: CanjuProgress((json['progress'] as String?) ?? ''),
      );
}

/// 残局记录仓库：持久化所有库的当前局与过关状态。
///
/// 文件：应用文档目录下 `canju_progress.json`，与 `app_config.json` 并列。
class CanjuStore extends ChangeNotifier {
  CanjuStore._();

  static final CanjuStore instance = CanjuStore._();

  static const String kFileName = 'canju_progress.json';

  String? _lastLibrary;
  Map<String, LibraryRecord> _records = {};

  bool _loaded = false;
  bool get isLoaded => _loaded;

  /// 上次打开的库名（null 表示尚未用过残局）。
  String? get lastLibrary => _lastLibrary;

  /// 全部库记录（只读）。
  Map<String, LibraryRecord> get records =>
      Map.unmodifiable(_records);

  /// 读取某库的记录，不存在则返回默认（currentIndex=0、空 progress）。
  LibraryRecord recordOf(String libraryName) =>
      _records[libraryName] ?? const LibraryRecord();

  /// 启动时加载。文件不存在或损坏时使用默认空记录。
  Future<void> load() async {
    try {
      final file = await _file();
      if (await file.exists()) {
        final raw = await file.readAsString();
        if (raw.trim().isEmpty) {
          _lastLibrary = null;
          _records = {};
        } else {
          final json = jsonDecode(raw) as Map<String, dynamic>;
          _lastLibrary = json['lastLibrary'] as String?;
          final libs = json['libraries'] as Map<String, dynamic>? ?? {};
          _records = {
            for (final e in libs.entries)
              e.key: LibraryRecord.fromJson(
                  Map<String, dynamic>.from(e.value as Map)),
          };
        }
      }
    } catch (e) {
      debugPrint('[CanjuStore] load failed: $e');
      _lastLibrary = null;
      _records = {};
    } finally {
      _loaded = true;
    }
  }

  /// 设置/更新上次打开的库名。空字符串视为清除。
  Future<void> setLastLibrary(String? name) async {
    _lastLibrary = (name == null || name.isEmpty) ? null : name;
    notifyListeners();
    await save();
  }

  /// 更新某库的记录。传入 [updater] 在副本上修改，再写回。
  Future<void> updateRecord(
    String libraryName,
    LibraryRecord Function(LibraryRecord current) updater,
  ) async {
    final cur = (_records[libraryName] ?? const LibraryRecord()).copyWith();
    final next = updater(cur);
    _records[libraryName] = next;
    notifyListeners();
    await save();
  }

  /// 便捷：仅更新当前局。
  Future<void> setCurrentIndex(String libraryName, int index) =>
      updateRecord(libraryName, (c) => c.copyWith(currentIndex: index));

  /// 便捷：标记第 [index] 局已过关。
  Future<void> markCleared(String libraryName, int index) =>
      updateRecord(
        libraryName,
        (c) => c.copyWith(
          progress: c.progress.setCleared(index),
        ),
      );

  Future<void> save() async {
    try {
      final file = await _file();
      final parent = file.parent;
      if (!await parent.exists()) {
        await parent.create(recursive: true);
      }
      const encoder = JsonEncoder.withIndent('  ');
      final json = {
        'lastLibrary': _lastLibrary,
        'libraries': {
          for (final e in _records.entries) e.key: e.value.toJson(),
        },
      };
      await file.writeAsString(encoder.convert(json));
    } catch (e) {
      debugPrint('[CanjuStore] save failed: $e');
    }
  }

  Future<File> _file() async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}${Platform.pathSeparator}$kFileName');
  }
}
