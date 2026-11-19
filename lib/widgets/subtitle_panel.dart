import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:provider/provider.dart';
import '../models/audio_item.dart';
import '../providers/player_provider.dart';

class SubtitlePanel extends StatefulWidget {
  const SubtitlePanel({super.key});

  @override
  State<SubtitlePanel> createState() => _SubtitlePanelState();
}

class _SubtitlePanelState extends State<SubtitlePanel> {
  final ScrollController _scrollController = ScrollController();
  final Map<int, GlobalKey> _cueKeys = {};
  int _lastScrolledIndex = -1;
  String? _lastTrackId;

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  GlobalKey _keyForIndex(int index) {
    return _cueKeys.putIfAbsent(index, () => GlobalKey());
  }

  /// 仅滚动内部字幕列表，避免 Scrollable.ensureVisible 连带滚动外层整个页面
  void _scrollToActiveCue(int index, int totalCount) {
    if (index < 0 || index == _lastScrolledIndex || totalCount <= 0) return;
    if (!_scrollController.hasClients) return;

    final targetContext = _cueKeys[index]?.currentContext;
    if (targetContext != null) {
      final renderObject = targetContext.findRenderObject();
      if (renderObject != null) {
        _lastScrolledIndex = index;
        final viewport = RenderAbstractViewport.of(renderObject);
        final revealedOffset = viewport.getOffsetToReveal(renderObject, 0.25);
        final targetOffset = revealedOffset.offset.clamp(
          0.0,
          _scrollController.position.maxScrollExtent,
        );
        _scrollController.animateTo(
          targetOffset,
          duration: const Duration(milliseconds: 240),
          curve: Curves.easeOutCubic,
        );
      }
      return;
    }

    // 目标项尚未进入可视区渲染时，先在内部列表预滚动触发构建，下一帧再精确对齐
    final maxExtent = _scrollController.position.maxScrollExtent;
    if (maxExtent > 0) {
      final roughOffset =
          ((index / totalCount) * maxExtent).clamp(0.0, maxExtent);
      _scrollController.jumpTo(roughOffset);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !_scrollController.hasClients) return;
        final retryContext = _cueKeys[index]?.currentContext;
        final retryRender = retryContext?.findRenderObject();
        if (retryRender != null) {
          _lastScrolledIndex = index;
          final viewport = RenderAbstractViewport.of(retryRender);
          final revealedOffset = viewport.getOffsetToReveal(retryRender, 0.25);
          final targetOffset = revealedOffset.offset.clamp(
            0.0,
            _scrollController.position.maxScrollExtent,
          );
          _scrollController.animateTo(
            targetOffset,
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOutCubic,
          );
        }
      });
    }
  }

  /// 重新生成字幕二次确认弹窗
  Future<void> _confirmRegenerate(
    BuildContext context,
    PlayerProvider provider,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: const Text('重新生成字幕'),
          content: const Text('确定要重新识别并生成双语字幕吗？这将会覆盖当前已有的字幕内容。'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('确定'),
            ),
          ],
        );
      },
    );

    if (confirmed == true && context.mounted) {
      await _handleGenerate(context, provider);
    }
  }

  Future<void> _handleGenerate(
    BuildContext context,
    PlayerProvider provider,
  ) async {
    final error = await provider.generateSubtitlesForCurrent();
    if (!context.mounted) return;

    if (error != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(error),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } else {
      _lastScrolledIndex = -1;
      final hasTranslation = provider.deepSeekConfig.isConfigured;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            hasTranslation
                ? '双语字幕生成完成，点击任意句子可跳转精听'
                : '已离线生成纯英文字幕（在设置填入 DeepSeek Key 可自动翻译中文）',
          ),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  /// 时间轴同步微调弹窗
  void _showTimelineSyncSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      builder: (ctx) {
        return Consumer<PlayerProvider>(
          builder: (ctx, provider, _) {
            final colorScheme = Theme.of(ctx).colorScheme;
            final textTheme = Theme.of(ctx).textTheme;
            final shiftMs = provider.subtitleShiftMs;

            return SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.timer_outlined, color: colorScheme.primary),
                        const SizedBox(width: 8),
                        Text(
                          '字幕时间轴同步',
                          style: textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const Spacer(),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: colorScheme.primaryContainer,
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            _formatShiftLabel(shiftMs),
                            style: textTheme.labelLarge?.copyWith(
                              fontWeight: FontWeight.bold,
                              color: colorScheme.onPrimaryContainer,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '若字幕高亮比人声慢，请调为“提前”；若字幕出现过早，请调为“延后”',
                      style: textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Slider(
                      value: shiftMs.toDouble().clamp(-3000.0, 3000.0),
                      min: -3000,
                      max: 3000,
                      divisions: 60,
                      label: _formatShiftLabel(shiftMs),
                      onChanged: (val) {
                        final delta = val.round() - shiftMs;
                        provider.adjustSubtitleShift(delta);
                      },
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        ActionChip(
                          label: const Text('提前 0.5s'),
                          onPressed: () => provider.adjustSubtitleShift(500),
                        ),
                        ActionChip(
                          label: const Text('提前 0.2s'),
                          onPressed: () => provider.adjustSubtitleShift(200),
                        ),
                        ActionChip(
                          label: const Text('延后 0.2s'),
                          onPressed: () => provider.adjustSubtitleShift(-200),
                        ),
                        ActionChip(
                          label: const Text('延后 0.5s'),
                          onPressed: () => provider.adjustSubtitleShift(-500),
                        ),
                        OutlinedButton.icon(
                          onPressed: provider.resetSubtitleShift,
                          icon: const Icon(Icons.restart_alt_rounded, size: 16),
                          label: const Text('恢复默认'),
                        ),
                      ],
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

  String _modeLabel(SubtitleDisplayMode mode) {
    switch (mode) {
      case SubtitleDisplayMode.bilingual:
        return '双语';
      case SubtitleDisplayMode.englishOnly:
        return '仅英文';
      case SubtitleDisplayMode.hidden:
        return '隐藏';
    }
  }

  SubtitleDisplayMode _nextMode(SubtitleDisplayMode current) {
    final nextIdx = (current.index + 1) % SubtitleDisplayMode.values.length;
    return SubtitleDisplayMode.values[nextIdx];
  }

  String _formatShiftLabel(int shiftMs) {
    if (shiftMs == 0) return '同步 0.0s';
    final sec = (shiftMs.abs() / 1000.0).toStringAsFixed(1);
    return shiftMs > 0 ? '提前 ${sec}s' : '延后 ${sec}s';
  }

  String _buildGuideText(PlayerProvider provider) {
    if (!provider.isSelectedOfflineModelReady) {
      return '尚未下载离线语音模型：请先前往底部“设置 → 离线语音识别模型”按需下载模型（无需预装）。';
    }
    if (!provider.deepSeekConfig.isConfigured) {
      return '离线识别模型已就绪！可直接点击右上角提取英文字幕；若在“设置”填入 DeepSeek API Key，将自动生成中英双语对照。';
    }
    return '离线识别模型与 DeepSeek 翻译均已就绪，点击右上角一键生成双语字幕。';
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Consumer<PlayerProvider>(
      builder: (context, provider, _) {
        final currentItem = provider.currentItem;
        if (currentItem?.id != _lastTrackId) {
          _lastTrackId = currentItem?.id;
          _cueKeys.clear();
          _lastScrolledIndex = -1;
        }

        final subtitles = currentItem?.subtitles ?? [];
        final activeIdx = provider.activeSubtitleIndex;

        if (provider.subtitleMode != SubtitleDisplayMode.hidden &&
            subtitles.isNotEmpty) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            _scrollToActiveCue(activeIdx, subtitles.length);
          });
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.subtitles_rounded,
                  color: colorScheme.primary,
                  size: 22,
                ),
                const SizedBox(width: 8),
                Text(
                  '双语字幕',
                  style: textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const Spacer(),
                if (subtitles.isNotEmpty) ...[
                  ActionChip(
                    visualDensity: VisualDensity.compact,
                    avatar: const Icon(Icons.translate_rounded, size: 15),
                    label: Text(_modeLabel(provider.subtitleMode)),
                    onPressed: () => provider.setSubtitleMode(
                      _nextMode(provider.subtitleMode),
                    ),
                  ),
                  const SizedBox(width: 6),
                  ActionChip(
                    visualDensity: VisualDensity.compact,
                    avatar: const Icon(Icons.timer_outlined, size: 15),
                    label: const Text('时间轴'),
                    onPressed: () => _showTimelineSyncSheet(context),
                  ),
                  IconButton(
                    icon: const Icon(Icons.refresh_rounded, size: 20),
                    tooltip: '重新识别生成字幕',
                    visualDensity: VisualDensity.compact,
                    onPressed:
                        (currentItem == null || provider.isGeneratingSubtitles)
                            ? null
                            : () => _confirmRegenerate(context, provider),
                  ),
                ] else
                  FilledButton.tonalIcon(
                    onPressed:
                        (currentItem == null || provider.isGeneratingSubtitles)
                            ? null
                            : () => _handleGenerate(context, provider),
                    icon: const Icon(Icons.auto_awesome_rounded, size: 18),
                    label: const Text('生成双语字幕'),
                  ),
              ],
            ),
            const SizedBox(height: 10),
            if (provider.isGeneratingSubtitles)
              _SubtitleProgressCard(
                progress: provider.subtitleProgress,
                statusText: provider.subtitleStatusText,
                hasDeepSeek: provider.deepSeekConfig.isConfigured,
              )
            else if (currentItem == null || subtitles.isEmpty)
              Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: colorScheme.surfaceContainerLowest,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: colorScheme.outlineVariant.withValues(alpha: 0.5),
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.closed_caption_off_rounded,
                      color: colorScheme.primary,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        _buildGuideText(provider),
                        style: textTheme.bodySmall?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                          height: 1.4,
                        ),
                      ),
                    ),
                  ],
                ),
              )
            else if (provider.subtitleMode == SubtitleDisplayMode.hidden)
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                decoration: BoxDecoration(
                  color: colorScheme.surfaceContainerLow,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.visibility_off_outlined,
                      size: 20,
                      color: colorScheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        '盲听练习模式：双语字幕已隐藏（共 ${subtitles.length} 句）',
                        style: textTheme.bodySmall?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                    TextButton(
                      onPressed: () => provider
                          .setSubtitleMode(SubtitleDisplayMode.bilingual),
                      child: const Text('显示双语'),
                    ),
                  ],
                ),
              )
            else
              Container(
                height: 248,
                decoration: BoxDecoration(
                  color: colorScheme.surfaceContainerLow,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: colorScheme.outlineVariant.withValues(alpha: 0.5),
                  ),
                ),
                clipBehavior: Clip.antiAlias,
                child: ListView.separated(
                  controller: _scrollController,
                  padding: const EdgeInsets.all(10),
                  itemCount: subtitles.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 6),
                  itemBuilder: (context, index) {
                    final cue = subtitles[index];
                    final isActive = index == activeIdx;
                    final displayStartMs =
                        (cue.startMs - provider.subtitleShiftMs)
                            .clamp(0, cue.startMs);
                    final timeStr = formatDuration(
                      Duration(milliseconds: displayStartMs),
                    );

                    return Container(
                      key: _keyForIndex(index),
                      child: Material(
                        color: isActive
                            ? colorScheme.primaryContainer
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(12),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(12),
                          onTap: () => provider.replayFromSubtitle(cue),
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(12, 8, 6, 8),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Padding(
                                  padding: const EdgeInsets.only(top: 2),
                                  child: Text(
                                    timeStr,
                                    style: textTheme.labelSmall?.copyWith(
                                      color: isActive
                                          ? colorScheme.primary
                                          : colorScheme.outline,
                                      fontWeight: isActive
                                          ? FontWeight.bold
                                          : FontWeight.normal,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        cue.english,
                                        style: textTheme.bodyMedium?.copyWith(
                                          fontWeight: isActive
                                              ? FontWeight.bold
                                              : FontWeight.w500,
                                          color: isActive
                                              ? colorScheme.onPrimaryContainer
                                              : colorScheme.onSurface,
                                          height: 1.35,
                                        ),
                                      ),
                                      if (provider.subtitleMode ==
                                              SubtitleDisplayMode.bilingual &&
                                          cue.chinese.isNotEmpty) ...[
                                        const SizedBox(height: 3),
                                        Text(
                                          cue.chinese,
                                          style: textTheme.bodySmall?.copyWith(
                                            color: isActive
                                                ? colorScheme.onPrimaryContainer
                                                    .withValues(alpha: 0.85)
                                                : colorScheme.onSurfaceVariant,
                                            height: 1.35,
                                          ),
                                        ),
                                      ],
                                    ],
                                  ),
                                ),
                                IconButton(
                                  icon: Icon(
                                    Icons.bookmark_add_outlined,
                                    size: 18,
                                    color: isActive
                                        ? colorScheme.primary
                                        : colorScheme.outline,
                                  ),
                                  tooltip: '将此句加入节点标注',
                                  onPressed: () {
                                    provider.bookmarkSubtitleCue(cue);
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: Text('已标注时间点 $timeStr'),
                                        duration: const Duration(seconds: 1),
                                        behavior: SnackBarBehavior.floating,
                                      ),
                                    );
                                  },
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
          ],
        );
      },
    );
  }
}

class _SubtitleProgressCard extends StatelessWidget {
  final double progress;
  final String statusText;
  final bool hasDeepSeek;

  const _SubtitleProgressCard({
    required this.progress,
    required this.statusText,
    required this.hasDeepSeek,
  });

  int get _currentStage {
    if (progress < 0.15) return 1;
    if (progress < 0.75) return 2;
    return 3;
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final percentInt = (progress * 100).round().clamp(0, 100);
    final stage = _currentStage;

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: colorScheme.primaryContainer.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: colorScheme.primary.withValues(alpha: 0.35),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  statusText.isEmpty ? '正在处理...' : statusText,
                  style: textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: colorScheme.primary,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                decoration: BoxDecoration(
                  color: colorScheme.primary,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  '$percentInt%',
                  style: textTheme.labelMedium?.copyWith(
                    color: colorScheme.onPrimary,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: progress > 0 ? progress : null,
              minHeight: 8,
              backgroundColor: colorScheme.surfaceContainerHighest,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _StageLabel(
                step: 1,
                label: '格式转换',
                activeStep: stage,
              ),
              _StageLabel(
                step: 2,
                label: '离线识别',
                activeStep: stage,
              ),
              _StageLabel(
                step: 3,
                label: hasDeepSeek ? 'DeepSeek 翻译' : '生成字幕',
                activeStep: stage,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _StageLabel extends StatelessWidget {
  final int step;
  final String label;
  final int activeStep;

  const _StageLabel({
    required this.step,
    required this.label,
    required this.activeStep,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final isDone = activeStep > step;
    final isCurrent = activeStep == step;

    final Color color = (isDone || isCurrent)
        ? colorScheme.primary
        : colorScheme.onSurfaceVariant.withValues(alpha: 0.6);

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          isDone
              ? Icons.check_circle_rounded
              : (isCurrent
                  ? Icons.radio_button_checked_rounded
                  : Icons.radio_button_unchecked_rounded),
          size: 15,
          color: color,
        ),
        const SizedBox(width: 4),
        Text(
          label,
          style: textTheme.labelSmall?.copyWith(
            color: color,
            fontWeight: isCurrent ? FontWeight.bold : FontWeight.normal,
          ),
        ),
      ],
    );
  }
}