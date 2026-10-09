import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';

/// 音效播放服务：走子 / 吃子 / 将军 / 终局等音效。
///
/// 多播放器模式：每个音效维护一个**独立且常驻**的 [AudioPlayer]，
/// 在 [preload] 阶段一次性完成：
/// 1. 全局设为 mixWithOthers（Android 不请求音频焦点），避免不同音效
///    播放时因抢占音频焦点而互相掐断；
/// 2. 音频文件解码进 [AudioCache]（只读一次盘）；
/// 3. 对每个 player `setSource` 预置好声源；
/// 4. 统一设置低延迟模式 + [ReleaseMode.stop]，使播放结束后只暂停回零、
///    声源继续常驻内存（默认的 release 模式播完即释放声源）。
///
/// 播放时只做 `stop() + resume()`，不再临时切换声源，因此：
/// - 不同音效各用各的 player，可并发播放、互不打断、不争用同一文件句柄
///   （避免 Windows 上并发访问缓存文件的 errno 32 锁冲突）；
/// - 同一音效被快速连续触发时，仅重启自己的 player，延迟最低；
/// - 每个 player 有独立的串行链，保证同一音效快速连点时 stop/resume
///   按序执行；不同音效之间不互相排队阻塞。
///
/// 注意：不能用 Dart 层的 `seek(0)` 重启——Android 低延迟模式底层是
/// SoundPool，不会回调 `onSeekComplete`，Dart 端 `seek()` 会等到超时；
/// 而原生 `stop()` 在 stop 释放模式下内部即「暂停 + 回零」，不涉及该事件。
/// 这与官方 audioplayers 为短促音效提供的 AudioPool 做法一致。
class SoundService {
  SoundService._();

  static const String _dir = 'sounds/chess';

  static const _movePath = '$_dir/move.mp3';
  static const _eatPath = '$_dir/eat.mp3';
  static const _checkPath = '$_dir/check.mp3';
  static const _winPath = '$_dir/win.mp3';
  static const _alarmPath = '$_dir/alarm.mp3';
  static const _chuaPath = '$_dir/chua.mp3';
  static const _errorPath = '$_dir/error.mp3';

  static final AudioCache _cache = AudioCache(prefix: 'assets/');
  static bool _preloaded = false;

  /// 每个音效一个独立播放器，声源在预加载阶段一次性预置。
  /// 共用同一个 [_cache]，预热与实际播放命中同一份缓存文件，避免重复拷贝。
  static AudioPlayer _newPlayer() => AudioPlayer()..audioCache = _cache;
  static final AudioPlayer _movePlayer = _newPlayer();
  static final AudioPlayer _eatPlayer = _newPlayer();
  static final AudioPlayer _checkPlayer = _newPlayer();
  static final AudioPlayer _winPlayer = _newPlayer();
  static final AudioPlayer _alarmPlayer = _newPlayer();
  static final AudioPlayer _chuaPlayer = _newPlayer();
  static final AudioPlayer _errorPlayer = _newPlayer();

  /// 每次播放「游戏结束」音效时自增，供 UI 监听以同步播放绝杀动画等。
  static final ValueNotifier<int> winTick = ValueNotifier(0);

  /// 预加载：解码全部音效到缓存，并为每个播放器预置声源。
  static Future<void> preload() async {
    if (_preloaded) return;
    _preloaded = true;

    // 0) 全局混音：不向系统请求音频焦点。默认 focus=gain 时，每个 player
    //    播放前都会请求 AUDIOFOCUS_GAIN，于是后播放的音效（如 AI 快速
    //    跟出的走子音）会让正在播放的音效（将军音）收到焦点丢失回调而
    //    被原生层直接暂停——表现为不同音效互相掐断。mixWithOthers 在
    //    Android 上映射为 AUDIOFOCUS_NONE（各音效自由混音叠加），
    //    iOS 上则打开 AVAudioSession mixWithOthers 选项。
    await AudioPlayer.global.setAudioContext(
      AudioContextConfig(focus: AudioContextConfigFocus.mixWithOthers).build(),
    );
    const paths = [
      _movePath,
      _eatPath,
      _checkPath,
      _winPath,
      _alarmPath,
      _chuaPath,
      _errorPath,
    ];
    // 1) 统一低延迟模式 + stop 释放模式：播完只暂停回零，声源常驻不销毁
    for (final p in _allPlayers) {
      await p.setPlayerMode(PlayerMode.lowLatency);
      await p.setReleaseMode(ReleaseMode.stop);
    }
    // 2) 音频文件解码进内存缓存（各文件并行加载，只读一次盘）
    await Future.wait(paths.map((f) => _cache.load(f)));
    // 3) 每个播放器预置自己的声源，之后播放无需再读文件
    await Future.wait([
      for (var i = 0; i < paths.length; i++)
        _allPlayers[i].setSource(AssetSource(paths[i])),
    ]);
  }

  /// 走子音效。
  static void playMove() => _restart(_movePlayer);

  /// 吃子音效。
  static void playEat() => _restart(_eatPlayer);

  /// 将军音效。
  static void playCheck() => _restart(_checkPlayer);

  /// 游戏结束音效。
  static void playWin() {
    winTick.value++;
    _restart(_winPlayer);
  }

  /// 取消选中提示音效。
  static void playAlarm() => _restart(_alarmPlayer);

  /// 切换分析状态音效。
  static void playChua() => _restart(_chuaPlayer);

  /// 走子错误提示音效（如背谱时走了与棋谱不一致的着法）。
  static void playError() => _restart(_errorPlayer);

  static List<AudioPlayer> get _allPlayers => [
        _movePlayer,
        _eatPlayer,
        _checkPlayer,
        _winPlayer,
        _alarmPlayer,
        _chuaPlayer,
        _errorPlayer,
      ];

  /// 每个播放器各自的串行链：同一音效快速连点时，保证 stop/resume
  /// 按序执行；不同播放器的链彼此独立，不互相阻塞。
  static final Map<AudioPlayer, Future<void>> _chains = {};

  /// 从头重启指定播放器（声源已预置）。
  ///
  /// 不使用 Dart 层 `seek()`：Android 低延迟模式（SoundPool）不回调
  /// seekComplete，会导致 seek 调用挂起直至超时。原生 `stop()` 在
  /// [ReleaseMode.stop] 下本身就是「暂停 + 回到起点」且声源不释放，
  /// 随后 `resume()` 即从头播放，重启延迟最低。
  static void _restart(AudioPlayer player) {
    final chain = (_chains[player] ?? Future.value()).then((_) async {
      // 兼容 playing/completed/paused/stopped：停止回零后立即重新播放。
      await player.stop();
      await player.resume();
    });
    // 单个播放器出错不阻塞该播放器后续播放
    _chains[player] = chain.catchError((_) {});
  }
}
