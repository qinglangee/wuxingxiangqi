package com.xmalloc.wuxingxiangqi

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val channelName = "com.xmalloc.wuxingxiangqi/appdirs"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // 暴露原生库安装目录：皮卡鱼引擎可执行文件以 lib*.so 形式打包在
        // jniLibs 中，安装后由系统释放到 nativeLibraryDir（该目录允许
        // 执行；Android 10+ 的应用私有数据/缓存目录禁止执行代码）。
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "nativeLibDir" -> result.success(applicationInfo.nativeLibraryDir)
                    else -> result.notImplemented()
                }
            }
    }
}
