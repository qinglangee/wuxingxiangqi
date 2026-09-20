/// 棋谱解析相关异常。
///
/// 解析失败、文件格式不支持、走法非法等情况抛出。
class NotationParseException implements Exception {
  const NotationParseException(this.message, {this.cause});

  /// 给用户看的错误信息（人类可读）。
  final String message;

  /// 原始异常，便于日志排查。
  final Object? cause;

  @override
  String toString() => 'NotationParseException: $message';
}
