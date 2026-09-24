import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:path_provider/path_provider.dart';

/// 皮卡鱼(Pikafish) UCI 象棋引擎封装。
///
/// - Windows: assets/engine/windows/pikafish-bmi2.exe
/// - Android: assets/engine/android/pikafish-armv8 (arm64)
///
/// Flutter 的 assets 不可直接执行，因此启动时把引擎二进制与权重文件
/// 拷贝到应用临时目录并赋予执行权限，再启动子进程。
class PikafishEngine {
  PikafishEngine._();

  static PikafishEngine? _instance;
  static PikafishEngine get instance => _instance ??= PikafishEngine._();

  Process? _process;
  bool _ready = false;

  /// 启动握手锁：多个调用方共享同一次启动；失败后允许重试。
  Future<void>? _starting;

  /// 握手信号（每次启动重新创建，避免单例 Completer 只能完成一次的问题）。
  Completer<void>? _uciokCompleter;
  Completer<void>? _readyokCompleter;

  /// 当前等待 bestmove 的请求。
  Completer<String>? _bestMoveCompleter;
  Timer? _hardTimeoutTimer;

  /// 新一局通知：true 表示已收到 [notifyNewGame] 但尚未在本局发送过
  /// `ucinewgame`（惰性——引擎进程此时可能还没启动）。
  bool _pendingNewGame = false;

  /// 本局初始局面 FEN（由 [notifyNewGame] 记录）。
  String? _initialFen;

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
    try {
      final (:exePath, :dirPath, :evalFilePath) = await _prepareFiles();
      // 工作目录设为引擎目录，使默认权重文件名 pikafish.nnue 也能被发现
      _process = await Process.start(
        exePath,
        const [],
        workingDirectory: dirPath,
      );
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

      // UCI 握手：uci → uciok 后才能 setoption，再 isready → readyok
      _send('uci');
      await uciok.future.timeout(
        const Duration(seconds: 10),
        onTimeout: () => throw TimeoutException('引擎 uci 握手超时'),
      );
      // 显式指定权重文件完整路径
      _send('setoption name EvalFile value $evalFilePath');
      _send('isready');
      await readyok.future.timeout(
        const Duration(seconds: 20),
        onTimeout: () => throw TimeoutException('引擎就绪超时(权重加载?)'),
      );
      _ready = true;
    } catch (e) {
      // 启动失败要彻底清理，使下次 start() 能重新拉起进程
      debugPrint('[pikafish] 启动失败: $e');
      await _teardownProcess();
      _starting = null; // 允许下次调用重新启动
      rethrow;
    }
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
    if (line.startsWith('bestmove')) {
      // bestmove b2c2 ponder ...
      final parts = line.split(RegExp(r'\s+'));
      final move = parts.length >= 2 ? parts[1] : '(none)';
      final completer = _bestMoveCompleter;
      if (completer != null && !completer.isCompleted) {
        _bestMoveCompleter = null;
        _hardTimeoutTimer?.cancel();
        _hardTimeoutTimer = null;
        completer.complete(move);
      }
    }
  }

  void _send(String cmd) {
    debugPrint('[pikafish →] $cmd');
    _process?.stdin.writeln(cmd);
  }

  /// 引擎思考时间硬上限(毫秒)。
  static const int maxMoveTimeMs = 5000;

  /// 通知引擎开始一局新游戏。
  ///
  /// 必须在每局开始时（新开局、重开、导入棋谱/残局）调用，记录初始 FEN。
  /// 此方法是惰性的：不会启动引擎进程；真正的 `ucinewgame` 命令延迟到
  /// 本局首次 [bestMove] 调用（且当前为初始局面）时才发送，同一局后续
  /// 调用不再重复发送，避免每次思考都重置引擎状态、损失哈希性能。
  void notifyNewGame(String initialFen) {
    _initialFen = initialFen;
    _pendingNewGame = true;
  }

  /// 给定 FEN 与思考时间(毫秒)，返回最佳走法(UCI 字符串，如 "b2c2")。
  ///
  /// [moveTimeMs] 会被限制在 1..[maxMoveTimeMs] 范围内，保证不超过 1 秒。
  /// [isInitialState] 表示当前是否为本局初始局面；仅当为初始局面且本局
  /// 尚未发送过 `ucinewgame` 时，才在本次请求前发送一次。
  Future<String> bestMove(
    String fen, {
    int moveTimeMs = 800,
    bool isInitialState = false,
  }) async {
    await start();
    final effectiveTime = moveTimeMs.clamp(1, maxMoveTimeMs);

    final completer = Completer<String>();
    _bestMoveCompleter = completer;

    if (isInitialState && _pendingNewGame) {
      // 本局首次且处于初始局面：发 ucinewgame + 初始 FEN
      _send('ucinewgame');
      _send('position fen ${_initialFen ?? fen}');
      _pendingNewGame = false;
    } else {
      // 同一局后续调用：只更新局面，不再重置引擎
      _send('position fen $fen');
    }
    _send('go movetime $effectiveTime');

    // 硬超时保护：思考上限 + 余量后仍无 bestmove，则发 stop；
    // 引擎收到 stop 后会尽快输出 bestmove（由 _onLine 完成）。
    _hardTimeoutTimer?.cancel();
    _hardTimeoutTimer = Timer(
      Duration(milliseconds: effectiveTime + 2000),
      () {
        if (completer.isCompleted) return;
        debugPrint('[pikafish] 未在规定时间返回 bestmove，发送 stop');
        _send('stop');
        // stop 之后再等 1 秒，仍无响应才判定失败
        Timer(const Duration(seconds: 1), () {
          if (!completer.isCompleted) {
            _bestMoveCompleter = null;
            completer.complete('(none)');
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
    _initialFen = null;
  }

  /// 在应用可写目录中准备好引擎可执行文件与权重文件。
  ///
  /// 返回 (exePath, dirPath, evalFilePath)。
  Future<({String exePath, String dirPath, String evalFilePath})>
      _prepareFiles() async {
    final tmp = await getTemporaryDirectory();
    final dir = Directory('${tmp.path}/pikafish');
    if (!await dir.exists()) await dir.create(recursive: true);

    final String exeAsset;
    final String exeName;
    final String nnueAsset;
    if (Platform.isWindows) {
      exeAsset = 'engine/windows/pikafish-bmi2.exe';
      exeName = 'pikafish-bmi2.exe';
      nnueAsset = 'engine/windows/pikafish.nnue';
    } else if (Platform.isAndroid) {
      exeAsset = 'engine/android/pikafish-armv8';
      exeName = 'pikafish-armv8';
      nnueAsset = 'engine/android/pikafish.nnue';
    } else {
      throw UnsupportedError('当前平台不支持皮卡鱼引擎');
    }

    // 可执行文件
    final exeFile = File('${dir.path}/$exeName');
    if (!await exeFile.exists()) {
      await _writeAsset(exeAsset, exeFile);
      if (!Platform.isWindows) {
        await Process.run('chmod', ['+x', exeFile.path]);
      }
    }

    // 神经网络权重文件（引擎运行必需）
    final nnueFile = File('${dir.path}/pikafish.nnue');
    if (!await nnueFile.exists()) {
      await _writeAsset(nnueAsset, nnueFile);
    }

    return (
      exePath: exeFile.path,
      dirPath: dir.path,
      evalFilePath: nnueFile.path,
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
