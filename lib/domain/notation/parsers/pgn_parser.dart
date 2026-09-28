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
/// - 注释：`{...}`（保留到对应步；着法区开头的注释为开局评注）；
/// - 变着 `(...)`：按标准 RAV 语义解析——括号线**替代紧邻其前的那一着**，
///   递归解析为 [ParsedMove.branches] / [ParsedGame.rootBranches]；
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
    final cursor = _Cursor(movetext);
    final main = _parseLine(cursor, startingSide, topLevel: true);
    if (main.moves.isEmpty && main.headBranches.isEmpty) {
      throw NotationParseException(
        'PGN 棋谱没有有效的着法',
        cause: 'filename=$filename',
      );
    }
    return ParsedGame(
      info: info,
      startingFen: fen,
      startingSide: startingSide,
      rootComment: cursor.rootComment,
      rootBranches: main.headBranches,
      moves: main.moves,
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

    if (game.moves.isEmpty) {
      // 无主线只有根变着（纯局面 + 变着的罕见棋谱）：逐条输出
      for (final branch in game.rootBranches) {
        tokens.add('(');
        _appendLine(tokens, branch, game.startingSide, 1);
        tokens.add(')');
      }
    } else {
      // 根变着（替代主线首着）按标准 RAV 写在首着之后，
      // 由 [headBranches] 参数传给 _appendLine
      _appendLine(tokens, game.moves, game.startingSide, 1, game.rootBranches);
    }

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
  ///
  /// 变着输出遵循标准 RAV 语义——`( … )` 替代**紧邻其前的那一着**：
  /// 本应用 [ParsedMove.branches] 语义为「替代主线下一着」，因此
  /// `line[i-1].branches` 写在 `line[i]` 记号之后；[headBranches] 为
  /// 替代本线首着的变着（顶层即 [ParsedGame.rootBranches]）。
  /// 线末着的 branches（替代不存在的下一着）写在着法区末尾，读入时
  /// 会被挂为替代末着——「终局局面仍有变着」属罕见边界，接受轻微错位。
  void _appendLine(
    List<String> out,
    List<ParsedMove> line,
    Side startSide,
    int startRound, [
    List<List<ParsedMove>> headBranches = const [],
  ]) {
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

      // 本着之后输出「替代本着的变着」（标准 RAV 语义）：
      // 首着的替代变着来自 [headBranches]，其余来自上一着的 branches
      // （branches 语义为替代其下一着）。
      final variations = i == 0 ? headBranches : line[i - 1].branches;
      for (final branch in variations) {
        if (branch.isEmpty) continue;
        out.add('(');
        // 变着首着与本着同走子方、同回合号
        _appendLine(out, branch, side, round);
        out.add(')');
      }

      if (side == Side.black) round++;
    }

    // 末着的 branches：替代「不存在的下一着」，标准 RAV 无安放位置，
    // 只能写在线路末尾（见方法注释的边界说明）。
    // 此时 round 已推进到下一着的回合号，变着首着与下一着同方同回合。
    for (final branch in line.last.branches) {
      if (branch.isEmpty) continue;
      out.add('(');
      final lastSide = line.last.side ?? startSide;
      _appendLine(out, branch, _flip(lastSide), round);
      out.add(')');
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

  /// 递归解析一条着法线（主线或括号变着线）。
  ///
  /// 返回 (moves, headBranches)：moves 为本线着法序列，headBranches 为
  /// 替代本线**首着**的变着列表（顶层即 [ParsedGame.rootBranches]）。
  ///
  /// 变着按标准 RAV 语义解析：`( … )` 替代**紧邻其前的那一着**，即
  /// 挂到前一着的前一着 [ParsedMove.branches] 上（branches 语义为
  /// 「替代下一着」）；前一着为本线首着时挂入 headBranches。
  ///
  /// [startSide] 为本线首着的走子方（变着线即被替代着的走子方）。
  /// 遇到 `)` 时结束本线返回；顶层遇到不匹配的 `)` 直接跳过。
  ({List<ParsedMove> moves, List<List<ParsedMove>> headBranches}) _parseLine(
    _Cursor c,
    Side startSide, {
    bool topLevel = false,
  }) {
    final moves = <ParsedMove>[];
    final headBranches = <List<ParsedMove>>[];

    // 当前回合标记声明的下一着走子方；null 表示尚未遇到回合标记，
    // 此时按起始走子方推断，之后红黑交替。
    Side? expected;

    String takeComment() {
      if (c.pendingComments.isEmpty) return '';
      final joined = c.pendingComments.join('\n\n');
      c.pendingComments.clear();
      return joined;
    }

    void emitMove(String token) {
      final side = expected ??
          (moves.isEmpty ? startSide : _flip(moves.last.side ?? startSide));
      var comment = takeComment();
      if (topLevel && moves.isEmpty && headBranches.isEmpty) {
        // 顶层着法区开头（首着之前）的注释 = 开局评注
        if (comment.isNotEmpty) c.rootComment = comment;
        comment = '';
      }
      moves.add(ParsedMove(
        moveText: token,
        side: side,
        comment: comment.isEmpty ? null : comment,
        // 显式可变列表：后续遇到的变着会追加进来
        branches: <List<ParsedMove>>[],
      ));
      // 同一回合内红→黑交替；遇到新回合标记时会被重置
      expected = _flip(side);
    }

    /// 线路结束时仍遗留的注释（线尾着法之后的 {…}）：挂到本线最后
    /// 一着。兼容其它软件「注释写在着法之后表示对该着的评注」的习惯。
    void flushTailComment() {
      if (c.pendingComments.isEmpty || moves.isEmpty) return;
      final tail = takeComment();
      final last = moves.removeLast();
      moves.add(ParsedMove(
        moveText: last.moveText,
        side: last.side,
        comment: last.comment == null ? tail : '${last.comment}\n\n$tail',
        branches: last.branches,
        notation: last.notation,
      ));
    }

    final text = c.text;
    while (c.i < text.length) {
      final ch = text[c.i];

      // 变着 (...)：递归解析为「替代紧邻前一着」的分支线
      if (ch == '(') {
        c.i++;
        // 变着首着的走子方 = 被替代着（本线最后一着）的走子方；
        // 本线还没有着法时，变着替代本线首着，走子方同首着
        final replacedSide = moves.isEmpty
            ? startSide
            : (moves.last.side ?? startSide);
        final sub = _parseLine(c, replacedSide);
        // 挂载点：替代本线最后一着 → 挂到其前一着的 branches；
        // 本线不足两着时挂入 headBranches（替代本线首着）。
        // sub.headBranches 与本变着同级（都替代同一着），一并挂载。
        final List<List<ParsedMove>> target =
            moves.length >= 2 ? moves[moves.length - 2].branches : headBranches;
        if (sub.moves.isNotEmpty) target.add(sub.moves);
        target.addAll(sub.headBranches);
        continue;
      }
      if (ch == ')') {
        c.i++;
        if (!topLevel) {
          flushTailComment();
          return (moves: moves, headBranches: headBranches);
        }
        continue; // 顶层不匹配的右括号：跳过
      }

      // 注释 {...}：附加到下一个着法
      if (ch == '{') {
        c.i++;
        final buf = StringBuffer();
        while (c.i < text.length && text[c.i] != '}') {
          buf.write(text[c.i]);
          c.i++;
        }
        if (c.i < text.length) c.i++; // 跳过 '}'
        final t = buf.toString().trim();
        if (t.isNotEmpty) c.pendingComments.add(t);
        continue;
      }

      // 行注释 ;...（部分 PGN 方言）
      if (ch == ';') {
        while (c.i < text.length && text[c.i] != '\n') {
          c.i++;
        }
        continue;
      }

      // 空白
      if (_isWhitespace(ch.codeUnitAt(0))) {
        c.i++;
        continue;
      }

      // 数字开头：结果标记 或 回合号
      if (_isDigit(ch.codeUnitAt(0))) {
        final rest = text.substring(c.i);
        if (rest.startsWith('1/2-1/2') ||
            rest.startsWith('1-0') ||
            rest.startsWith('0-1')) {
          while (c.i < text.length && !_isWhitespace(text.codeUnitAt(c.i))) {
            c.i++;
          }
          continue;
        }
        // 回合标记：连续数字 + 一个或多个点
        var j = c.i;
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
        c.i = j;
        continue;
      }

      // 独立结果星号
      if (ch == '*') {
        c.i++;
        continue;
      }

      // NAG：$12 形式
      if (ch == r'$') {
        c.i++;
        while (c.i < text.length && _isDigit(text.codeUnitAt(c.i))) {
          c.i++;
        }
        continue;
      }

      // UCI/ICCS 着法：[a-i] 数字 [a-i] 数字
      if (_isFileLetter(ch) &&
          c.i + 3 < text.length &&
          _isDigit(text.codeUnitAt(c.i + 1)) &&
          _isFileLetter(text[c.i + 2]) &&
          _isDigit(text.codeUnitAt(c.i + 3))) {
        emitMove(text.substring(c.i, c.i + 4));
        c.i += 4;
        continue;
      }

      // 中文招法：首字符为棋子名或前后消歧字，取连续 4 个字符
      if (ChineseNotation.looksLikeChinese(ch) && c.i + 3 < text.length) {
        final token = text.substring(c.i, c.i + 4);
        if (ChineseNotation.isValidToken(token)) {
          emitMove(token);
          c.i += 4;

          continue;
        }
      }

      // 其它字符（!、? 等 NAG 符号、标点）：跳过
      c.i++;
    }

    flushTailComment();
    return (moves: moves, headBranches: headBranches);
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

/// PGN 着法区扫描游标：在变着线递归解析间共享文本位置与待挂注释。
class _Cursor {
  _Cursor(this.text);

  final String text;
  int i = 0;

  /// 已扫描到、尚未附着到着法的注释（附加到下一个着法）。
  final List<String> pendingComments = [];

  /// 顶层着法区开头（首着之前）的注释 = 开局评注。
  String? rootComment;
}
