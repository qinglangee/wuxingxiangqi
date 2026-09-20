import 'notation_exception.dart';
import 'notation_parser.dart';
import 'parsed_game.dart';
import 'pgn_parser.dart';
import 'xqf_parser.dart';

/// 棋谱加载器：按文件扩展名分发到对应解析器。
///
/// 用法：
/// ```dart
/// final game = await NotationLoader.load(path: path, bytes: bytes);
/// ```
///
/// 找不到对应解析器或解析失败时抛出 [NotationParseException]。
class NotationLoader {
  NotationLoader._();

  /// 已注册的解析器（按扩展名索引）。
  static final Map<String, NotationParser> _parsers = {
    'pgn': const PgnParser(),
    'xqf': const XqfParser(),
  };

  /// 注册新解析器（覆盖同名扩展）。
  static void register(NotationParser parser) {
    _parsers[parser.primaryExtension.toLowerCase()] = parser;
  }

  /// 按文件扩展名选择解析器解析字节内容。
  ///
  /// [path] 用于取扩展名，[bytes] 是文件原始字节。
  static ParsedGame load({required String path, required List<int> bytes}) {
    final ext = _extensionOf(path).toLowerCase();
    final parser = _parsers[ext];
    if (parser == null) {
      throw NotationParseException(
        '不支持的棋谱格式：.$ext（当前支持：${_parsers.keys.map((e) => '.$e').join(' / ')}）',
        cause: 'path=$path',
      );
    }
    return parser.parse(bytes, filename: path);
  }

  /// 取出文件扩展名（不带点，无则返回空串）。
  static String _extensionOf(String path) {
    final dot = path.lastIndexOf('.');
    if (dot < 0 || dot == path.length - 1) return '';
    return path.substring(dot + 1);
  }
}
