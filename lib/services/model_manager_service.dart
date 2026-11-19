import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:whisper_flutter_new/whisper_flutter_new.dart';

typedef ModelStatusMap = Map<OfflineAsrModelType, bool>;

enum OfflineAsrModelType {
  tinyEn(
    fileName: 'ggml-tiny.bin',
    title: '轻量极速版 (tiny)',
    sizeLabel: '约 75 MB',
    description: '占用空间小、识别速度快，适合快速生成草稿字幕',
    whisperModel: WhisperModel.tiny,
  ),
  baseEn(
    fileName: 'ggml-base.bin',
    title: '推荐均衡版 (base)',
    sizeLabel: '约 142 MB',
    description: '识别精度更高，对四六级连读、弱读与长难句辨识更准确',
    whisperModel: WhisperModel.base,
  );

  final String fileName;
  final String title;
  final String sizeLabel;
  final String description;
  final WhisperModel whisperModel;

  const OfflineAsrModelType({
    required this.fileName,
    required this.title,
    required this.sizeLabel,
    required this.description,
    required this.whisperModel,
  });

  static OfflineAsrModelType fromName(String name) {
    return OfflineAsrModelType.values.firstWhere(
      (e) => e.name == name,
      orElse: () => OfflineAsrModelType.baseEn,
    );
  }
}

class ModelManagerService {
  http.Client? _activeClient;
  bool _isCancelled = false;

  Future<Directory> getModelDirectory() async {
    final supportDir = await getApplicationSupportDirectory();
    final dir = Directory('${supportDir.path}/whisper_models');
    if (!dir.existsSync()) {
      dir.createSync(recursive: true);
    }
    return dir;
  }

  Future<File> getModelFile(OfflineAsrModelType type) async {
    final dir = await getModelDirectory();
    return File('${dir.path}/${type.fileName}');
  }

  Future<bool> isModelDownloaded(OfflineAsrModelType type) async {
    final file = await getModelFile(type);
    return file.existsSync() && file.lengthSync() > 10 * 1024 * 1024;
  }

  Future<ModelStatusMap> getAllModelStatuses() async {
    final ModelStatusMap result = {};
    for (final type in OfflineAsrModelType.values) {
      result[type] = await isModelDownloaded(type);
    }
    return result;
  }

  /// 按需流式下载离线模型（支持主备镜像自动切换容错）
  Future<void> downloadModel({
    required OfflineAsrModelType type,
    required bool useChinaMirror,
    required void Function(double progress) onProgress,
  }) async {
    cancelDownload();
    _isCancelled = false;

    const mirrorHost = 'https://hf-mirror.com/ggerganov/whisper.cpp/resolve/main';
    const officialHost =
        'https://huggingface.co/ggerganov/whisper.cpp/resolve/main';

    final hosts = useChinaMirror
        ? [mirrorHost, officialHost]
        : [officialHost, mirrorHost];

    Object? lastError;
    for (final host in hosts) {
      if (_isCancelled) return;
      try {
        await _downloadFromUri(
          uri: Uri.parse('$host/${type.fileName}'),
          type: type,
          onProgress: onProgress,
        );
        return; // 下载成功直接返回
      } catch (e) {
        if (_isCancelled) rethrow;
        lastError = e;
      }
    }

    throw Exception(
      '模型下载失败，请检查手机网络连接或应用联网权限 ($lastError)',
    );
  }

  Future<void> _downloadFromUri({
    required Uri uri,
    required OfflineAsrModelType type,
    required void Function(double progress) onProgress,
  }) async {
    final targetFile = await getModelFile(type);
    final tempFile = File('${targetFile.path}.tmp');
    if (tempFile.existsSync()) {
      tempFile.deleteSync();
    }

    final client = http.Client();
    _activeClient = client;

    try {
      final request = http.Request('GET', uri);
      final response = await client.send(request);

      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw Exception('HTTP ${response.statusCode}');
      }

      final totalBytes = response.contentLength ?? 0;
      int receivedBytes = 0;
      final sink = tempFile.openWrite();

      await for (final chunk in response.stream) {
        sink.add(chunk);
        receivedBytes += chunk.length;
        if (totalBytes > 0) {
          onProgress((receivedBytes / totalBytes).clamp(0.0, 1.0));
        }
      }

      await sink.flush();
      await sink.close();

      if (targetFile.existsSync()) {
        targetFile.deleteSync();
      }
      tempFile.renameSync(targetFile.path);
      onProgress(1.0);
    } catch (e) {
      if (tempFile.existsSync()) {
        tempFile.deleteSync();
      }
      rethrow;
    } finally {
      if (_activeClient == client) {
        _activeClient = null;
      }
      client.close();
    }
  }

  void cancelDownload() {
    _isCancelled = true;
    _activeClient?.close();
    _activeClient = null;
  }

  Future<void> deleteModel(OfflineAsrModelType type) async {
    final file = await getModelFile(type);
    if (file.existsSync()) {
      file.deleteSync();
    }
  }
}