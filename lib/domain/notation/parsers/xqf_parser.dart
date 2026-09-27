import 'dart:developer' show log;
import 'dart:typed_data';

import 'package:gbk_codec/gbk_codec.dart';

import 'notation_exception.dart';
import 'notation_parser.dart';
import 'parsed_game.dart';
import '../../models/piece.dart' show Side;

/// XQF（象棋演播室 XQStudio）棋谱文件解析器。
///
/// 支持：
/// - 文件头校验、加密参数解析与解密密钥推导；
/// - 由 32 枚棋子原始位置计算开局 FEN（含让子/排局等非标准局面）；
/// - 着法段的二叉树遍历：通过 `hasNext`（续着）/`hasChange`（变着）标志
///   还原完整的多分支着法树，再拍扁为「主线 + 各步 branches + 起始
///   局面 rootBranches」供下游使用。
///
/// 文本字段（标题、对弈方、注释等）在 XQF 中为 GBK 编码；Dart 标准库
/// 不含 GBK 解码器，当前用 latin1 兜底（ASCII 正确、中文显示为乱码但不
/// 崩溃）。若需正确中文，引入 `gbk_codec` 三方包后替换 [_decodeText]
/// 即可——这是一处单点改动。
class XqfParser implements NotationParser {
  const XqfParser();

  @override
  String get primaryExtension => 'xqf';

  @override
  ParsedGame parse(List<int> bytes, {String? filename}) {
    if (bytes.length < 1024) {
      throw NotationParseException('XQF 文件过短，不是有效的棋谱文件',
          cause: 'len=${bytes.length}');
    }
    // 文件头标记 'X','Q'
    if (bytes[0] != 0x58 || bytes[1] != 0x51) {
      throw NotationParseException('XQF 文件头标记无效（应以 XQ 开头）',
          cause: 'filename=$filename');
    }

    final data = Uint8List.fromList(bytes);
    try {
      final header = _parseHeader(data);
      final key = _calculateKey(header);
      final fen = _calculateFen(header, key);
      final root = _parseMoveTree(data, header, key);
      return _toParsedGame(header, fen, root);
    } on NotationParseException {
      rethrow;
    } catch (e, s) {
      log("XQF 解析失败：$e, $s");
      throw NotationParseException('XQF 解析失败：$e', cause: e);
    }
  }

  // ---- 写入（解析的逆操作） ------------------------------------------------

  /// 标准开局 FEN（起始 FEN 为空时使用）。
  static const String _standardFen =
      'rnbakabnr/9/1c5c1/p1p1p1p1p/9/9/P1P1P1P1P/1C5C1/9/RNBAKABNR w - - 0 1';

  /// 文件头总长度：着法段从 0x400 开始。
  static const int _headerSize = 1024;

  @override
  List<int> write(ParsedGame game) {
    // 输出固定使用 XQF 1.0（version=10）——该版本着法段与棋子坐标
    // 均不加密，现有 parse() 可直接读回，兼容象棋演播室系列软件。
    final header = Uint8List(_headerSize);
    header[0] = 0x58; // 'X'
    header[1] = 0x51; // 'Q'
    header[2] = 10; // version

    // 32 枚棋子位置
    _writePiecePositions(header, game.startingFen ?? _standardFen);

    // 轮次与结果
    header[50] = game.startingSide == Side.black ? 1 : 0;
    header[51] = switch (game.info.result) {
      '1-0' => 1,
      '0-1' => 2,
      '1/2-1/2' => 3,
      _ => 0,
    };

    // 文本字段（GBK，长度前缀）
    _writeHeaderString(header, 80, 128, game.info.note ?? '');
    _writeHeaderString(header, 208, 64, game.info.event ?? '');
    _writeHeaderString(header, 272, 16, game.info.date ?? '');
    _writeHeaderString(header, 288, 16, game.info.site ?? '');
    _writeHeaderString(header, 304, 16, game.info.red ?? '');
    _writeHeaderString(header, 320, 16, game.info.black ?? '');

    // 着法树：根节点 + 子节点（第 0 节点承载开局评注）
    final root = _buildWriteTree(game);
    final moveBytes = BytesBuilder();
    _writeNode(moveBytes, root,
        isRoot: true,
        hasNext: root.children.isNotEmpty,
        hasChange: root.children.length > 1);
    if (root.children.isNotEmpty) {
      _writeChildren(moveBytes, root.children);
    }

    final out = BytesBuilder()
      ..add(header)
      ..add(moveBytes.toBytes());
    return out.toBytes();
  }

  /// 从 FEN 推导 32 枚棋子位置并写入文件头 16..47。
  ///
  /// 槽位顺序固定为 [_fenPieces]；同类棋子的多个槽位可互换（FEN 字符
  /// 相同）。棋盘上缺失的棋子写 0xFF（>= 90，解析时视为不存在）。
  void _writePiecePositions(Uint8List h, String fen) {
    final placement = fen.trim().split(RegExp(r'\s+')).first;
    // 展开为 90 格字符列表（row 0 = 黑方顶部，与 FEN 行序一致）
    final cells = <String>[];
    for (final ch in placement.split('')) {
      if (ch == '/') continue;
      if (RegExp(r'[1-9]').hasMatch(ch)) {
        cells.addAll(List.filled(int.parse(ch), ''));
      } else {
        cells.add(ch);
      }
    }
    if (cells.length != 90) {
      throw NotationParseException('XQF 写入失败：起始 FEN 不合法');
    }

    for (var i = 0; i < 32; i++) {
      final target = _fenPieces[i];
      var pos = 0xFF;
      final idx = cells.indexWhere((c) => c == target);
      if (idx >= 0) {
        final row = idx ~/ 9;
        final col = idx % 9;
        cells[idx] = ''; // 已占用
        pos = col * 10 + (9 - row);
      }
      h[16 + i] = pos;
    }
  }

  /// 写一个「长度前缀 + GBK 内容（剩余补零）」的文件头文本字段。
  void _writeHeaderString(
      Uint8List h, int offset, int maxLen, String text) {
    final t = text.trim();
    if (t.isEmpty) {
      h[offset] = 0;
      return;
    }
    List<int> gb;
    try {
      gb = gbk_bytes.encode(t);
    } catch (_) {
      gb = gbk_bytes.encode(t.replaceAll(RegExp(r'[^\x00-\x7F一-鿿]'), '?'));
    }
    final len = gb.length > maxLen - 1 ? maxLen - 1 : gb.length;
    h[offset] = len;
    for (var i = 0; i < len; i++) {
      h[offset + 1 + i] = gb[i] & 0xFF;
    }
  }

  /// 把 [ParsedGame] 的主线/根分支/各步变着构建为写入用着法树。
  ///
  /// 每个节点 children[0] 为主线续着，其余为同位变着，与解析端
  /// `_flattenLine` 的拍扁方式互逆。
  _WNode _buildWriteTree(ParsedGame game) {
    final root = _WNode(move: '', remark: game.rootComment);
    if (game.moves.isNotEmpty) {
      root.children.add(_buildChain(game.moves, 0));
    }
    for (final branch in game.rootBranches) {
      if (branch.isNotEmpty) root.children.add(_buildChain(branch, 0));
    }
    return root;
  }

  /// 构建一条着法线从 [i] 起的节点；i+1 为主线续着（置于 children[0]），
  /// 该步自带的 branches 为同位变着。
  _WNode _buildChain(List<ParsedMove> line, int i) {
    final m = line[i];
    final uci = _requireUci(m.moveText);
    final node = _WNode(
      move: uci,
      remark: (m.comment?.trim().isNotEmpty ?? false) ? m.comment!.trim() : '',
    );
    // 先放变着，再把主线续着插到首位
    for (final b in m.branches) {
      if (b.isNotEmpty) node.children.add(_buildChain(b, 0));
    }
    if (i + 1 < line.length) {
      node.children.insert(0, _buildChain(line, i + 1));
    }
    return node;
  }

  /// 校验并规范化为 ICCS/UCI 坐标串（XQF 着法段只存坐标）。
  String _requireUci(String text) {
    final t = text.trim();
    final uci = RegExp(r'^[a-i][0-9][a-i][0-9]$');
    if (!uci.hasMatch(t)) {
      throw NotationParseException(
        'XQF 写入失败：着法必须是 UCI 坐标（如 h2e2），实际为「$t」',
      );
    }
    return t;
  }

  /// DFS 写一层兄弟节点。
  ///
  /// flag 规则（与解析端 fork 栈互逆）：
  /// - hasNext：本节点有续着（children 非空）；
  /// - hasChange：本节点之后还有同父兄弟（不是最后一个孩子）。
  void _writeChildren(BytesBuilder out, List<_WNode> children) {
    for (var i = 0; i < children.length; i++) {
      final node = children[i];
      final hasNext = node.children.isNotEmpty;
      final hasChange = i < children.length - 1;
      _writeNode(out, node, isRoot: false, hasNext: hasNext, hasChange: hasChange);
      if (hasNext) _writeChildren(out, node.children);
    }
  }

  /// 写单个着法节点（8 字节头 + GBK 注释），v10 不加密。
  void _writeNode(
    BytesBuilder out,
    _WNode node, {
    required bool isRoot,
    required bool hasNext,
    required bool hasChange,
  }) {
    if (isRoot) {
      // 根节点着法字节无意义，置 0
      out.addByte(0);
      out.addByte(0);
    } else {
      final pf = _iccsToPos(node.move.substring(0, 2));
      final pt = _iccsToPos(node.move.substring(2, 4));
      out.addByte((pf + 24) & 0xFF);
      out.addByte((pt + 32) & 0xFF);
    }
    // v10：高 4 位 hasNext，低 4 位 hasChange
    out.addByte((hasNext ? 0xF0 : 0x00) | (hasChange ? 0x0F : 0x00));
    out.addByte(0);

    final remark = node.remark;
    List<int> commentBytes = const [];
    if (remark != null && remark.isNotEmpty) {
      try {
        commentBytes = gbk_bytes.encode(remark);
      } catch (_) {
        commentBytes = const [];
      }
    }
    final len = commentBytes.length;
    out.addByte(len & 0xFF);
    out.addByte((len >> 8) & 0xFF);
    out.addByte((len >> 16) & 0xFF);
    out.addByte((len >> 24) & 0xFF);
    out.add(commentBytes);
  }

  /// ICCS 坐标（如 a0）转 XQF 位置（x*10+y）。
  int _iccsToPos(String iccs) {
    final x = iccs.codeUnitAt(0) - 0x61;
    final y = int.parse(iccs[1]);
    return x * 10 + y;
  }

  // ---- 文件头 -------------------------------------------------------------

  /// 32 枚棋子的 FEN 表示顺序（红方车马相士帅士相马车炮炮兵×5 + 黑方同序）。
  static const String _fenPieces = 'RNBAKABNRCCPPPPPrnbakabnrccppppp';

  /// XQF 加密种子（版权串）。
  static const String _seed = '[(C) Copyright Mr. Dong Shiwei.]';

  _XqfHeader _parseHeader(Uint8List b) {
    final h = _XqfHeader()
      ..version = b[2] & 0xFF
      ..keyMask = b[3] & 0xFF
      ..keyOr = [b[8], b[9], b[10], b[11]]
      ..keySum = b[12] & 0xFF
      ..keyXYp = b[13] & 0xFF
      ..keyXYf = b[14] & 0xFF
      ..keyXYt = b[15] & 0xFF;
    h.qiziXY = Uint8List.sublistView(b, 16, 48);
    h.playStepNo = (b[49] & 0xFF) * 256 + (b[48] & 0xFF);
    h.whoPlay = b[50] & 0xFF;
    h.playResult = b[51] & 0xFF;
    h.type = b[64] & 0xFF;
    h.title = _readString(b, 80, 128);
    h.matchName = _readString(b, 208, 64);
    h.matchTime = _readString(b, 272, 16);
    h.matchAddr = _readString(b, 288, 16);
    h.redPlayer = _readString(b, 304, 16);
    h.blkPlayer = _readString(b, 320, 16);
    h.timeRule = _readString(b, 336, 64);
    h.redTime = _readString(b, 400, 16);
    h.blkTime = _readString(b, 416, 16);
    h.rmkWriter = _readString(b, 464, 16);
    h.author = _readString(b, 480, 16);
    return h;
  }

  /// 从 [offset] 起读取「长度前缀 + GBK 内容」字符串。
  /// 第一字节为长度，其后为内容，遇 0 提前终止。
  String _readString(Uint8List b, int offset, int maxLen) {
    final length = b[offset] & 0xFF;
    if (length == 0 || length > maxLen - 1) return '';
    var actual = 0;
    for (var i = 0; i < length && i < maxLen - 1; i++) {
      if (b[offset + 1 + i] != 0) {
        actual++;
      } else {
        break;
      }
    }
    if (actual == 0) return '';
    return _decodeText(b.sublist(offset + 1, offset + 1 + actual));
  }

  // ---- 密钥 --------------------------------------------------------------

  _XqfKey _calculateKey(_XqfHeader h) {
    final k = _XqfKey();
    // XQF 1.0（version <= 10）不加密
    if (h.version <= 10) return k;

    k.xYp = ((h.keyXYp * h.keyXYp * 54 + 221) * h.keyXYp) & 0xFF;
    k.xYf = ((h.keyXYf * h.keyXYf * 54 + 221) * k.xYp) & 0xFF;
    k.xYt = ((h.keyXYt * h.keyXYt * 54 + 221) * k.xYf) & 0xFF;
    k.rmk = (((h.keySum * 256 + h.keyXYp) % 32000) + 767) & 0xFFFF;

    final fKey = <int>[
      (h.keySum & h.keyMask) | (h.keyOr[0] & 0xFF),
      (h.keyXYp & h.keyMask) | (h.keyOr[1] & 0xFF),
      (h.keyXYf & h.keyMask) | (h.keyOr[2] & 0xFF),
      (h.keyXYt & h.keyMask) | (h.keyOr[3] & 0xFF),
    ];
    for (var i = 0; i < 32; i++) {
      k.f32[i] = fKey[i % 4] & _seed.codeUnitAt(i);
    }
    return k;
  }

  // ---- FEN ---------------------------------------------------------------

  String _calculateFen(_XqfHeader h, _XqfKey k) {
    // 10 行 × 9 列，初始填 '*' 表示空
    final arr = List<int>.filled(90, '*'.codeUnitAt(0));
    for (var i = 0; i < 32; i++) {
      final int pieceKey;
      final int piecePos;
      if (h.version > 10) {
        pieceKey = (k.xYp + i + 1) & 31;
        piecePos = ((h.qiziXY[i] & 0xFF) - k.xYp) & 0xFF;
      } else {
        pieceKey = i;
        piecePos = h.qiziXY[i] & 0xFF;
      }
      if (piecePos < 90) {
        final x = piecePos ~/ 10;
        final y = 9 - (piecePos % 10);
        final idx = y * 9 + x;
        if (idx >= 0 && idx < 90) {
          arr[idx] = _fenPieces.codeUnitAt(pieceKey);
        }
      }
    }

    final sb = StringBuffer();
    for (var row = 0; row < 10; row++) {
      var empty = 0;
      for (var col = 0; col < 9; col++) {
        final c = arr[row * 9 + col];
        if (c == '*'.codeUnitAt(0)) {
          empty++;
        } else {
          if (empty > 0) {
            sb.write(empty);
            empty = 0;
          }
          sb.writeCharCode(c);
        }
      }
      if (empty > 0) sb.write(empty);
      if (row < 9) sb.write('/');
    }
    // 轮次与步数（参考实现的附加段）
    sb.write(h.whoPlay == 1 ? ' b - - 0 ' : ' w - - 0 ');
    sb.write(h.playStepNo > 0 ? (h.playStepNo >> 1) : 1);
    return sb.toString();
  }

  // ---- 着法树 ------------------------------------------------------------

  /// 解析着法段为内部着法树（根节点为「开始局面」，无 move）。
  _TreeNode _parseMoveTree(Uint8List b, _XqfHeader h, _XqfKey k) {
    final root = _TreeNode(move: '', remark: '');

    if (b.length <= 1024) return root;

    // 着法段从 0x400(1024) 开始，整体解密
    final n = b.length - 1024;
    final decode = Uint8List(n);
    for (var i = 0; i < n; i++) {
      if (h.version > 10) {
        decode[i] = ((b[1024 + i] & 0xFF) - k.f32[i % 32]) & 0xFF;
      } else {
        decode[i] = b[1024 + i];
      }
    }

    final forkStack = <_TreeNode>[];
    var parent = root;
    var pos = 0;

    while (pos < decode.length) {
      if (pos + 8 > decode.length) break;

      var commentLen = 0;
      var nextOffset = 4; // 不含注释时的 8 字节节点中后 4 字节为注释长度字段
      bool hasNext;
      bool hasChange;

      if (h.version > 10) {
        hasNext = (decode[pos + 2] & 0x80) != 0;
        hasChange = (decode[pos + 2] & 0x40) != 0;
        if ((decode[pos + 2] & 0x20) != 0) {
          commentLen = _readInt32(decode, pos + 4) - k.rmk;
          if (commentLen < 0) commentLen = 0;
          nextOffset = commentLen + 8;
        }
      } else {
        hasNext = (decode[pos + 2] & 0xF0) != 0;
        hasChange = (decode[pos + 2] & 0x0F) != 0;
        commentLen = _readInt32(decode, pos + 4);
        nextOffset = commentLen + 8;
      }

      // 读取注释（GBK）
      var comment = '';
      if (commentLen > 0 && pos + 8 + commentLen <= decode.length) {
        comment = _decodeText(
          decode.sublist(pos + 8, pos + 8 + commentLen),
        );
      }

      // 第 0 步是空着法，只承载开始局面注释
      if (pos == 0) {
        if (comment.isNotEmpty) root.remark = comment;
        pos += hasNext ? nextOffset : decode.length;
        continue;
      }

      // 解析着法坐标（解密后减偏移）
      final pf = ((decode[pos] & 0xFF) - 24 - k.xYf) & 0xFF;
      final pt = ((decode[pos + 1] & 0xFF) - 32 - k.xYt) & 0xFF;
      final move = _toIccs(pf, pt);

      final step = _TreeNode(move: move, remark: comment);
      parent.children.add(step);

      if (hasNext) {
        if (hasChange) {
          // 本步既有续着又有变着：记住当前 fork，之后会回到此父节点加兄弟
          forkStack.add(parent);
        }
        parent = step; // 下一着是本步的子
      } else {
        if (!hasChange) {
          // 既无续着也无变着：本支线到此为止，回到上一个 fork
          if (forkStack.isNotEmpty) {
            parent = forkStack.removeLast();
          }
        }
        // 有变着无续着：下一节点是同父兄弟，parent 不变
      }

      pos += nextOffset;
    }

    return root;
  }

  int _readInt32(Uint8List d, int offset) {
    if (offset + 4 > d.length) return 0;
    return (d[offset] & 0xFF) |
        ((d[offset + 1] & 0xFF) << 8) |
        ((d[offset + 2] & 0xFF) << 16) |
        ((d[offset + 3] & 0xFF) << 24);
  }

  /// XQF 坐标（X*10+Y，原点(0,0)在左下角）转 ICCS 串（如 a0a1）。
  String _toIccs(int fromPos, int toPos) {
    var fx = fromPos ~/ 10;
    var fy = fromPos % 10;
    var tx = toPos ~/ 10;
    var ty = toPos % 10;
    fx = fx.clamp(0, 8);
    fy = fy.clamp(0, 9);
    tx = tx.clamp(0, 8);
    ty = ty.clamp(0, 9);
    return '${String.fromCharCode(0x61 + fx)}$fy'
        '${String.fromCharCode(0x61 + tx)}$ty';
  }

  // ---- 拍扁为 ParsedGame ---------------------------------------------------

  _Side _flip(_Side s) => s == _Side.red ? _Side.black : _Side.red;

  ParsedGame _toParsedGame(_XqfHeader h, String fen, _TreeNode root) {
    final startSide = h.whoPlay == 1 ? Side.black : Side.red;
    final startEnum = h.whoPlay == 1 ? _Side.black : _Side.red;

    final moves = root.children.isEmpty
        ? <ParsedMove>[]
        : _flattenLine(root.children[0], startEnum);
    final rootBranches = root.children
        .skip(1)
        .map((sib) => _flattenLine(sib, startEnum))
        .toList();

    String? result;
    switch (h.playResult) {
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

    // 标题归入 note（GameInfo 无独立标题字段）；开局评注单独走 rootComment，
    // 载入时挂在棋谱树根节点的局面注释上。
    final note = (h.title?.isEmpty ?? true) ? null : h.title;
    final rootComment =
        (root.remark?.isEmpty ?? true) ? null : root.remark;

    // 注意：不校验 moves 非空。纯局面文件（排局/残局 setup）没有任何着法，
    // 只有文件头里的棋子位置（可能外加开局评注），同样是合法棋谱。

    return ParsedGame(
      info: GameInfo(
        event: (h.matchName?.isEmpty ?? true) ? null : h.matchName,
        site: (h.matchAddr?.isEmpty ?? true) ? null : h.matchAddr,
        date: (h.matchTime?.isEmpty ?? true) ? null : h.matchTime,
        red: (h.redPlayer?.isEmpty ?? true) ? null : h.redPlayer,
        black: (h.blkPlayer?.isEmpty ?? true) ? null : h.blkPlayer,
        result: result,
        note: note,
      ),
      startingFen: fen,
      startingSide: startSide,
      rootComment: rootComment,
      moves: moves,
      rootBranches: rootBranches,
    );
  }

  /// 把一个着法节点拍成一条 [ParsedMove] 序列（主线沿 children[0] 走），
  /// 其余 children 作为本步的变着（递归）。
  ///
  /// [side] 为走到 [node] 这步时该谁走子；用于填充 [ParsedMove.side]
  /// 供回放校验回合一致性。
  List<ParsedMove> _flattenLine(_TreeNode node, _Side side) {
    final pm = ParsedMove(
      moveText: node.move,
      side: side == _Side.red ? Side.red : Side.black,
      comment: (node.remark?.isEmpty ?? true) ? null : node.remark,
      branches: node.children
          .skip(1)
          .map((sib) => _flattenLine(sib, _flip(side)))
          .toList(),
    );
    if (node.children.isEmpty) return [pm];
    return [pm, ..._flattenLine(node.children[0], _flip(side))];
  }

  // ---- 文本解码 ------------------------------------------------------------

  /// 解码 GBK 文本。XQF 的所有文本字段（标题、对弈方、注释等）均为
  /// GBK 编码。注意必须用 `gbk_bytes`（2 字节配对查表），而非同包的
  /// `gbk`（单字节查表，中文会错成 "ÖÐ" 之类）。
  String _decodeText(List<int> bytes) {
    if (bytes.isEmpty) return '';
    return gbk_bytes.decode(bytes).trim();
  }
}

// ---- 内部辅助结构 -----------------------------------------------------------

class _XqfHeader {
  late int version;
  late int keyMask;
  late List<int> keyOr;
  late int keySum;
  late int keyXYp;
  late int keyXYf;
  late int keyXYt;
  late Uint8List qiziXY;
  late int playStepNo;
  late int whoPlay;
  late int playResult;
  late int type;
  String? title;
  String? matchName;
  String? matchTime;
  String? matchAddr;
  String? redPlayer;
  String? blkPlayer;
  String? timeRule;
  String? redTime;
  String? blkTime;
  String? rmkWriter;
  String? author;
}

class _XqfKey {
  final List<int> f32 = List<int>.filled(32, 0);
  int xYp = 0;
  int xYf = 0;
  int xYt = 0;
  int rmk = 0;
}

/// 内部着法树节点（对应 Java 的 ManualRecord，只保留解析所需字段）。
class _TreeNode {
  _TreeNode({required this.move, this.remark});
  String move;
  String? remark;
  final List<_TreeNode> children = [];
}

/// 写入用着法树节点（结构同 [_TreeNode]，语义独立，避免与解析逻辑耦合）。
class _WNode {
  _WNode({required this.move, this.remark});
  final String move;
  final String? remark;
  final List<_WNode> children = [];
}

/// 内部走子方枚举（避免在解析循环里反复与 Flutter 的 Side 互转）。
enum _Side { red, black }
