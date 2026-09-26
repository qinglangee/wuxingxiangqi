import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle, MethodChannel;
import 'package:path_provider/path_provider.dart';

import '../../core/config/app_config.dart';
import '../../core/config/config_manager.dart';
import '../models/piece.dart';
import 'engine_info.dart';

/// 引擎权重文件 pikafish.nnue 未配置或文件不存在。
///
/// 权重不再随包分发，需要用户在引导弹窗中选择文件后，
/// 路径记录到 [EngineConfig.evalFilePath] 并持久化。
class EvalFileMissingException implements Exception {
  @override
  String toString() => '引擎权重文件 pikafish.nnue 未配置或不存在';
}

/// 引擎完成握手但报告权重文件加载失败（典型：Windows 下路径含中文，
/// Pikafish 窄字符接口无法打开）。由启动流程捕获后复制到 ASCII 数据
/// 目录并重试。
class _EvalFileLoadException implements Exception {
  _EvalFileLoadException(this.path);

  final String path;

  @override
  String toString() => '引擎权重文件加载失败: $path';
}

/// 引擎一次思考的结果。
///
/// - [move]：最佳走法 UCI（如 "b2c2"），异常时为 "(none)"；
/// - [pv]：bestmove 之前最后一条首选变化（Principal Variation）的 UCI
///   招法列表，从当前局面的招法开始，无 PV 时为空；
/// - [mate]：引擎报告的杀棋步数（`score mate N`）。正数表示当前走子方
///   N 步内将杀对手，负数表示被将杀；普通分数（cp）时为 null。
typedef EngineBestMove = ({String move, List<String> pv, int? mate});

/// 皮卡鱼(Pikafish) UCI 象棋引擎封装。
///
/// - Windows: 引擎 exe 从 assets 拷贝到临时目录后执行。
/// - Android: 引擎二进制以原生库形式打包在 `jniLibs/arm64-v8a/`
///   （`libpikafish_dotprod.so` 优先，握手失败回退 `libpikafish.so`），
///   安装后由系统释放到可执行的原生库目录。Android 10+ 禁止从应用
///   数据/缓存目录执行代码，必须走原生库路径，无需也不能 chmod。
/// - 权重文件 pikafish.nnue 不随包分发：由用户选择文件，Windows 下
///   ASCII 路径直接使用原文件；路径无法加载时自动复制到应用数据目录
///   （文档目录/wuxingxingqi）后重试，路径记录在
///   [EngineConfig.evalFilePath]；未配置或文件不存在时启动抛出
///   [EvalFileMissingException]。
class PikafishEngine {
  PikafishEngine._();

  static PikafishEngine? _instance;
  static PikafishEngine get instance => _instance ??= PikafishEngine._();

  Process? _process;
  bool _ready = false;

  /// 本次握手中引擎是否报告权重文件加载失败（网络文件未成功加载）。
  bool _evalLoadFailed = false;

  /// 启动握手锁：多个调用方共享同一次启动；失败后允许重试。
  Future<void>? _starting;

  /// 握手信号（每次启动重新创建，避免单例 Completer 只能完成一次的问题）。
  Completer<void>? _uciokCompleter;
  Completer<void>? _readyokCompleter;

  /// 当前等待 bestmove 的请求。
  Completer<EngineBestMove>? _bestMoveCompleter;
  Timer? _hardTimeoutTimer;

  /// 无限分析（go infinite）状态。
  ///
  /// 为 true 时引擎正在做无时限分析；`stop` 后引擎输出的 bestmove
  /// 由 [_analysisCompleter] 接收（分析模式下不存在限时 bestMove 请求）。
  bool _analyzing = false;
  Completer<String>? _analysisCompleter;

  /// 是否正在无限分析中。
  bool get isAnalyzing => _analyzing;

  /// 本次思考周期内最后一条首选（multipv 1）变化与杀棋分数。
  List<String> _lastPv = const [];
  int? _lastMate;

  /// 本次思考周期内各路 MultiPV 候选（key = multipv 序号）。
  final Map<int, EnginePvLine> _pvLines = {};

  /// 本次思考的走子方与起始 FEN（随 bestMove 请求确定）。
  Side _searchSide = Side.red;
  String _searchFen = '';

  /// 引擎搜索信息广播：每条含 pv 的 info 行产生一个快照。
  /// UI（引擎面板）监听它实时显示深度/nps/时间/评分/PV。
  final StreamController<EngineSearchInfo> _infoController =
      StreamController<EngineSearchInfo>.broadcast();
  Stream<EngineSearchInfo> get infoStream => _infoController.stream;

  /// 新一局通知：true 表示已收到 [notifyNewGame] 但本局引擎尚未被调用过
  /// （惰性——引擎进程此时可能还没启动）。第一次 [bestMove] 时发送一次
  /// `ucinewgame`。
  bool _pendingNewGame = false;

  StreamSubscription<String>? _stdoutSub;
  StreamSubscription<String>? _stderrSub;

  /// 是否已启动并完成 UCI 握手。
  bool get isReady => _ready;

  /// 启动引擎进程并完成握手。并发调用共享同一个启动过程。
  Future<void> start() {
    if (_ready) return Future.value();
    return _starting ??= _doStart();
  }

  Future<void> _doStart() async {
    // 权重路径不可用时（典型：Windows 非 ASCII 路径导致窄字符打开失败），
    // 把原文件复制到 ASCII 的应用数据目录后整体重试一次。
    var evalFallbackDone = false;
    while (true) {
      try {
        await _startWithCandidates();
        return;
      } on _EvalFileLoadException catch (e) {
        if (evalFallbackDone || !Platform.isWindows) {
          debugPrint('[pikafish] 权重文件加载失败且无法回退: ${e.path}');
          await _teardownProcess();
          _starting = null;
          rethrow;
        }
        evalFallbackDone = true;
        debugPrint('[pikafish] 权重路径引擎无法加载，复制到数据目录后重试: ${e.path}');
        await _fallbackCopyEvalFile(e.path);
      } catch (e) {
        // 启动失败要彻底清理，使下次 start() 能重新拉起进程
        debugPrint('[pikafish] 启动失败: $e');
        await _teardownProcess();
        _starting = null; // 允许下次调用重新启动
        rethrow;
      }
    }
  }

  /// 用当前配置准备文件并逐个尝试可执行候选，握手全部成功后返回。
  Future<void> _startWithCandidates() async {
    final (:exeCandidates, :dirPath, :evalFilePath) = await _prepareFiles();
    Object? lastError;

    // 逐个尝试可执行文件：Android 上先 dotprod 版本，
    // 握手失败（如 CPU 不支持 dotprod 指令而 SIGILL）则回退通用版本。
    for (final exePath in exeCandidates) {
      try {
        // 工作目录设为临时目录；权重以完整路径传入，不依赖工作目录。
        _process = await Process.start(
          exePath,
          const [],
          workingDirectory: dirPath,
        );
        _evalLoadFailed = false;
        _stdoutSub = _process!.stdout
            .transform(utf8.decoder)
            .transform(const LineSplitter())
            .listen(_onLine);
        _stderrSub = _process!.stderr
            .transform(utf8.decoder)
            .transform(const LineSplitter())
            .listen((line) => debugPrint('[pikafish stderr] $line'));

        // 每次启动使用全新的握手信号
        final uciok = Completer<void>();
        final readyok = Completer<void>();
        _uciokCompleter = uciok;
        _readyokCompleter = readyok;

        // 进程提前退出（典型：dotprod 版在不支持的 CPU 上立即崩溃）
        // 时立刻让握手失败，不必等满超时，快速切换到下一个候选。
        unawaited(_process!.exitCode.then((code) {
          if (!uciok.isCompleted) {
            uciok.completeError(
                StateError('引擎进程提前退出(code=$code): $exePath'));
          }
          if (!readyok.isCompleted) {
            readyok.completeError(
                StateError('引擎进程提前退出(code=$code): $exePath'));
          }
        }));

        // UCI 握手：uci → uciok 后才能 setoption，再 isready → readyok
        _send('uci');
        await uciok.future.timeout(
          const Duration(seconds: 10),
          onTimeout: () => throw TimeoutException('引擎 uci 握手超时'),
        );
        // 显式指定权重文件完整路径
        _send('setoption name EvalFile value $evalFilePath');
        // 应用用户配置的引擎选项（MultiPV/线程/哈希/棋规）
        applyOptions();
        _send('isready');
        await readyok.future.timeout(
          const Duration(seconds: 20),
          onTimeout: () => throw TimeoutException('引擎就绪超时(权重加载?)'),
        );
        // readyok 不代表权重加载成功：路径打不开时引擎仅打印 ERROR
        // 仍会就绪，这里必须显式检查。
        if (_evalLoadFailed) {
          throw _EvalFileLoadException(evalFilePath);
        }
        _ready = true;
        debugPrint('[pikafish] 引擎启动成功: $exePath');
        return;
      } catch (e) {
        lastError = e;
        debugPrint('[pikafish] $exePath 启动失败: $e');
        // 权重加载失败对所有可执行候选结论一致，直接交给外层回退
        if (e is _EvalFileLoadException) {
          await _teardownProcess();
          rethrow;
        }
        // 清理本次失败的进程与订阅，再尝试下一个候选
        await _teardownProcess();
      }
    }

    throw StateError('所有引擎版本均启动失败: $lastError');
  }

  /// 把引擎无法加载的权重原文件复制到纯 ASCII 的应用数据目录，
  /// 并更新引擎配置；随后调用方会以新路径重新启动引擎。
  Future<void> _fallbackCopyEvalFile(String badPath) async {
    final src = File(badPath);
    if (!await src.exists()) {
      throw EvalFileMissingException();
    }
    final dataDir = await ConfigManager.instance.dataDirPath;
    final target = File(
      '$dataDir${Platform.pathSeparator}pikafish.nnue',
    );
    if (!await target.parent.exists()) {
      await target.parent.create(recursive: true);
    }
    await src.copy(target.path);
    await ConfigManager.instance.updateEngine((c) {
      c.evalFilePath = target.path;
      return c;
    });
  }

  void _onLine(String line) {
    debugPrint('[pikafish] $line');

    if (line == 'uciok') {
      _uciokCompleter?.complete();
      return;
    }
    if (line == 'readyok') {
      _readyokCompleter?.complete();
      return;
    }
    // info ... depth .. multipv N score cp/mate .. time .. nps .. pv ...
    // 只处理含 pv 的行：更新该路候选并广播一份完整快照。
    if (line.startsWith('info ')) {
      // 权重文件无法加载时引擎会输出：
      // "info string ERROR: The network file <path> was not loaded successfully."
      if (line.contains('ERROR') &&
          line.contains('network file') &&
          line.contains('not loaded')) {
        _evalLoadFailed = true;
      }
      _parseInfo(line);
      return;
    }
    if (line.startsWith('bestmove')) {
      // bestmove b2c2 ponder ...
      final parts = line.split(RegExp(r'\s+'));
      final move = parts.length >= 2 ? parts[1] : '(none)';
      // 首选线取 multipv 1；引擎未输出过 pv 时回退到空。
      final best = _pvLines[1];
      _lastPv = best?.moves ?? const [];
      _lastMate = best?.mate;
      final completer = _bestMoveCompleter;
      if (completer != null && !completer.isCompleted) {
        _bestMoveCompleter = null;
        _hardTimeoutTimer?.cancel();
        _hardTimeoutTimer = null;
        completer.complete((
          move: move,
          pv: List<String>.unmodifiable(_lastPv),
          mate: _lastMate,
        ));
      }
      // 无限分析被 stop 后：把 bestmove 交回等待方（出招/分支）。
      final analysisCompleter = _analysisCompleter;
      if (analysisCompleter != null && !analysisCompleter.isCompleted) {
        _analysisCompleter = null;
        analysisCompleter.complete(move);
      }
    }
  }

  /// 解析一条 info 行；仅含 pv 字段的行更新对应候选并广播快照。
  void _parseInfo(String line) {
    // info string ... 是引擎文本输出，不是搜索统计
    if (line.contains(' string ')) return;

    final tokens = line.split(RegExp(r'\s+'));
    var depth = 0;
    var seldepth = 0;
    var multipv = 1;
    var timeMs = 0;
    var nps = 0;
    int? cp;
    int? mate;
    List<String>? pv;

    for (var i = 1; i < tokens.length; i++) {
      // 需要带值的字段，行末缺值时直接放弃该行，避免越界
      int? nextValue() => i + 1 < tokens.length ? int.tryParse(tokens[++i]) : null;
      switch (tokens[i]) {
        case 'depth':
          depth = nextValue() ?? depth;
        case 'seldepth':
          seldepth = nextValue() ?? seldepth;
        case 'multipv':
          multipv = nextValue() ?? multipv;
        case 'time':
          timeMs = nextValue() ?? timeMs;
        case 'nps':
          nps = nextValue() ?? nps;
        case 'score':
          if (i + 2 >= tokens.length) return;
          final kind = tokens[++i]; // cp / mate
          final v = int.tryParse(tokens[++i]) ?? 0;
          if (kind == 'mate') {
            mate = v;
            cp = null;
          } else {
            cp = v;
            mate = null;
          }
        case 'pv':
          // pv 是行末字段，剩余 token 全部为招法
          pv = tokens
              .sublist(i + 1)
              .where((t) => t.length >= 4)
              .toList(growable: false);
          i = tokens.length;
      }
    }

    if (pv == null || pv.isEmpty) return;

    _pvLines[multipv] = EnginePvLine(
      multipv: multipv,
      moves: List<String>.unmodifiable(pv),
      cp: cp,
      mate: mate,
    );

    final sorted = _pvLines.values.toList()
      ..sort((a, b) => a.multipv.compareTo(b.multipv));
    _infoController.add(EngineSearchInfo(
      depth: depth,
      seldepth: seldepth,
      nps: nps,
      timeMs: timeMs,
      sideToMove: _searchSide,
      fen: _searchFen,
      lines: List<EnginePvLine>.unmodifiable(sorted),
    ));
  }

  void _send(String cmd) {
    debugPrint('[pikafish →] $cmd');
    _process?.stdin.writeln(cmd);
  }

  /// 引擎思考时间硬上限(毫秒)。
  static const int maxMoveTimeMs = EngineConfig.kMaxMoveTimeMs;

  /// 同时输出的候选变化路数（MultiPV）。
  static int get multiPv =>
      ConfigManager.instance.config.engine.multiPv;

  /// 把当前配置中的引擎选项实时发送给运行中的引擎。
  ///
  /// 未启动或握手未完成的引擎不响应；启动握手时会再次应用一次。
  void applyOptions() {
    if (!_ready) return;
    final e = ConfigManager.instance.config.engine;
    _send('setoption name MultiPV value ${e.multiPv}');
    _send('setoption name Threads value ${e.threads}');
    _send('setoption name Hash value ${e.hashSizeMb}');
    // 棋规：Pikafish 通过 UCI_Variant 或 Rule 选项下发（按引擎实际支持发送）
    _send('setoption name UCI_Variant value ${e.rule.code}');
  }

  /// 通知引擎开始一局新游戏。
  ///
  /// 在每局开始时（新开局、重开、导入棋谱/残局）调用。此方法是惰性的：
  /// 不会启动引擎进程；真正的 `ucinewgame` 命令延迟到本局**引擎第一次
  /// 被请求** [bestMove] 时才发送——即使此前人类已走若干步，也不影响。
  /// 同一局后续调用不再发送，避免重复重置引擎状态、损失哈希性能。
  void notifyNewGame() {
    _pendingNewGame = true;
  }

  /// 开始无限分析（`go infinite`）：引擎持续搜索并不断推送 info 流，
  /// 直到 [stopAnalysis] 或下一次搜索请求。
  ///
  /// [fen] 为要分析的局面；[banMoves] 非空时通过 pikafish 的
  /// `banmoves` 扩展禁止这些 UCI 招法（分支分析）。
  Future<void> startAnalysis(
    String fen, {
    List<String> banMoves = const [],
  }) async {
    await start();
    // 若有进行中的限时思考，先丢弃；再终止旧的无限分析（消费 bestmove）
    if (_bestMoveCompleter != null) {
      cancelSearch();
    }
    await _finishAnalysis();

    _analyzing = true;
    _lastPv = const [];
    _lastMate = null;
    _pvLines.clear();
    _searchSide = fen.contains(' b ') ? Side.black : Side.red;
    _searchFen = fen;

    _send('position fen $fen');
    if (banMoves.isEmpty) {
      _send('go infinite');
    } else {
      _send('go infinite banmoves ${banMoves.join(' ')}');
    }
  }

  /// 停止无限分析，发送 `stop` 并等待引擎输出 bestmove，返回该 UCI 招法
  /// （无分析或超时时返回 `(none)`）。
  Future<String> stopAnalysis() async {
    if (!_analyzing) return '(none)';
    _analyzing = false;
    final completer = Completer<String>();
    _analysisCompleter = completer;
    _send('stop');
    try {
      return await completer.future
          .timeout(const Duration(seconds: 2), onTimeout: () => '(none)');
    } finally {
      if (identical(_analysisCompleter, completer)) {
        _analysisCompleter = null;
      }
    }
  }

  /// 内部：停止可能进行中的无限分析，丢弃其 bestmove（不等待）。
  ///
  /// 引擎收到 stop 后仍会输出一行 bestmove，由于没有等待者，该行被忽略。
  Future<void> _finishAnalysis() async {
    if (!_analyzing) return;
    _analyzing = false;
    _analysisCompleter = null;
    _send('stop');
  }

  /// 给定 FEN 与思考时间(毫秒)，返回最佳走法(UCI 字符串，如 "b2c2")。
  ///
  /// [moveTimeMs] 会被限制在 [EngineConfig.kMinMoveTimeMs]..[maxMoveTimeMs]
  /// 范围内；[depth] 非 null 时以 `go depth N` 搜索（忽略 movetime）。
  /// 若本调用是 [notifyNewGame] 之后引擎本局第一次被调用，会先发送一次
  /// `ucinewgame`，随后发送当前请求的 [fen]。
  Future<EngineBestMove> bestMove(
    String fen, {
    int moveTimeMs = 800,
    int? depth,
  }) async {
    await start();
    // 若正在无限分析，先停止并丢弃其 bestmove，避免与本次限时搜索冲突。
    await _finishAnalysis();
    final e = ConfigManager.instance.config.engine;
    final effectiveTime =
        moveTimeMs.clamp(EngineConfig.kMinMoveTimeMs, maxMoveTimeMs);
    final effectiveDepth =
        (depth ?? e.depth)?.clamp(EngineConfig.kMinDepth, EngineConfig.kMaxDepth);

    // 新一次思考：清空上一周期残留的 pv/mate 与各路候选
    _lastPv = const [];
    _lastMate = null;
    _pvLines.clear();
    _searchSide = fen.contains(' b ') ? Side.black : Side.red;
    _searchFen = fen;

    final completer = Completer<EngineBestMove>();
    _bestMoveCompleter = completer;

    if (_pendingNewGame) {
      // 本局引擎首次交互：发 ucinewgame，再让引擎分析当前局面
      _send('ucinewgame');
      _pendingNewGame = false;
    }
    _send('position fen $fen');
    if (effectiveDepth != null) {
      _send('go depth $effectiveDepth');
    } else {
      _send('go movetime $effectiveTime');
    }

    // 硬超时保护：深度搜索按 30s 封顶，时间搜索按思考上限 + 余量。
    final timeoutMs = effectiveDepth != null ? 30000 : effectiveTime + 2000;
    _hardTimeoutTimer?.cancel();
    _hardTimeoutTimer = Timer(
      Duration(milliseconds: timeoutMs),
      () {
        if (completer.isCompleted) return;
        debugPrint('[pikafish] 未在规定时间返回 bestmove，发送 stop');
        _send('stop');
        // stop 之后再等 1 秒，仍无响应才判定失败
        Timer(const Duration(seconds: 1), () {
          if (!completer.isCompleted) {
            _bestMoveCompleter = null;
            completer.complete(
                (move: '(none)', pv: const <String>[], mate: null));
          }
        });
      },
    );

    try {
      return await completer.future;
    } finally {
      _hardTimeoutTimer?.cancel();
      _hardTimeoutTimer = null;
    }
  }

  /// 中止当前思考请求（切换页面/对局时调用，引擎进程保留）。
  ///
  /// 若引擎正在思考则发送 `stop` 让其尽快结束当前搜索；同时丢弃等待
  /// bestmove 的 completer 与超时计时器，使之后到达的旧 bestmove 被忽略，
  /// 防止它被误关联到下次进入页面后的新请求。
  void cancelSearch() {
    if (_analyzing) {
      _analyzing = false;
      _analysisCompleter = null;
      _send('stop');
    }
    if (_bestMoveCompleter != null) {
      _send('stop');
      // 不完成旧 completer：其调用方（已销毁页面的控制器）随之放弃等待；
      // 若完成它，旧调用方继续执行会在已 dispose 的 notifier 上通知而报错。
      _bestMoveCompleter = null;
    }
    _hardTimeoutTimer?.cancel();
    _hardTimeoutTimer = null;
  }

  Future<void> _teardownProcess() async {
    await _stdoutSub?.cancel();
    await _stderrSub?.cancel();
    _stdoutSub = null;
    _stderrSub = null;
    _bestMoveCompleter = null;
    _analysisCompleter = null;
    _analyzing = false;
    _hardTimeoutTimer?.cancel();
    _hardTimeoutTimer = null;
    _process?.kill();
    _process = null;
    _ready = false;
    // 关键：清空启动锁，否则下次 start() 会复用这个已完成的旧 Future，
    // 误以为已启动而不会重新拉起进程，导致所有命令因 _process 为 null
    // 被静默丢弃（表现为引擎"没有反应"）。
    _starting = null;
    _pendingNewGame = false;
  }

  /// 准备引擎可执行文件候选列表与权重文件路径。
  ///
  /// 返回 (exeCandidates, dirPath, evalFilePath)。
  /// - Windows：exe 从 assets 拷贝到临时目录，只有一个候选；
  /// - Android：二进制以原生库形式安装到 nativeLibraryDir，
  ///   先 dotprod 版本，后通用 armv8 版本，均不复制、不 chmod；
  /// - 权重文件由用户提供，路径取自 [EngineConfig.evalFilePath]，
  ///   未配置或文件不存在时抛 [EvalFileMissingException]。
  Future<({List<String> exeCandidates, String dirPath, String evalFilePath})>
      _prepareFiles() async {
    final tmp = await getTemporaryDirectory();
    final dir = Directory('${tmp.path}/pikafish');
    if (!await dir.exists()) await dir.create(recursive: true);

    // 权重文件：不再随包分发，必须由用户在引导弹窗中选择并记录路径。
    // 路径的字符集是否被引擎接受（Windows 窄字符接口）不在预检阶段
    // 判定——先让引擎尝试，若报告加载失败则由启动流程复制到 ASCII
    // 数据目录后重试。这里只拦截"未配置/文件已不存在"。
    final evalPath = ConfigManager.instance.config.engine.evalFilePath;
    if (evalPath == null || !File(evalPath).existsSync()) {
      throw EvalFileMissingException();
    }

    final List<String> candidates;
    if (Platform.isWindows) {
      const exeAsset = 'engine/windows/pikafish-bmi2.exe';
      final exeFile = File('${dir.path}/pikafish-bmi2.exe');
      if (!await exeFile.exists()) {
        await _writeAsset(exeAsset, exeFile);
      }
      candidates = [exeFile.path];
    } else if (Platform.isAndroid) {
      // 原生库安装目录（/data/app/.../lib/arm64），Android 10+ 唯一可执行位置
      final libDir = await const MethodChannel(
        'com.xmalloc.wuxingxiangqi/appdirs',
      ).invokeMethod<String>('nativeLibDir');
      if (libDir == null || libDir.isEmpty) {
        throw StateError('无法获取引擎原生库目录');
      }
      // 先 dotprod 版，握手失败再回退通用 armv8 版
      candidates = [
        '$libDir/libpikafish_dotprod.so',
        '$libDir/libpikafish.so',
      ];
    } else {
      throw UnsupportedError('当前平台不支持皮卡鱼引擎');
    }

    return (
      exeCandidates: candidates,
      dirPath: dir.path,
      evalFilePath: evalPath,
    );
  }

  Future<void> _writeAsset(String assetPath, File target) async {
    final bytes = await rootBundle.load(assetPath);
    await target.writeAsBytes(
      bytes.buffer.asUint8List(bytes.offsetInBytes, bytes.lengthInBytes),
      flush: true,
    );
  }

  /// 关闭引擎进程。
  Future<void> dispose() async {
    _send('quit');
    await _teardownProcess();
  }
}
