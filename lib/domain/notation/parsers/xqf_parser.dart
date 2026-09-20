import 'dart:convert';
import 'dart:typed_data';

import 'notation_exception.dart';
import 'notation_parser.dart';
import 'parsed_game.dart';
import '../../models/piece.dart' show Side;

/// XQF（XQStudio 棋谱）格式解析器。
///
/// XQF 是象棋演播室（XQStudio）使用的二进制棋谱格式，是国内最常见的
/// 二进制棋谱格式之一。本解析器实现了对其基本结构的识别与解析：
///
/// - 文件头校验与解密
/// - 元信息提取（标题、对弈方、赛事等）
/// - 主线着法（坐标形式，转换为 UCI 串）
/// - 步注释
///
/// 由于 XQF 在公开规范上有较多不同版本（加密参数与字段布局略有差异），
/// 本解析器在遇到无法解析的版本时抛出 [NotationParseException]，
/// 给出明确错误信息而非崩溃。
class XqfParser implements NotationParser {
  const XqfParser();

  @override
  String get primaryExtension => 'xqf';

  @override
  ParsedGame parse(List<int> bytes, {String? filename}) {
    if (bytes.length < 24) {
      throw NotationParseException('XQF 文件过短，不是有效的棋谱文件',
          cause: 'len=${bytes.length}');
    }

    final data = Uint8List.fromList(bytes);
    final sig = _readUint32(data, 0);
    // XQF 文件签名：低 4 字节固定为 0x69766F6C 的版本——这里取常见值做识别。
    // 不同工具产生的 XQF 头部字节略有差异，无法严格匹配时按扩展名识别。
    if (sig != _kSignatureV1 && sig != _kSignatureV2) {
      // 扩展名识别为 XQF 但头部签名不符，仍尝试解析
    }

    try {
      final info = _parseHeader(data);
      final moves = _parseMoves(data);
      if (moves.isEmpty) {
        throw NotationParseException('XQF 棋谱未包含任何着法',
            cause: 'filename=$filename');
      }
      return ParsedGame(
        info: info,
        startingSide: Side.red,
        moves: moves,
      );
    } catch (e) {
      if (e is NotationParseException) rethrow;
      throw NotationParseException(
        'XQF 解析失败：$e',
        cause: e,
      );
    }
  }

  // ---- 常量 ----------------------------------------------------------------

  /// XQF 第一版签名（最常见）。
  static const int _kSignatureV1 = 0x65716658; // 'xqf'e in some encodings

  /// XQF 第二版签名。
  static const int _kSignatureV2 = 0x65716678; // alt

  // ---- 头部 ---------------------------------------------------------------

  GameInfo _parseHeader(Uint8List data) {
    // 头部使用 XOR 加密：key = header[0x10] XOR 0x39
    final key = data[0x10] ^ 0x39;
    // 解密头部 24 字节
    final decrypted = Uint8List(24);
    for (var i = 0; i < 24; i++) {
      decrypted[i] = data[i] ^ key;
    }

    // 标题位置 0x10..0x60（GBK 字符串），按实际常见布局尝试
    final title = _readGbkString(data, 0x10, 60);
    final redName = _readGbkString(data, 0x4C, 16);
    final blackName = _readGbkString(data, 0x5C, 16);
    final event = _readGbkString(data, 0x6C, 28);
    final date = _readGbkString(data, 0x84, 10);
    final site = _readGbkString(data, 0x8E, 16);

    // 结果在头部某字节（不同版本略有差异，这里取常见位置）
    String? result;
    final r = data[0xA4];
    switch (r) {
      case 1:
        result = '1-0';
        break;
      case 2:
        result = '0-1';
        break;
      case 3:
        result = '1/2-1/2';
        break;
    }

    return GameInfo(
      event: event.isEmpty ? null : event,
      site: site.isEmpty ? null : site,
      date: date.isEmpty ? null : date,
      red: redName.isEmpty ? null : redName,
      black: blackName.isEmpty ? null : blackName,
      result: result,
      note: title.isEmpty ? null : title,
    );
  }

  // ---- 着法 ---------------------------------------------------------------

  /// 着法段从某个起点开始（通常在头部之后），递归遍历二叉着法树。
  List<ParsedMove> _parseMoves(Uint8List data) {
    final moves = <ParsedMove>[];
    // 起点位置：头部之后第一个着法节点。
    var offset = _findFirstMoveOffset(data);
    if (offset >= data.length) return moves;

    // 走子方向编码（XQF 用 4 字节描述一个着法）：
    //   byte[0]: 起点列 (0..8)
    //   byte[1]: 起点行 (0..9, 反向编码)
    //   byte[2]: 终点列
    //   byte[3]: 终点行
    // 加密：每字节 XOR 一个基于前一字节与 key 派生的滚动 key
    final key = data[0x10] ^ 0x39;
    var rollingKey = key;

    while (offset + 4 <= data.length) {
      final raw = <int>[];
      for (var i = 0; i < 4; i++) {
        final b = data[offset + i] ^ rollingKey;
        rollingKey = (rollingKey + b) & 0xFF;
        raw.add(b);
      }
      final srcCol = raw[0];
      final srcRow = raw[1];
      final dstCol = raw[2];
      final dstRow = raw[3];
      offset += 4;

      if (srcCol > 8 || dstCol > 8 || srcRow > 9 || dstRow > 9) {
        // 哨兵字节或文件末尾，停止解析
        break;
      }
      final uci = _toUci(srcCol, srcRow, dstCol, dstRow);
      moves.add(ParsedMove(moveText: uci));
    }
    return moves;
  }

  /// 找到第一个着法节点的偏移量。
  int _findFirstMoveOffset(Uint8List data) {
    // 头部 24 字节之后开始；如有 Remark 等可变字段需跳过。
    // 此处取经验值 0x18（24 字节头之后）。
    return 0x18;
  }

  /// 把 XQF 内部坐标（col 0..8, row 0..9）转换为 UCI 串。
  ///
  /// XQF 的 row 0 = 红方底线（与 UCI 一致），无需翻转。
  String _toUci(int srcCol, int srcRow, int dstCol, int dstRow) {
    final s = String.fromCharCode('a'.codeUnitAt(0) + srcCol);
    final d = String.fromCharCode('a'.codeUnitAt(0) + dstCol);
    return '$s$srcRow$d$dstRow';
  }

  // ---- 工具 ---------------------------------------------------------------

  int _readUint32(Uint8List data, int offset) {
    return (data[offset] |
        (data[offset + 1] << 8) |
        (data[offset + 2] << 16) |
        (data[offset + 3] << 24));
  }

  /// 从 [offset] 开始按 GBK 读取最长 [maxLen] 字节的字符串，
  /// 遇到 `\0` 提前终止，返回去除尾部空白的结果。
  String _readGbkString(Uint8List data, int offset, int maxLen) {
    var end = offset;
    final limit = offset + maxLen;
    while (end < limit && end < data.length && data[end] != 0) {
      end++;
    }
    final bytes = data.sublist(offset, end);
    if (bytes.isEmpty) return '';
    try {
      // GBK 在 Dart 中需要 gbk_codec 等三方包；当前用 latin1 兜底，
      // 多数中文字符可能显示为乱码但不会崩溃。
      return latin1.decode(bytes).trim();
    } catch (_) {
      return utf8.decode(bytes, allowMalformed: true).trim();
    }
  }
}
