import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import '../data/changelog.dart';
import '../providers/player_provider.dart';
import '../services/audio_converter_service.dart';
import '../services/model_manager_service.dart';
import '../services/storage_service.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  /// 独立音频格式转换器 (转 WAV) 弹窗
  void _showAudioConverterSheet(BuildContext context) {
    final converter = AudioConverterService();
    String? selectedInputPath;
    String selectedFileName = '';
    int targetSampleRate = 16000;
    bool isConverting = false;
    String? outputSavedPath;
    String? errorMessage;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setModalState) {
            final colorScheme = Theme.of(ctx).colorScheme;
            final textTheme = Theme.of(ctx).textTheme;

            Future<void> pickSourceAudio() async {
              final res = await FilePicker.platform.pickFiles(
                type: FileType.any,
                allowMultiple: false,
              );
              if (res == null || res.files.isEmpty) return;
              final picked = res.files.first;
              if (picked.path == null) return;

              setModalState(() {
                selectedInputPath = picked.path;
                selectedFileName = picked.name;
                outputSavedPath = null;
                errorMessage = null;
              });
            }

            Future<void> startConvert() async {
              if (selectedInputPath == null || isConverting) return;
              setModalState(() {
                isConverting = true;
                outputSavedPath = null;
                errorMessage = null;
              });

              try {
                Directory outDir =
                    Directory('/storage/emulated/0/Download/ListenMate_WAV');
                try {
                  if (!outDir.existsSync()) {
                    outDir.createSync(recursive: true);
                  }
                } catch (_) {
                  final extDir = await getExternalStorageDirectory();
                  outDir = Directory(
                    '${(extDir ?? await getApplicationDocumentsDirectory()).path}/WAV_Exports',
                  );
                  if (!outDir.existsSync()) {
                    outDir.createSync(recursive: true);
                  }
                }

                final baseName =
                    selectedFileName.replaceFirst(RegExp(r'\.[^.]+$'), '');
                final outPath =
                    '${outDir.path}/${baseName}_${targetSampleRate}Hz.wav';

                final saved = await converter.convertToWavFile(
                  inputPath: selectedInputPath!,
                  outputPath: outPath,
                  sampleRate: targetSampleRate,
                );

                setModalState(() {
                  outputSavedPath = saved;
                });
              } catch (e) {
                setModalState(() {
                  errorMessage = e.toString().replaceFirst('Exception: ', '');
                });
              } finally {
                setModalState(() {
                  isConverting = false;
                });
              }
            }

            return SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.transform_rounded, color: colorScheme.primary),
                        const SizedBox(width: 8),
                        Text(
                          '音频格式转换器 (转 WAV)',
                          style: textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '支持将 MP3、M4A、AAC、OGG 等转换为 16-bit 单声道 PCM WAV（生成字幕时会自动转换，此处用于手动导出备份）',
                      style: textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                        height: 1.4,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Material(
                      color: colorScheme.surfaceContainerLow,
                      borderRadius: BorderRadius.circular(14),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(14),
                        onTap: isConverting ? null : pickSourceAudio,
                        child: Padding(
                          padding: const EdgeInsets.all(14),
                          child: Row(
                            children: [
                              Icon(
                                Icons.audio_file_rounded,
                                color: colorScheme.primary,
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  selectedFileName.isEmpty
                                      ? '点击选择待转换的 MP3 / M4A 音频...'
                                      : selectedFileName,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: textTheme.bodyMedium?.copyWith(
                                    fontWeight: selectedFileName.isEmpty
                                        ? FontWeight.normal
                                        : FontWeight.w600,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                '浏览',
                                style: textTheme.labelLarge?.copyWith(
                                  color: colorScheme.primary,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),
                    Text(
                      '输出采样率',
                      style: textTheme.labelMedium?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        ChoiceChip(
                          label: const Text('16kHz (识别专用)'),
                          selected: targetSampleRate == 16000,
                          onSelected: isConverting
                              ? null
                              : (_) => setModalState(
                                    () => targetSampleRate = 16000,
                                  ),
                        ),
                        ChoiceChip(
                          label: const Text('44.1kHz (标准音质)'),
                          selected: targetSampleRate == 44100,
                          onSelected: isConverting
                              ? null
                              : (_) => setModalState(
                                    () => targetSampleRate = 44100,
                                  ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    if (errorMessage != null)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: Text(
                          errorMessage!,
                          style: textTheme.bodySmall?.copyWith(
                            color: colorScheme.error,
                          ),
                        ),
                      ),
                    if (outputSavedPath != null)
                      Container(
                        width: double.infinity,
                        margin: const EdgeInsets.only(bottom: 12),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: colorScheme.primaryContainer
                              .withValues(alpha: 0.5),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          '转换成功！已保存至：\n$outputSavedPath',
                          style: textTheme.bodySmall?.copyWith(
                            color: colorScheme.onPrimaryContainer,
                            height: 1.4,
                          ),
                        ),
                      ),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        onPressed: (selectedInputPath == null || isConverting)
                            ? null
                            : startConvert,
                        icon: isConverting
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Icon(Icons.play_arrow_rounded),
                        label: Text(
                          isConverting ? '正在硬件解码转换中...' : '开始转换为 WAV',
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  /// 离线语音模型按需下载与管理弹窗
  void _showOfflineModelSheet(BuildContext context) {
    bool useChinaMirror = true;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setModalState) {
            final colorScheme = Theme.of(ctx).colorScheme;
            final textTheme = Theme.of(ctx).textTheme;

            return Consumer<PlayerProvider>(
              builder: (context, provider, _) {
                return SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(
                              Icons.downloading_rounded,
                              color: colorScheme.primary,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              '离线语音识别模型',
                              style: textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Text(
                          '模型仅在需要时下载到手机本地，离线运行、完全免费',
                          style: textTheme.bodySmall?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            Text(
                              '首选线路：',
                              style: textTheme.labelMedium?.copyWith(
                                color: colorScheme.onSurfaceVariant,
                              ),
                            ),
                            ChoiceChip(
                              label: const Text('国内镜像'),
                              selected: useChinaMirror,
                              onSelected: provider.downloadingModel != null
                                  ? null
                                  : (_) => setModalState(
                                        () => useChinaMirror = true,
                                      ),
                            ),
                            ChoiceChip(
                              label: const Text('HuggingFace 官方'),
                              selected: !useChinaMirror,
                              onSelected: provider.downloadingModel != null
                                  ? null
                                  : (_) => setModalState(
                                        () => useChinaMirror = false,
                                      ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 14),
                        ...OfflineAsrModelType.values.map((modelType) {
                          final isDownloaded =
                              provider.modelDownloadStatuses[modelType] ??
                                  false;
                          final isSelected =
                              provider.selectedOfflineModel == modelType;
                          final isDownloadingThis =
                              provider.downloadingModel == modelType;

                          return Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: Container(
                              padding: const EdgeInsets.all(14),
                              decoration: BoxDecoration(
                                color: isSelected && isDownloaded
                                    ? colorScheme.primaryContainer
                                        .withValues(alpha: 0.45)
                                    : colorScheme.surfaceContainerLow,
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(
                                  color: isSelected && isDownloaded
                                      ? colorScheme.primary
                                      : colorScheme.outlineVariant
                                          .withValues(alpha: 0.5),
                                ),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Wrap(
                                              spacing: 8,
                                              runSpacing: 4,
                                              crossAxisAlignment:
                                                  WrapCrossAlignment.center,
                                              children: [
                                                Text(
                                                  modelType.title,
                                                  style: textTheme.titleSmall
                                                      ?.copyWith(
                                                    fontWeight: FontWeight.bold,
                                                  ),
                                                ),
                                                Container(
                                                  padding: const EdgeInsets
                                                      .symmetric(
                                                    horizontal: 8,
                                                    vertical: 2,
                                                  ),
                                                  decoration: BoxDecoration(
                                                    color: colorScheme
                                                        .secondaryContainer,
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                            6),
                                                  ),
                                                  child: Text(
                                                    modelType.sizeLabel,
                                                    style: textTheme.labelSmall
                                                        ?.copyWith(
                                                      color: colorScheme
                                                          .onSecondaryContainer,
                                                    ),
                                                  ),
                                                ),
                                              ],
                                            ),
                                            const SizedBox(height: 4),
                                            Text(
                                              modelType.description,
                                              style: textTheme.bodySmall
                                                  ?.copyWith(
                                                color: colorScheme
                                                    .onSurfaceVariant,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      if (isDownloadingThis)
                                        TextButton(
                                          onPressed:
                                              provider.cancelModelDownload,
                                          child: const Text('取消'),
                                        )
                                      else if (isDownloaded)
                                        Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            if (isSelected)
                                              Chip(
                                                label: const Text('使用中'),
                                                backgroundColor:
                                                    colorScheme.primary,
                                                labelStyle: TextStyle(
                                                  color: colorScheme.onPrimary,
                                                  fontSize: 12,
                                                ),
                                              )
                                            else
                                              OutlinedButton(
                                                onPressed: () =>
                                                    provider.selectOfflineModel(
                                                  modelType,
                                                ),
                                                child: const Text('启用'),
                                              ),
                                            IconButton(
                                              icon: const Icon(
                                                Icons.delete_outline_rounded,
                                                size: 20,
                                              ),
                                              tooltip: '删除模型释放空间',
                                              onPressed: () =>
                                                  provider.deleteOfflineModel(
                                                modelType,
                                              ),
                                            ),
                                          ],
                                        )
                                      else
                                        FilledButton.tonalIcon(
                                          onPressed:
                                              provider.downloadingModel != null
                                                  ? null
                                                  : () async {
                                                      final err = await provider
                                                          .downloadOfflineModel(
                                                        modelType,
                                                        useChinaMirror:
                                                            useChinaMirror,
                                                      );
                                                      if (ctx.mounted &&
                                                          err != null) {
                                                        ScaffoldMessenger.of(
                                                                ctx)
                                                            .showSnackBar(
                                                          SnackBar(
                                                            content: Text(err),
                                                          ),
                                                        );
                                                      }
                                                    },
                                          icon: const Icon(
                                            Icons.download_rounded,
                                            size: 18,
                                          ),
                                          label: const Text('下载'),
                                        ),
                                    ],
                                  ),
                                  if (isDownloadingThis) ...[
                                    const SizedBox(height: 10),
                                    LinearProgressIndicator(
                                      value: provider.downloadProgress > 0
                                          ? provider.downloadProgress
                                          : null,
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      '正在下载模型... ${(provider.downloadProgress * 100).toStringAsFixed(1)}%',
                                      style: textTheme.labelSmall?.copyWith(
                                        color: colorScheme.primary,
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          );
                        }),
                      ],
                    ),
                  ),
                );
              },
            );
          },
        );
      },
    );
  }

  /// DeepSeek 翻译 API 配置弹窗
  void _showDeepSeekConfigSheet(
    BuildContext context,
    PlayerProvider provider,
  ) {
    final current = provider.deepSeekConfig;
    final urlCtrl = TextEditingController(text: current.baseUrl);
    final keyCtrl = TextEditingController(text: current.apiKey);
    final modelCtrl = TextEditingController(text: current.model);
    bool obscureKey = true;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) {
        final colorScheme = Theme.of(ctx).colorScheme;
        final textTheme = Theme.of(ctx).textTheme;

        return StatefulBuilder(
          builder: (ctx, setModalState) {
            return Padding(
              padding: EdgeInsets.fromLTRB(
                20,
                4,
                20,
                MediaQuery.of(ctx).viewInsets.bottom + 24,
              ),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'DeepSeek 双语翻译配置',
                      style: textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '本地离线识别出英文后，自动调用 DeepSeek 翻译为中文（不填 Key 也可生成纯英文字幕）',
                      style: textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        ActionChip(
                          label: const Text('deepseek-flash (极速推荐)'),
                          onPressed: () {
                            setModalState(() {
                              urlCtrl.text = 'https://api.deepseek.com';
                              modelCtrl.text = 'deepseek-flash';
                            });
                          },
                        ),
                        ActionChip(
                          label: const Text('deepseek-v4-pro'),
                          onPressed: () {
                            setModalState(() {
                              urlCtrl.text = 'https://api.deepseek.com';
                              modelCtrl.text = 'deepseek-v4-pro';
                            });
                          },
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    TextField(
                      controller: urlCtrl,
                      decoration: const InputDecoration(
                        labelText: 'API Base URL',
                        hintText: 'https://api.deepseek.com',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: keyCtrl,
                      obscureText: obscureKey,
                      decoration: InputDecoration(
                        labelText: 'DeepSeek API Key',
                        hintText: 'sk-...',
                        border: const OutlineInputBorder(),
                        suffixIcon: IconButton(
                          icon: Icon(
                            obscureKey
                                ? Icons.visibility_outlined
                                : Icons.visibility_off_outlined,
                          ),
                          onPressed: () =>
                              setModalState(() => obscureKey = !obscureKey),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: modelCtrl,
                      decoration: const InputDecoration(
                        labelText: '翻译模型 ID',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 18),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        onPressed: () async {
                          await provider.updateDeepSeekConfig(
                            DeepSeekApiConfig(
                              baseUrl: urlCtrl.text,
                              apiKey: keyCtrl.text,
                              model: modelCtrl.text,
                            ),
                          );
                          if (ctx.mounted) Navigator.pop(ctx);
                        },
                        child: const Text('保存配置'),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  void _showVersionHistorySheet(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.history_rounded, color: colorScheme.primary),
                    const SizedBox(width: 8),
                    Text(
                      '历史版本',
                      style: textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                ConstrainedBox(
                  constraints: BoxConstraints(
                    maxHeight: MediaQuery.of(ctx).size.height * 0.55,
                  ),
                  child: ListView.separated(
                    shrinkWrap: true,
                    itemCount: appVersionHistory.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 10),
                    itemBuilder: (_, index) {
                      final item = appVersionHistory[index];
                      final isLatest = index == 0;

                      return Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: colorScheme.surfaceContainerLow,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: isLatest
                                ? colorScheme.primary.withValues(alpha: 0.35)
                                : colorScheme.outlineVariant
                                    .withValues(alpha: 0.5),
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 10,
                                    vertical: 3,
                                  ),
                                  decoration: BoxDecoration(
                                    color: isLatest
                                        ? colorScheme.primaryContainer
                                        : colorScheme.secondaryContainer,
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Text(
                                    item.version,
                                    style: textTheme.labelLarge?.copyWith(
                                      fontWeight: FontWeight.bold,
                                      color: isLatest
                                          ? colorScheme.onPrimaryContainer
                                          : colorScheme.onSecondaryContainer,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Text(
                                  item.date,
                                  style: textTheme.bodySmall?.copyWith(
                                    color: colorScheme.onSurfaceVariant,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 10),
                            ...item.changes.map(
                              (line) => Padding(
                                padding: const EdgeInsets.only(bottom: 4),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      '•  ',
                                      style: TextStyle(
                                        color: colorScheme.primary,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    Expanded(
                                      child: Text(
                                        line,
                                        style: textTheme.bodySmall?.copyWith(
                                          height: 1.4,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final latestVersion = appVersionHistory.isNotEmpty
        ? appVersionHistory.first.version
        : 'v0.1.0';

    return Consumer<PlayerProvider>(
      builder: (context, provider, _) {
        final modelReady = provider.isSelectedOfflineModelReady;
        final deepSeekReady = provider.deepSeekConfig.isConfigured;

        return Scaffold(
          appBar: AppBar(
            title: const Text('设置'),
            centerTitle: false,
          ),
          body: ListView(
            padding: const EdgeInsets.fromLTRB(14, 8, 14, 20),
            children: [
              _SettingsEntryCard(
                icon: Icons.downloading_rounded,
                title: '离线语音识别模型',
                subtitle: modelReady
                    ? '已就绪 (${provider.selectedOfflineModel.title})'
                    : '未下载，点击选择并按需下载',
                highlightSubtitle: modelReady,
                onTap: () => _showOfflineModelSheet(context),
              ),
              const SizedBox(height: 8),
              _SettingsEntryCard(
                icon: Icons.translate_rounded,
                title: 'DeepSeek 双语翻译配置',
                subtitle: deepSeekReady
                    ? '已配置 (${provider.deepSeekConfig.model})'
                    : '未填写 API Key（可选）',
                highlightSubtitle: deepSeekReady,
                onTap: () => _showDeepSeekConfigSheet(context, provider),
              ),
              const SizedBox(height: 8),
              _SettingsEntryCard(
                icon: Icons.transform_rounded,
                title: '音频格式转换器 (转 WAV)',
                subtitle: '将 MP3 / M4A / AAC 转为标准 WAV',
                onTap: () => _showAudioConverterSheet(context),
              ),
              const SizedBox(height: 8),
              _SettingsEntryCard(
                icon: Icons.history_rounded,
                title: '历史版本',
                subtitle: '当前版本 $latestVersion',
                onTap: () => _showVersionHistorySheet(context),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _SettingsEntryCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final bool highlightSubtitle;
  final VoidCallback onTap;

  const _SettingsEntryCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    this.highlightSubtitle = false,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Card(
      margin: EdgeInsets.zero,
      elevation: 0,
      color: colorScheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: colorScheme.outlineVariant.withValues(alpha: 0.5),
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 12,
          vertical: 2,
        ),
        horizontalTitleGap: 10,
        minLeadingWidth: 0,
        visualDensity: VisualDensity.compact,
        leading: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: colorScheme.primaryContainer,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(
            icon,
            size: 20,
            color: colorScheme.onPrimaryContainer,
          ),
        ),
        title: Text(
          title,
          style: textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
        subtitle: Text(
          subtitle,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: textTheme.bodySmall?.copyWith(
            color: highlightSubtitle
                ? colorScheme.primary
                : colorScheme.onSurfaceVariant,
          ),
        ),
        trailing: Icon(
          Icons.chevron_right_rounded,
          size: 20,
          color: colorScheme.onSurfaceVariant,
        ),
        onTap: onTap,
      ),
    );
  }
}