import 'dart:io';

import 'package:flutter/services.dart';

/// Android 存储权限服务：让应用能直接用 dart:io 读写用户选择的
/// 公共目录（如 Documents/Download 下的棋谱仓库目录）。
///
/// 背景：Android 11+ 上 SAF 目录选择器（file_picker 的授权弹窗）只授予
/// 那一次内容访问，后续的 dart:io 文件写入仍会被拒绝，需要用户在系统
/// 设置里授予「所有文件访问」；Android 10 及以下则需要传统的外部存储
/// 运行时权限。本服务通过 MethodChannel（MainActivity.kt）完成申请。
class StorageAccessService {
  StorageAccessService._();

  static const MethodChannel _channel =
      MethodChannel('com.xmalloc.wuxingxiangqi/appdirs');

  /// 设备 Android API 版本（非 Android 返回 0）。
  static Future<int> sdkInt() async {
    if (!Platform.isAndroid) return 0;
    try {
      return await _channel.invokeMethod<int>('sdkInt') ?? 0;
    } catch (_) {
      return 0;
    }
  }

  /// Android 11+：是否已授予「所有文件访问」。
  static Future<bool> hasAllFilesAccess() async {
    if (!Platform.isAndroid) return true;
    try {
      return await _channel.invokeMethod<bool>('isAllFilesAccess') ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Android 11+：跳转系统设置页申请「所有文件访问」。
  /// 用户授权后返回应用，需再次调用 [hasAllFilesAccess] 确认。
  static Future<void> requestAllFilesAccess() async {
    if (!Platform.isAndroid) return;
    try {
      await _channel.invokeMethod<void>('requestAllFilesAccess');
    } catch (_) {
      // 忽略跳转失败
    }
  }

  /// Android 10 及以下：申请传统外部存储写权限（弹出系统授权对话框，
  /// 挂起直到用户选择）。返回是否获得授权。
  static Future<bool> requestLegacyStorage() async {
    if (!Platform.isAndroid) return true;
    try {
      return await _channel.invokeMethod<bool>('requestLegacyStorage') ?? false;
    } catch (_) {
      return false;
    }
  }
}
