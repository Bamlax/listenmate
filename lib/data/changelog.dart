class VersionRecord {
  final String version;
  final String date;
  final List<String> changes;

  const VersionRecord({
    required this.version,
    required this.date,
    required this.changes,
  });
}

/// 应用历史版本记录（按时间倒序排列，第 1 条会自动作为设置页显示的“当前版本”）
/// 如需新增版本，只需复制一条 VersionRecord 粘贴到列表最上方即可。
const List<VersionRecord> appVersionHistory = [
  VersionRecord(
    version: 'v0.1.0',
    date: '2026-11-19',
    changes: [
      '支持四六级听力音频播放、自定义倍速与快进/快退',
      '支持重点时间节点标注与点击即时复听',
      '支持离线语音识别与 DeepSeek 双语字幕生成',
    ],
  ),
];