import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'package:http/http.dart' as http;
import 'package:whisper_flutter_new/whisper_flutter_new.dart';
import '../models/audio_item.dart';
import 'audio_converter_service.dart';
import 'model_manager_service.dart';
import 'storage_service.dart';

class SubtitleService {
  final ModelManagerService _modelManager = ModelManagerService();
  final AudioConverterService _converter = AudioConverterService();

  /// 生成双语字幕并实时回调进度 (0.0 ~ 1.0) 与阶段说明
  Future<List<SubtitleCue>> generateBilingualSubtitles({
    required String filePath,
    required OfflineAsrModelType offlineModel,
    required DeepSeekApiConfig deepSeekConfig,
    Duration? audioDuration,
    void Function(double progress, String status)? onProgress,
  }) async {
    final file = File(filePath);
    if (!file.existsSync()) {
      throw Exception('音频文件不存在，请检查路径');
    }

    final downloaded = await _modelManager.isModelDownloaded(offlineModel);
    if (!downloaded) {
      throw Exception('离线识别模型尚未下载，请先前往底部“设置”页下载模型');
    }

    File? tempWavFile;
    Timer? whisperProgressTimer;
    late final WhisperTranscribeResponse response;

    try {
      onProgress?.call(0.05, '阶段 1/3：正在转换音频为 16kHz WAV 格式...');
      tempWavFile = await _converter.convertToTempWhisperWav(file.path);
      onProgress?.call(0.15, '阶段 2/3：正在本地离线识别英文语音...');

      final modelDir = await _modelManager.getModelDirectory();
      final whisper = Whisper(
        model: offlineModel.whisperModel,
        modelDir: modelDir.path,
      );

      final totalAudioSec = (audioDuration?.inSeconds ?? 0) > 0
          ? audioDuration!.inSeconds.toDouble()
          : 45.0;
      final speedFactor =
          offlineModel == OfflineAsrModelType.tinyEn ? 6.0 : 3.5;
      final estimatedSec = (totalAudioSec / speedFactor + 3.0).clamp(5.0, 300.0);
      final stopwatch = Stopwatch()..start();

      whisperProgressTimer = Timer.periodic(
        const Duration(milliseconds: 300),
        (_) {
          final elapsedSec = stopwatch.elapsedMilliseconds / 1000.0;
          final ratio = 1.0 - math.exp(-elapsedSec / estimatedSec);
          final smoothProgress = 0.15 + 0.59 * ratio;
          onProgress?.call(
            smoothProgress,
            '阶段 2/3：正在本地离线识别英文语音...',
          );
        },
      );

      response = await whisper.transcribe(
        transcribeRequest: TranscribeRequest(
          audio: tempWavFile.path,
          language: 'en',
          isTranslate: false,
          isNoTimestamps: false,
          splitOnWord: false,
        ),
      );

      whisperProgressTimer.cancel();
      whisperProgressTimer = null;
      onProgress?.call(0.75, '英文语音识别完成，准备处理字幕...');
    } finally {
      whisperProgressTimer?.cancel();
      if (tempWavFile != null && tempWavFile.existsSync()) {
        try {
          tempWavFile.deleteSync();
        } catch (_) {}
      }
    }

    final rawSegments = _parseWhisperSegments(
      response,
      totalDurationMs: audioDuration?.inMilliseconds ?? 0,
    );
    if (rawSegments.isEmpty) {
      throw Exception('未识别到有效英文语音内容');
    }

    if (!deepSeekConfig.isConfigured) {
      onProgress?.call(1.0, '英文字幕生成完成');
      return List.generate(rawSegments.length, (i) {
        final seg = rawSegments[i];
        return SubtitleCue(
          id: '${DateTime.now().microsecondsSinceEpoch}_$i',
          startMs: seg.startMs,
          endMs: seg.endMs,
          english: seg.english,
          chinese: '',
        );
      });
    }

    final cleanBaseUrl =
        deepSeekConfig.baseUrl.trim().replaceAll(RegExp(r'/+$'), '');
    final List<SubtitleCue> result = [];
    const batchSize = 25;

    for (int i = 0; i < rawSegments.length; i += batchSize) {
      final end = (i + batchSize < rawSegments.length)
          ? i + batchSize
          : rawSegments.length;
      final batch = rawSegments.sublist(i, end);

      final currentProgress = 0.75 + 0.25 * (i / rawSegments.length);
      onProgress?.call(
        currentProgress,
        '阶段 3/3：DeepSeek 正在翻译双语字幕 ($end/${rawSegments.length} 句)...',
      );

      final translations = await _translateWithDeepSeek(
        englishLines: batch.map((e) => e.english).toList(),
        baseUrl: cleanBaseUrl,
        apiKey: deepSeekConfig.apiKey.trim(),
        model: deepSeekConfig.model.trim(),
      );

      for (int j = 0; j < batch.length; j++) {
        final seg = batch[j];
        final zh = j < translations.length ? translations[j] : '';
        result.add(
          SubtitleCue(
            id: '${DateTime.now().microsecondsSinceEpoch}_${i + j}',
            startMs: seg.startMs,
            endMs: seg.endMs,
            english: seg.english,
            chinese: zh,
          ),
        );
      }

      final doneProgress = 0.75 + 0.25 * (end / rawSegments.length);
      onProgress?.call(
        doneProgress,
        '阶段 3/3：DeepSeek 正在翻译双语字幕 ($end/${rawSegments.length} 句)...',
      );
    }

    onProgress?.call(1.0, '双语字幕生成完成');
    return result;
  }

  List<_RawSegment> _parseWhisperSegments(
    WhisperTranscribeResponse response, {
    required int totalDurationMs,
  }) {
    final segments = response.segments;
    if (segments != null && segments.isNotEmpty) {
      final parsed = <_RawSegment>[];
      int prevEndMs = 0;

      for (final seg in segments) {
        final text = seg.text.trim();
        if (text.isEmpty) continue;

        int startMs = seg.fromTs.inMilliseconds;
        int endMs = seg.toTs.inMilliseconds;

        // 保证时间轴严格单调递增，避免区间倒挂
        if (startMs < prevEndMs) {
          startMs = prevEndMs;
        }
        if (endMs <= startMs) {
          endMs = startMs + 1500;
        }
        if (totalDurationMs > 0 && endMs > totalDurationMs) {
          endMs = totalDurationMs;
        }

        parsed.add(
          _RawSegment(
            startMs: startMs,
            endMs: endMs,
            english: text,
          ),
        );
        prevEndMs = endMs;
      }
      if (parsed.isNotEmpty) return parsed;
    }

    // 兜底：按各句字符长度在音频总时长内等比例分配时间戳，避免固定 4 秒导致累积漂移
    final fullText = response.text.trim();
    if (fullText.isEmpty) return [];

    final sentences = fullText
        .split(RegExp(r'(?<=[.!?])\s+'))
        .where((s) => s.trim().isNotEmpty)
        .map((s) => s.trim())
        .toList();

    final totalChars = sentences.fold<int>(0, (sum, s) => sum + s.length);
    final effectiveDuration = totalDurationMs > 0
        ? totalDurationMs
        : sentences.length * 3000;

    int cursorMs = 0;
    return List.generate(sentences.length, (idx) {
      final sentence = sentences[idx];
      final ratio = totalChars > 0
          ? (sentence.length / totalChars)
          : (1.0 / sentences.length);
      final sliceMs = (effectiveDuration * ratio).round().clamp(800, 15000);
      final startMs = cursorMs;
      final endMs = (idx == sentences.length - 1)
          ? effectiveDuration
          : (startMs + sliceMs).clamp(startMs + 500, effectiveDuration);
      cursorMs = endMs;

      return _RawSegment(
        startMs: startMs,
        endMs: endMs,
        english: sentence,
      );
    });
  }

  Future<List<String>> _translateWithDeepSeek({
    required List<String> englishLines,
    required String baseUrl,
    required String apiKey,
    required String model,
  }) async {
    final uri = Uri.parse('$baseUrl/chat/completions');
    final numberedInput = List.generate(
      englishLines.length,
      (idx) => '${idx + 1}. ${englishLines[idx]}',
    ).join('\n');

    final isDeepSeek = baseUrl.contains('deepseek.com');
    final Map<String, dynamic> payload = {
      'model': model,
      'temperature': 0.2,
      if (isDeepSeek) 'thinking': {'type': 'disabled'},
      'messages': [
        {
          'role': 'system',
          'content':
              '你是一名大学英语四六级听力翻译专家。请将用户提供的多行英文听力原句逐条翻译为地道、准确、简洁的中文。'
                  '严格只返回一个 JSON 字符串数组（例如 ["第一句译文", "第二句译文"]），数组长度必须与输入行数完全一致，不要输出任何额外说明或 Markdown 标记。',
        },
        {
          'role': 'user',
          'content': numberedInput,
        },
      ],
    };

    final response = await http.post(
      uri,
      headers: {
        'Authorization': 'Bearer $apiKey',
        'Content-Type': 'application/json',
      },
      body: jsonEncode(payload),
    );

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('DeepSeek 翻译接口报错 (${response.statusCode}): ${response.body}');
    }

    final Map<String, dynamic> data =
        jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
    final choices = data['choices'] as List<dynamic>? ?? [];
    if (choices.isEmpty) return List.filled(englishLines.length, '');

    String content =
        (choices.first['message']['content'] as String? ?? '').trim();

    content = content
        .replaceAll(RegExp(r'^```json\s*', caseSensitive: false), '')
        .replaceAll(RegExp(r'^```\s*'), '')
        .replaceAll(RegExp(r'\s*```$'), '')
        .trim();

    final decoded = jsonDecode(content) as List<dynamic>;
    return decoded.map((e) => e.toString().trim()).toList();
  }
}

class _RawSegment {
  final int startMs;
  final int endMs;
  final String english;

  const _RawSegment({
    required this.startMs,
    required this.endMs,
    required this.english,
  });
}