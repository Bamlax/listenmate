import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/player_provider.dart';

class PlaylistSheet extends StatelessWidget {
  const PlaylistSheet({super.key});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Consumer<PlayerProvider>(
      builder: (context, provider, _) {
        final playlist = provider.playlist;

        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Icon(Icons.queue_music_rounded, color: colorScheme.primary),
                    const SizedBox(width: 8),
                    Text(
                      '播放列表 (${playlist.length})',
                      style: textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const Spacer(),
                    FilledButton.icon(
                      onPressed: () async {
                        final count = await provider.importAudioFiles();
                        if (context.mounted && count > 0) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('已导入 $count 个听力音频')),
                          );
                        }
                      },
                      icon: const Icon(Icons.add_rounded, size: 20),
                      label: const Text('导入音频'),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                if (playlist.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 40),
                    child: Column(
                      children: [
                        Icon(
                          Icons.library_music_outlined,
                          size: 48,
                          color: colorScheme.outline,
                        ),
                        const SizedBox(height: 12),
                        Text(
                          '暂无听力音频，点击右上角导入本地 MP3 / M4A 等文件',
                          style: textTheme.bodyMedium?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  )
                else
                  ConstrainedBox(
                    constraints: BoxConstraints(
                      maxHeight: MediaQuery.of(context).size.height * 0.5,
                    ),
                    child: ListView.separated(
                      shrinkWrap: true,
                      itemCount: playlist.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 6),
                      itemBuilder: (context, index) {
                        final item = playlist[index];
                        final isCurrent = index == provider.currentIndex;

                        return Material(
                          color: isCurrent
                              ? colorScheme.primaryContainer
                              : colorScheme.surfaceContainerLow,
                          borderRadius: BorderRadius.circular(14),
                          child: ListTile(
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                            leading: CircleAvatar(
                              backgroundColor: isCurrent
                                  ? colorScheme.primary
                                  : colorScheme.secondaryContainer,
                              foregroundColor: isCurrent
                                  ? colorScheme.onPrimary
                                  : colorScheme.onSecondaryContainer,
                              child: isCurrent
                                  ? const Icon(Icons.equalizer_rounded, size: 20)
                                  : Text('${index + 1}'),
                            ),
                            title: Text(
                              item.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontWeight: isCurrent
                                    ? FontWeight.bold
                                    : FontWeight.normal,
                                color: isCurrent
                                    ? colorScheme.onPrimaryContainer
                                    : colorScheme.onSurface,
                              ),
                            ),
                            subtitle: Text(
                              item.markers.isEmpty
                                  ? '暂无标注节点'
                                  : '已标注 ${item.markers.length} 个重点节点',
                              style: textTheme.bodySmall?.copyWith(
                                color: isCurrent
                                    ? colorScheme.onPrimaryContainer
                                        .withValues(alpha: 0.8)
                                    : colorScheme.onSurfaceVariant,
                              ),
                            ),
                            trailing: IconButton(
                              icon: const Icon(Icons.delete_outline_rounded),
                              tooltip: '从列表移除',
                              onPressed: () => provider.removeTrackAt(index),
                            ),
                            onTap: () {
                              provider.playTrackAt(index, autoPlay: true);
                              Navigator.pop(context);
                            },
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
}