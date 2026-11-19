import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/audio_item.dart';
import '../providers/player_provider.dart';
import '../widgets/playlist_sheet.dart';
import '../widgets/subtitle_panel.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  bool _isDragging = false;
  double _dragValueMs = 0;

  void _openPlaylistSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => const PlaylistSheet(),
    );
  }

  /// 自定义倍速弹窗
  void _showSpeedDialog(PlayerProvider provider) {
    const presets = [0.75, 0.9, 1.0, 1.15, 1.25, 1.5];
    double tempSpeed = provider.speed;

    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setModalState) {
            final colorScheme = Theme.of(ctx).colorScheme;
            return SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          '播放倍速设置',
                          style: Theme.of(ctx).textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.bold,
                              ),
                        ),
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
                            '${tempSpeed.toStringAsFixed(2)}x',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: colorScheme.onPrimaryContainer,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Slider(
                      value: tempSpeed,
                      min: 0.5,
                      max: 2.0,
                      divisions: 30,
                      label: '${tempSpeed.toStringAsFixed(2)}x',
                      onChanged: (val) {
                        setModalState(() => tempSpeed = val);
                        provider.setSpeed(val);
                      },
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: presets.map((preset) {
                        final selected = (tempSpeed - preset).abs() < 0.01;
                        return ChoiceChip(
                          label: Text('${preset}x'),
                          selected: selected,
                          onSelected: (_) {
                            setModalState(() => tempSpeed = preset);
                            provider.setSpeed(preset);
                          },
                        );
                      }).toList(),
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

  /// 自定义快进/快退秒数弹窗（与播放倍速交互样式一致）
  void _showSeekSecondsDialog(PlayerProvider provider) {
    const presets = [2, 3, 5, 10, 15, 20];
    int tempSeconds = provider.seekSeconds.clamp(1, 30);

    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setModalState) {
            final colorScheme = Theme.of(ctx).colorScheme;
            return SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          '快进 / 快退秒数设置',
                          style: Theme.of(ctx).textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.bold,
                              ),
                        ),
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
                            '$tempSeconds 秒',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: colorScheme.onPrimaryContainer,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Slider(
                      value: tempSeconds.toDouble(),
                      min: 1,
                      max: 30,
                      divisions: 29,
                      label: '$tempSeconds 秒',
                      onChanged: (val) {
                        final sec = val.round();
                        setModalState(() => tempSeconds = sec);
                        provider.setSeekSeconds(sec);
                      },
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: presets.map((preset) {
                        final selected = tempSeconds == preset;
                        return ChoiceChip(
                          label: Text('$preset 秒'),
                          selected: selected,
                          onSelected: (_) {
                            setModalState(() => tempSeconds = preset);
                            provider.setSeekSeconds(preset);
                          },
                        );
                      }).toList(),
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

  /// 编辑节点名称弹窗
  void _showRenameMarkerDialog(PlayerProvider provider, AudioMarker marker) {
    final controller = TextEditingController(text: marker.label);

    showDialog(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: Text(
            '编辑节点 (${formatDuration(Duration(milliseconds: marker.positionMs))})',
          ),
          content: TextField(
            controller: controller,
            autofocus: true,
            decoration: const InputDecoration(
              labelText: '节点备注（如：长对话第2题、连读难点）',
              border: OutlineInputBorder(),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () {
                provider.renameMarker(marker.id, controller.text);
                Navigator.pop(ctx);
              },
              child: const Text('保存'),
            ),
          ],
        );
      },
    );
  }

  IconData _loopModeIcon(PlayLoopMode mode) {
    switch (mode) {
      case PlayLoopMode.sequence:
        return Icons.arrow_forward_rounded;
      case PlayLoopMode.singleLoop:
        return Icons.repeat_one_rounded;
      case PlayLoopMode.listLoop:
        return Icons.repeat_rounded;
    }
  }

  String _loopModeTooltip(PlayLoopMode mode) {
    switch (mode) {
      case PlayLoopMode.sequence:
        return '顺序播放';
      case PlayLoopMode.singleLoop:
        return '单曲循环';
      case PlayLoopMode.listLoop:
        return '列表循环';
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Consumer<PlayerProvider>(
      builder: (context, provider, _) {
        final currentItem = provider.currentItem;
        final totalMs = provider.duration.inMilliseconds.toDouble();
        final currentMs = _isDragging
            ? _dragValueMs
            : provider.position.inMilliseconds
                .toDouble()
                .clamp(0.0, totalMs > 0 ? totalMs : 1.0);

        return Scaffold(
          appBar: AppBar(
            title: const Text('听力助手'),
            centerTitle: false,
            actions: [
              Padding(
                padding: const EdgeInsets.only(right: 12),
                child: FilledButton.tonalIcon(
                  onPressed: _openPlaylistSheet,
                  icon: const Icon(Icons.queue_music_rounded, size: 20),
                  label: Text('播放列表 (${provider.playlist.length})'),
                ),
              ),
            ],
          ),
          body: ListView(
            padding: const EdgeInsets.fromLTRB(14, 8, 14, 28),
            children: [
              // 1. 当前音频与加长进度条卡片
              Card(
                elevation: 0,
                color: colorScheme.surfaceContainerLow,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(24),
                  side: BorderSide(
                    color: colorScheme.outlineVariant.withValues(alpha: 0.5),
                  ),
                ),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 18, 12, 18),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 6),
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: colorScheme.primaryContainer,
                                borderRadius: BorderRadius.circular(14),
                              ),
                              child: Icon(
                                Icons.headphones_rounded,
                                color: colorScheme.onPrimaryContainer,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    currentItem?.title ?? '未选择听力音频',
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: textTheme.titleMedium?.copyWith(
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    currentItem == null
                                        ? '点击右上角“播放列表”导入四六级真题音频'
                                        : '第 ${provider.currentIndex + 1} / ${provider.playlist.length} 首',
                                    style: textTheme.bodySmall?.copyWith(
                                      color: colorScheme.onSurfaceVariant,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),

                      // 加长版进度条
                      SliderTheme(
                        data: SliderTheme.of(context).copyWith(
                          trackHeight: 5,
                          thumbShape: const RoundSliderThumbShape(
                            enabledThumbRadius: 7,
                          ),
                          overlayShape: const RoundSliderOverlayShape(
                            overlayRadius: 14,
                          ),
                          trackShape: const RoundedRectSliderTrackShape(),
                        ),
                        child: Slider(
                          value: totalMs > 0 ? currentMs : 0.0,
                          min: 0.0,
                          max: totalMs > 0 ? totalMs : 1.0,
                          onChanged: currentItem == null || totalMs <= 0
                              ? null
                              : (val) {
                                  setState(() {
                                    _isDragging = true;
                                    _dragValueMs = val;
                                  });
                                },
                          onChangeEnd: currentItem == null || totalMs <= 0
                              ? null
                              : (val) {
                                  provider.seekTo(
                                    Duration(milliseconds: val.round()),
                                  );
                                  setState(() => _isDragging = false);
                                },
                        ),
                      ),

                      // 时间轴节点刻度指示条
                      if (currentItem != null &&
                          currentItem.markers.isNotEmpty &&
                          totalMs > 0)
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 14),
                          child: SizedBox(
                            height: 10,
                            child: LayoutBuilder(
                              builder: (context, constraints) {
                                return Stack(
                                  children: currentItem.markers.map((marker) {
                                    final ratio = (marker.positionMs / totalMs)
                                        .clamp(0.0, 1.0);
                                    return Positioned(
                                      left: ratio * (constraints.maxWidth - 8),
                                      top: 1,
                                      child: GestureDetector(
                                        onTap: () =>
                                            provider.replayFromMarker(marker),
                                        child: Container(
                                          width: 8,
                                          height: 8,
                                          decoration: BoxDecoration(
                                            color: colorScheme.primary,
                                            shape: BoxShape.circle,
                                          ),
                                        ),
                                      ),
                                    );
                                  }).toList(),
                                );
                              },
                            ),
                          ),
                        ),

                      // 时间数字
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 14),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              formatDuration(
                                Duration(milliseconds: currentMs.round()),
                              ),
                              style: textTheme.labelMedium?.copyWith(
                                color: colorScheme.primary,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            Text(
                              formatDuration(provider.duration),
                              style: textTheme.labelMedium?.copyWith(
                                color: colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 14),

                      // 主播放控制按钮栏
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            SizedBox(
                              width: 40,
                              height: 40,
                              child: IconButton(
                                padding: EdgeInsets.zero,
                                iconSize: 22,
                                onPressed: provider.cycleLoopMode,
                                icon: Icon(_loopModeIcon(provider.loopMode)),
                                tooltip: _loopModeTooltip(provider.loopMode),
                              ),
                            ),
                            SizedBox(
                              width: 72,
                              height: 38,
                              child: FilledButton.tonal(
                                onPressed: currentItem == null
                                    ? null
                                    : provider.seekBackward,
                                style: FilledButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                  ),
                                ),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    const Icon(
                                      Icons.fast_rewind_rounded,
                                      size: 18,
                                    ),
                                    const SizedBox(width: 3),
                                    Text(
                                      '${provider.seekSeconds}s',
                                      style: textTheme.labelMedium?.copyWith(
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            SizedBox(
                              width: 52,
                              height: 52,
                              child: FilledButton(
                                onPressed: currentItem == null
                                    ? null
                                    : provider.togglePlayPause,
                                style: FilledButton.styleFrom(
                                  shape: const CircleBorder(),
                                  padding: EdgeInsets.zero,
                                ),
                                child: Icon(
                                  provider.isPlaying
                                      ? Icons.pause_rounded
                                      : Icons.play_arrow_rounded,
                                  size: 28,
                                ),
                              ),
                            ),
                            SizedBox(
                              width: 72,
                              height: 38,
                              child: FilledButton.tonal(
                                onPressed: currentItem == null
                                    ? null
                                    : provider.seekForward,
                                style: FilledButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                  ),
                                ),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Text(
                                      '${provider.seekSeconds}s',
                                      style: textTheme.labelMedium?.copyWith(
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    const SizedBox(width: 3),
                                    const Icon(
                                      Icons.fast_forward_rounded,
                                      size: 18,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            SizedBox(
                              width: 40,
                              height: 40,
                              child: IconButton(
                                padding: EdgeInsets.zero,
                                iconSize: 22,
                                onPressed: provider.playlist.length > 1
                                    ? provider.playNext
                                    : null,
                                icon: const Icon(Icons.skip_next_rounded),
                                tooltip: '下一首',
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 14),

              // 2. 自定义倍速 & 快进/快退卡片
              Row(
                children: [
                  Expanded(
                    child: _SettingTileCard(
                      icon: Icons.speed_rounded,
                      title: '播放倍速',
                      value: '${provider.speed.toStringAsFixed(2)}x',
                      onTap: () => _showSpeedDialog(provider),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _SettingTileCard(
                      icon: Icons.swap_horiz_rounded,
                      title: '快进/快退',
                      value: '${provider.seekSeconds} 秒',
                      onTap: () => _showSeekSecondsDialog(provider),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 20),

              // 3. 双语字幕区域
              const SubtitlePanel(),

              const SizedBox(height: 20),

              // 4. 节点标注区域
              Row(
                children: [
                  Icon(
                    Icons.bookmark_added_rounded,
                    color: colorScheme.primary,
                    size: 22,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '听力节点标注',
                    style: textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const Spacer(),
                  FilledButton.icon(
                    onPressed: currentItem == null
                        ? null
                        : () => provider.addMarkerAtCurrentPosition(),
                    icon: const Icon(Icons.add_location_alt_rounded, size: 18),
                    label: const Text('标注当前点'),
                  ),
                ],
              ),
              const SizedBox(height: 12),

              if (currentItem == null || currentItem.markers.isEmpty)
                Container(
                  padding: const EdgeInsets.all(20),
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
                        Icons.tips_and_updates_outlined,
                        color: colorScheme.primary,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          '听到没听清的句子时，点击右上角“标注当前点”。之后点击任意标注卡片，即可立即跳回该时间点反复精听。',
                          style: textTheme.bodySmall?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                            height: 1.4,
                          ),
                        ),
                      ),
                    ],
                  ),
                )
              else
                ListView.separated(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: currentItem.markers.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (context, index) {
                    final marker = currentItem.markers[index];
                    final timeText = formatDuration(
                      Duration(milliseconds: marker.positionMs),
                    );

                    return Material(
                      color: colorScheme.surfaceContainerLow,
                      borderRadius: BorderRadius.circular(16),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(16),
                        onTap: () => provider.replayFromMarker(marker),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 10,
                          ),
                          child: Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 6,
                                ),
                                decoration: BoxDecoration(
                                  color: colorScheme.primaryContainer,
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      Icons.play_circle_fill_rounded,
                                      size: 16,
                                      color: colorScheme.primary,
                                    ),
                                    const SizedBox(width: 4),
                                    Text(
                                      timeText,
                                      style: textTheme.labelLarge?.copyWith(
                                        fontWeight: FontWeight.bold,
                                        color: colorScheme.onPrimaryContainer,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  marker.label,
                                  style: textTheme.bodyMedium?.copyWith(
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ),
                              IconButton(
                                icon: const Icon(Icons.edit_outlined, size: 20),
                                tooltip: '重命名备注',
                                onPressed: () =>
                                    _showRenameMarkerDialog(provider, marker),
                              ),
                              IconButton(
                                icon: const Icon(Icons.close_rounded, size: 20),
                                tooltip: '删除标注',
                                onPressed: () =>
                                    provider.deleteMarker(marker.id),
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
            ],
          ),
        );
      },
    );
  }
}

class _SettingTileCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String value;
  final VoidCallback onTap;

  const _SettingTileCard({
    required this.icon,
    required this.title,
    required this.value,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Material(
      color: colorScheme.secondaryContainer.withValues(alpha: 0.45),
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              Icon(icon, color: colorScheme.primary, size: 22),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: textTheme.labelMedium?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      value,
                      style: textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: colorScheme.primary,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.tune_rounded,
                size: 18,
                color: colorScheme.onSurfaceVariant,
              ),
            ],
          ),
        ),
      ),
    );
  }
}