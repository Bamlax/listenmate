package com.example.listenmate // <-- 请保留你原有的 package 声明

import android.os.Handler
import android.os.Looper
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.Executors

class MainActivity : FlutterActivity() {
    private val channelName = "listenmate/audio_converter"
    private val executor = Executors.newSingleThreadExecutor()
    private val mainHandler = Handler(Looper.getMainLooper())

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call, result ->
                if (call.method == "convertToWav") {
                    val inputPath = call.argument<String>("inputPath")
                    val outputPath = call.argument<String>("outputPath")
                    val sampleRate = call.argument<Int>("sampleRate") ?: 16000

                    if (inputPath.isNullOrBlank() || outputPath.isNullOrBlank()) {
                        result.error("INVALID_ARGS", "输入或输出路径为空", null)
                        return@setMethodCallHandler
                    }

                    executor.execute {
                        try {
                            AudioConverter.convertToWav(
                                inputPath = inputPath,
                                outputPath = outputPath,
                                targetSampleRate = sampleRate
                            )
                            mainHandler.post { result.success(outputPath) }
                        } catch (e: Exception) {
                            mainHandler.post {
                                result.error(
                                    "CONVERT_FAILED",
                                    e.message ?: "音频格式转换失败",
                                    null
                                )
                            }
                        }
                    }
                } else {
                    result.notImplemented()
                }
            }
    }

    override fun onDestroy() {
        executor.shutdown()
        super.onDestroy()
    }
}