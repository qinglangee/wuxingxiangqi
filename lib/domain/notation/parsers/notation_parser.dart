import 'notation_exception.dart';
import 'parsed_game.dart';

/// 棋谱解析器接口。
///
/// 不同格式（PGN、XQF、CBF 等）各自实现此接口，把原始文件内容
/// 转换为统一的 [ParsedGame]。解析失败时抛出 [NotationParseException]。
abstract class NotationParser {
  /// 解析器支持的主扩展名（小写，不带点），如 `'pgn'`、`'xqf'`。
  String get primaryExtension;

  /// 解析给定的字节内容。
  ///
  /// [bytes] 为原始文件字节，[filename] 仅用于错误信息（可选）。
  /// 不同格式可选择用字节或解码后的文本进行解析。
  ParsedGame parse(List<int> bytes, {String? filename});

  /// 把内部统一格式 [game] 序列化为该格式的文件字节（解析的逆操作）。
  ///
  /// 输出需包含全部主线着法、分支变着与各节点注释；不支持的内容
  /// （如某格式无法表达的字段）可安全丢弃。
  List<int> write(ParsedGame game);
}
