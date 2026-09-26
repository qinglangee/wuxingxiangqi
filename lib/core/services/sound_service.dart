import 'package:flutter/services.dart';

/// 音效播放服务。
///
/// 当前网络环境无法引入 audioplayers，先用系统提示音实现走子/
/// 吃子/游戏结束的听觉反馈；后续可替换为播放自定义 mp3。
class SoundService {
  SoundService._();

  /// 走子音效。
  static void playMove() {
    SystemSound.play(SystemSoundType.click);
  }

  /// 吃子音效（比走子更明显的提示）。
  static void playEat() {
    SystemSound.play(SystemSoundType.alert);
  }

  /// 游戏结束音效。
  static void playWin() {
    SystemSound.play(SystemSoundType.alert);
  }
}
