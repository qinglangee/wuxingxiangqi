import 'package:audioplayers/audioplayers.dart';

/// 音效播放服务：走子 / 吃子 / 游戏结束的自定义音效。
///
/// 单播放器模式：只维护一个常驻 [AudioPlayer]，所有音效共用。
/// 播放前先把该 player 停掉（无论当前是否在播），再切到新音效源播放，
/// 保证每次请求都能立即出声、不受前一次播放状态影响。
///
/// 音效数据在 [preload] 时缓存到 [AudioCache]，播放时直接通过缓存键
/// 引用，避免重复解码。
class SoundService {
  SoundService._();

  static const String _dir = 'sounds/chess';

  static const _movePath = '$_dir/move.mp3';
  static const _eatPath = '$_dir/eat.mp3';
  static const _checkPath = '$_dir/check.mp3';
  static const _winPath = '$_dir/win.mp3';
  static const _alarmPath = '$_dir/alarm.mp3';
  static const _chuaPath = '$_dir/chua.mp3';

  static final AudioPlayer _player = AudioPlayer();
  static final AudioCache _cache = AudioCache(prefix: 'assets/');
  static bool _preloaded = false;

  /// 预加载三个音效到缓存并初始化播放器。
  static Future<void> preload() async {
    if (_preloaded) return;
    _preloaded = true;
    _player.setPlayerMode(PlayerMode.lowLatency);
    // 预热缓存：把音频文件解码进内存，播放时不再读盘
    await Future.wait([
      _cache.load(_movePath),
      _cache.load(_eatPath),
      _cache.load(_checkPath),
      _cache.load(_winPath),
      _cache.load(_alarmPath),
      _cache.load(_chuaPath),
    ]);
  }

  /// 走子音效。
  static void playMove() => _play(_movePath);

  /// 吃子音效。
  static void playEat() => _play(_eatPath);

  /// 将军音效。
  static void playCheck() => _play(_checkPath);

  /// 游戏结束音效。
  static void playWin() => _play(_winPath);

  /// 取消选中提示音效。
  static void playAlarm() => _play(_alarmPath);

  /// 切换分析状态音效。
  static void playChua() => _play(_chuaPath);

  static void _play(String path) {
    // 无论当前状态（idle/playing/completed/paused）都先停掉，
    // 确保下一次 play 立即生效且从头播放。
    _player.stop().then((_) {
      _player.play(AssetSource(path));
    });
  }
}
