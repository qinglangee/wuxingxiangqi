package com.xmalloc.wuxingxiangqi

import android.Manifest
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.provider.Settings
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val channelName = "com.xmalloc.wuxingxiangqi/appdirs"

    /// 等待运行时权限授权结果的挂起回调（requestLegacyStorage 用）
    private var pendingStorageResult: MethodChannel.Result? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // 暴露原生库安装目录：皮卡鱼引擎可执行文件以 lib*.so 形式打包在
        // jniLibs 中，安装后由系统释放到 nativeLibraryDir（该目录允许
        // 执行；Android 10+ 的应用私有数据/缓存目录禁止执行代码）。
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "nativeLibDir" -> result.success(applicationInfo.nativeLibraryDir)
                    "sdkInt" -> result.success(Build.VERSION.SDK_INT)
                    "isAllFilesAccess" -> result.success(hasAllFilesAccess())
                    "requestAllFilesAccess" -> {
                        // Android 11+：跳转系统设置页申请"所有文件访问"。
                        // 用户在设置里授权后返回应用，Dart 端再查询
                        // isAllFilesAccess 确认结果。
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                            try {
                                startActivity(
                                    Intent(
                                        Settings.ACTION_MANAGE_APP_ALL_FILES_ACCESS_PERMISSION,
                                        Uri.parse("package:$packageName"),
                                    )
                                )
                            } catch (e: Exception) {
                                // 部分机型不支持带包名的页面，退回通用入口
                                startActivity(
                                    Intent(Settings.ACTION_MANAGE_ALL_FILES_ACCESS_PERMISSION)
                                )
                            }
                        }
                        result.success(null)
                    }
                    "requestLegacyStorage" -> {
                        // Android 10 及以下：申请传统外部存储写权限（运行时授权）
                        val permission = Manifest.permission.WRITE_EXTERNAL_STORAGE
                        if (Build.VERSION.SDK_INT <= Build.VERSION_CODES.S_V2 &&
                            ContextCompat.checkSelfPermission(this, permission) !=
                            PackageManager.PERMISSION_GRANTED
                        ) {
                            pendingStorageResult = result
                            ActivityCompat.requestPermissions(
                                this,
                                arrayOf(permission),
                                REQUEST_STORAGE_PERMISSION,
                            )
                        } else {
                            result.success(true)
                        }
                    }
                    else -> result.notImplemented()
                }
            }
    }

    /// 是否已授予"所有文件访问"权限（仅 Android 11+ 有此概念）
    private fun hasAllFilesAccess(): Boolean =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            Environment.isExternalStorageManager()
        } else {
            false
        }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == REQUEST_STORAGE_PERMISSION) {
            pendingStorageResult?.success(
                grantResults.isNotEmpty() &&
                    grantResults[0] == PackageManager.PERMISSION_GRANTED
            )
            pendingStorageResult = null
        }
    }

    companion object {
        private const val REQUEST_STORAGE_PERMISSION = 1001
    }
}
