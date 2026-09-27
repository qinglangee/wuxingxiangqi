import 'dart:convert';

import '../../notation/chinese_notation.dart';
import 'notation_exception.dart';
import 'notation_parser.dart';
import 'parsed_game.dart';
import '../../models/piece.dart' show Side;

/// PGN（Portable Game Notation）格式解析器。
///
/// 支持 PGN 标准结构：
/// - 头部标签对：`[Key "Value"]`，包括可选的 `[FEN "..."]` 起始局面；
/// - 着法区默认使用**中文招法**（如「炮二平五」「马8进7」），
///   也兼容 ICCS/UCI 坐标着法（如 `e3e4`）；
/// - 注释：`{...}`（保留到对应步）；
/// - 变着 `(...)`：当前版本仅保留主线，变着内容忽略；
/// - NAG 标记 `$1`、`!`、`?` 等：忽略；
/// - 结果：`1-0` / `0-1` / `1/2-1/2` / `*`：忽略。
class PgnParser implements NotationParser {
  const PgnParser();

  @override
  String get primaryExtension => 'pgn';

  @override
  ParsedGame parse(List<int> bytes, {String? filename}) {
    final text = _decodeText(bytes);
    final headerEnd = _findMovetextStart(text);
    final header = text.substring(0, headerEnd);
    final movetext = text.substring(headerEnd);

    final tags = _parseHeaders(header);
    final info = GameInfo(
      event: tags['event'],
      site: tags['site'],
      date: tags['date'],
      red: tags['red'],
      black: tags['black'],
      result: tags['result'],
      opening: tags['opening'],
      note: tags['note'],
    );
    final fen = tags['fen'];
    // FEN 中若声明走子方，以 FEN 为准；否则红先
    final startingSide = _sideFromFen(fen) ?? Side.red;
    final moves = _parseMovetext(movetext, startingSide);
    if (moves.isEmpty) {
      throw NotationParseException(
        'PGN 棋谱没有有效的着法',
        cause: 'filename=$filename',
      );
    }
    return ParsedGame(
      info: info,
      startingFen: fen,
      startingSide: startingSide,
      moves: moves,
    );
  }

  // ---- 写入（解析的逆操作） ------------------------------------------------

  /// 标准开局 FEN（与 [Fen.fromBoard] 输出风格一致）。
  ///
  /// 起始局面等价于标准开局且红先时不写 FEN 头标（PGN 约定）。
  static const String _standardFen =
      'rnbakabnr/9/1c5c1/p1p1p1p1p/9/9/P1P1P1P1P/1C5C1/9/RNBAKABNR w - - 0 1';

  @override
  List<int> write(ParsedGame game) => utf8.encode(encodeText(game));

  /// 把 [game] 序列化为 PGN 文本：头部标签 + 着法区（含分支与注释）。
  String encodeText(ParsedGame game) {
    final sb = StringBuffer();

    // ---- 头部标签 ----
    void tag(String key, String? value) {
      if (value == null || value.trim().isEmpty) return;
      final escaped = value.replaceAll(r'\', r'\\').replaceAll('"', r'\"');
      sb.writeln('[$key "$escaped"]');
    }

    tag('Event', game.info.event);
    tag('Site', game.info.site);
    tag('Date', game.info.date);
    tag('Red', game.info.red);
    tag('Black', game.info.black);
    tag('Opening', game.info.opening);
    tag('Note', game.info.note);
    // 非标准开局（让子/排局/黑先）才写 FEN
    final fen = game.startingFen;
    if (fen != null && fen.trim() != _standardFen) {
      tag('FEN', fen.trim());
    }
    tag('Result', game.info.result ?? '*');
    sb.writeln();

    // ---- 着法区 ----
    final tokens = <String>[];

    // 开局评注：着法区开头的 {…}，载入时由根节点注释承接
    final rootComment = game.rootComment?.trim();
    if (rootComment != null && rootComment.isNotEmpty) {
      tokens.add('{${_sanitizeComment(rootComment)}}');
    }

    // 起始局面的分支（替代首着的变着线）
    for (final branch in game.rootBranches) {
      tokens.add('(');
      _appendLine(tokens, branch, game.startingSide, 1);
      tokens.add(')');
    }

    _appendLine(tokens, game.moves, game.startingSide, 1);

    final result = (game.info.result ?? '').trim();
    tokens.add(result.isEmpty ? '*' : result);

    // 按约 78 列折行，保持 PGN 可读性
    final line = StringBuffer();
    for (final t in tokens) {
      if (line.length + t.length + 1 > 78 && line.isNotEmpty) {
        sb.writeln(line.toString().trimRight());
        line.clear();
      }
      line.write('$t ');
    }
    if (line.isNotEmpty) sb.writeln(line.toString().trimRight());

    return sb.toString();
  }

  /// 递归拼接一条着法线（含每步的分支变着与注释）。
  ///
  /// [startSide] 为该线首着的走子方，[startRound] 为首着所在回合号。
  /// 红着前输出 `N.`；线首（含括号内变着首着为黑方）输出 `N...`。
  /// 每步走完后，其 [ParsedMove.branches] 以 `(…)` 形式紧随该步输出。
  void _appendLine(
    List<String> out,
    List<ParsedMove> line,
    Side startSide,
    int startRound,
  ) {
    var round = startRound;
    for (var i = 0; i < line.length; i++) {
      final m = line[i];
      final side = m.side ?? (i == 0 ? startSide : _flip(line[i - 1].side ?? startSide));

      if (side == Side.red) {
        out.add('$round.');
      } else if (i == 0) {
        // 黑方先行的主线或变着首着：N...
        out.add('$round...');
      }

      // 注释写在着法记号之前：标准 PGN 中该位置的 {…} 注解走子前局面，
      // 同时也与本应用解析器「{…} 附加到下一步」的约定一致，保证
      // 保存后重新打开注释不丢失。
      final comment = m.comment?.trim();
      if (comment != null && comment.isNotEmpty) {
        out.add('{${_sanitizeComment(comment)}}');
      }

      out.add(m.notation ?? m.moveText);

      // 本步走完后局面的变着（替代下一着），递归输出
      for (final branch in m.branches) {
        out.add('(');
        _appendLine(out, branch, _flip(side), side == Side.red ? round : round + 1);
        out.add(')');
      }

      if (side == Side.black) round++;
    }
  }

  /// 注释中不允许出现未转义的花括号（PGN 注释定界符）。
  String _sanitizeComment(String text) =>
      text.replaceAll('{', '(').replaceAll('}', ')');

  // ---- 文本解码 ------------------------------------------------------------

  /// 默认按 UTF-8 解码；失败时退回 latin1 兜底（不崩溃）。
  ///
  /// 老版本中文 PGN 若使用 GBK 编码，中文会显示为乱码，需要后续引入
  /// gbk_codec 等三方包完善。
  String _decodeText(List<int> bytes) {
    try {
      return _normalizeDigits(_stripBom(utf8.decode(bytes, allowMalformed: false)));
    } catch (_) {
      return _normalizeDigits(_stripBom(latin1.decode(bytes)));
    }
  }

  /// 去掉文本开头的 BOM 标记。
  ///
  /// UTF-8 BOM（EF BB BF）解码后是零宽字符 U+FEFF；latin1 兜底路径下
  /// 则显示为 "ï»¿"。不去掉会导致头部解析失败（首字符不是 `[`）。
  String _stripBom(String text) {
    if (text.startsWith('\uFEFF')) return text.substring(1);
    if (text.startsWith('ï»¿')) return text.substring(3);
    return text;
  }

  /// 全角数字（０..９）归一化为半角（0..9）。
  ///
  /// 部分棋谱软件输出黑方着法时使用全角数字（如「炮８平５」），
  /// 中文招法解析只认半角 1..9，解析前先统一替换。
  String _normalizeDigits(String text) {
    // 全角数字 U+FF10..U+FF19 与半角 0x30..0x39 固定偏移 0xFEE0
    // 注意：Dart 的 StringBuffer 构造参数是"初始内容"而非容量，
    // 不能传 text.length，否则长度数字会被拼到文本开头。
    final sb = StringBuffer();
    for (final ch in text.runes) {
      if (ch >= 0xFF10 && ch <= 0xFF19) {
        sb.writeCharCode(ch - 0xFEE0);
      } else {
        sb.writeCharCode(ch);
      }
    }
    return sb.toString();
  }

  // ---- 头部 ----------------------------------------------------------------

  /// 找到第一个非 `[...]` 标签的字符位置，即着法区起点。
  int _findMovetextStart(String text) {
    var i = 0;
    while (i < text.length) {
      while (i < text.length && _isWhitespace(text.codeUnitAt(i))) {
        i++;
      }
      if (i >= text.length) return i;
      if (text[i] != '[') return i;
      var depth = 0;
      while (i < text.length) {
        final ch = text[i];
        if (ch == '[') {
          depth++;
        } else if (ch == ']') {
          depth--;
          if (depth == 0) {
            i++;
            break;
          }
        }
        i++;
      }
    }
    return i;
  }

  /// 解析全部标签对为小写 key → value 的映射。
  Map<String, String> _parseHeaders(String header) {
    final tags = <String, String>{};
    final tagRegex = RegExp(r'\[(\w+)\s+"((?:[^"\\]|\\.)*)"\]');
    for (final match in tagRegex.allMatches(header)) {
      tags[match.group(1)!.toLowerCase()] = match.group(2)!;
    }
    return tags;
  }

  /// 从 FEN 第二段读取走子方（w/b）；无 FEN 返回 null。
  Side? _sideFromFen(String? fen) {
    if (fen == null || fen.trim().isEmpty) return null;
    final parts = fen.trim().split(RegExp(r'\s+'));
    if (parts.length < 2) return null;
    return parts[1] == 'b' ? Side.black : Side.red;
  }

  // ---- 着法区 --------------------------------------------------------------

  /// 解析着法区，按回合结构提取主线着法与注释。
  ///
  /// 回合约定：
  /// - `N.`（数字 + 一个点）：第 N 回合开始，下一着为**红方**；
  /// - `N...`（数字 + 三个点）：该回合从**黑方**着法开始（常见于
  ///   FEN 指定黑方先行，或从某局面开始只记录黑方应答）；
  /// - 一个回合通常为「红着 + 黑着」，但允许只有红着（如红方将死后
  ///   终局，没有黑方应答）或只有黑着（`N...` 起始）；
  /// - 下一个回合标记会**重置**预期走子方，因此不能仅靠"红黑交替"推断。
  List<ParsedMove> _parseMovetext(String text, Side startingSide) {
    final moves = <ParsedMove>[];
    final pendingComments = <String>[];
    var parenDepth = 0;
    var i = 0;

    // 当前回合标记声明的下一着走子方；null 表示尚未遇到回合标记，
    // 此时按 FEN 起始轮次推断，之后红黑交替。
    Side? expected;

    String takeComment() {
      if (pendingComments.isEmpty) return '';
      final joined = pendingComments.join('\n\n');
      pendingComments.clear();
      return joined;
    }

    void emitMove(String token) {
      final side = expected ?? (moves.isEmpty ? startingSide : _flip(moves.last.side ?? startingSide));
      final comment = takeComment();
      moves.add(ParsedMove(
        moveText: token,
        side: side,
        comment: comment.isEmpty ? null : comment,
      ));
      // 同一回合内红→黑交替；遇到新回合标记时会被重置
      expected = _flip(side);
    }

    while (i < text.length) {
      final ch = text[i];

      // 变着 (...)：按括号深度整体跳过（当前不解析为分支）
      if (ch == '(') {
        parenDepth++;
        i++;
        continue;
      }
      if (ch == ')') {
        if (parenDepth > 0) parenDepth--;
        i++;
        continue;
      }
      if (parenDepth > 0) {
        i++;
        continue;
      }

      // 注释 {...}：附加到下一个着法
      if (ch == '{') {
        i++;
        final buf = StringBuffer();
        while (i < text.length && text[i] != '}') {
          buf.write(text[i]);
          i++;
        }
        if (i < text.length) i++; // 跳过 '}'
        final t = buf.toString().trim();
        if (t.isNotEmpty) pendingComments.add(t);
        continue;
      }

      // 行注释 ;...（部分 PGN 方言）
      if (ch == ';') {
        while (i < text.length && text[i] != '\n') {
          i++;
        }
        continue;
      }

      // 空白
      if (_isWhitespace(ch.codeUnitAt(0))) {
        i++;
        continue;
      }

      // 数字开头：结果标记 或 回合号
      if (_isDigit(ch.codeUnitAt(0))) {
        final rest = text.substring(i);
        if (rest.startsWith('1/2-1/2') ||
            rest.startsWith('1-0') ||
            rest.startsWith('0-1')) {
          while (i < text.length && !_isWhitespace(text.codeUnitAt(i))) {
            i++;
          }
          continue;
        }
        // 回合标记：连续数字 + 一个或多个点
        var j = i;
        while (j < text.length && _isDigit(text.codeUnitAt(j))) {
          j++;
        }
        var dots = 0;
        while (j < text.length && text[j] == '.') {
          dots++;
          j++;
        }
        if (dots > 0) {
          // 一个点 = 红方回合；三个点 = 黑方先行的回合
          expected = dots >= 3 ? Side.black : Side.red;
        }
        i = j;
        continue;
      }

      // 独立结果星号
      if (ch == '*') {
        i++;
        continue;
      }

      // NAG：$12 形式
      if (ch == r'$') {
        i++;
        while (i < text.length && _isDigit(text.codeUnitAt(i))) {
          i++;
        }
        continue;
      }

      // UCI/ICCS 着法：[a-i] 数字 [a-i] 数字
      if (_isFileLetter(ch) &&
          i + 3 < text.length &&
          _isDigit(text.codeUnitAt(i + 1)) &&
          _isFileLetter(text[i + 2]) &&
          _isDigit(text.codeUnitAt(i + 3))) {
        emitMove(text.substring(i, i + 4));
        i += 4;
        continue;
      }

      // 中文招法：首字符为棋子名或前后消歧字，取连续 4 个字符
      if (ChineseNotation.looksLikeChinese(ch) && i + 3 < text.length) {
        final token = text.substring(i, i + 4);
        if (ChineseNotation.isValidToken(token)) {
          emitMove(token);
          i += 4;

          continue;
        }
      }

      // 其它字符（!、? 等 NAG 符号、标点）：跳过
      i++;
    }

    return moves;
  }

  Side _flip(Side s) => s == Side.red ? Side.black : Side.red;

  bool _isWhitespace(int code) =>
      code == 0x20 || code == 0x09 || code == 0x0A || code == 0x0D;
  bool _isDigit(int code) => code >= 0x30 && code <= 0x39;
  bool _isFileLetter(String ch) {
    if (ch.isEmpty) return false;
    final c = ch.codeUnitAt(0);
    return c >= 0x61 && c <= 0x69; // a..i
  }
}
