import 'dart:io';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

class AudioConverterService {
  static const MethodChannel _channel =
      MethodChannel('listenmate/audio_converter');

  /// 将任意音频转换为用于 Whisper 识别的临时 16kHz 单声道 WAV 文件
  Future<File> convertToTempWhisperWav(String inputPath) async {
    final tempDir = await getTemporaryDirectory();
    final tempWavPath =
        '${tempDir.path}/whisper_tmp_${DateTime.now().microsecondsSinceEpoch}.wav';

    await _channel.invokeMethod<String>('convertToWav', {
      'inputPath': inputPath,
      'outputPath': tempWavPath,
      'sampleRate': 16000,
    });

    return File(tempWavPath);
  }

  /// 手动将任意音频转换为标准 WAV 并保存到指定输出路径
  Future<String> convertToWavFile({
    required String inputPath,
    required String outputPath,
    int sampleRate = 16000,
  }) async {
    try {
      final result = await _channel.invokeMethod<String>('convertToWav', {
        'inputPath': inputPath,
        'outputPath': outputPath,
        'sampleRate': sampleRate,
      });
      return result ?? outputPath;
    } on PlatformException catch (e) {
      throw Exception(e.message ?? '音频转换失败');
    }
  }
}