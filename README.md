# ListenMate · 听力助手

一款基于 Flutter 与 Material Design 3 蓝色主题构建的 Android 英语听力精听工具，专为大学英语四、六级真题听力训练设计。

## 核心功能

- **精听播放控制**：支持 `0.5x ~ 2.0x` 连续自定义倍速、自定义快进/快退秒数，以及顺序、单曲循环、列表循环切换。
- **重点节点标注**：听到没听清的句子一键打点标注，支持自定义备注与进度条可视化刻度，点击卡片即可跳回对应时间点反复复听。
- **离线识别 + AI 双语字幕**：
  - 集成端侧 `whisper.cpp` 离线模型（支持设置页按需下载 `tiny` / `base` 模型，零识别接口费用）。
  - 接入 DeepSeek API（默认 `deepseek-flash`）自动生成地道中英双语对照字幕，支持「双语 / 仅英文 / 隐藏（盲听）」模式切换、实时时间轴微调与点击单句跳转。
- **内置硬件格式转换器**：基于 Android 原生 `MediaExtractor` 与 `MediaCodec` 实现硬件解码重采样，自动将 MP3 / M4A / AAC 等转为 16kHz 单声道 WAV 供识别使用，也支持在设置页手动转换导出。

## 快速上手

1. **导入音频**：点击主界面右上角「播放列表」，导入本地四、六级听力音频（MP3、M4A、WAV 等）。
2. **下载离线识别模型**：切换至底部「设置」页，打开「离线语音识别模型」，按需下载 `base` 或 `tiny` 模型（内置国内镜像与官方源自动容错切换）。
3. **配置翻译接口（可选）**：在「设置 → DeepSeek 双语翻译配置」填入 API Key，生成字幕时将自动补充中文译文；不填也可离线生成纯英文字幕。

## 项目结构

```text
lib/
├── main.dart                     # 应用入口、MD3 蓝色主题与底部导航栏
├── data/
│   └── changelog.dart            # 独立版本历史记录（同步驱动设置页与 CI Release 日志）
├── models/
│   └── audio_item.dart           # 音频、节点标注与双语字幕数据模型
├── providers/
│   └── player_provider.dart      # 播放状态、字幕同步与离线模型管理
├── screens/
│   ├── home_screen.dart          # 听力精听主界面
│   └── settings_screen.dart      # 设置中心（模型下载、DeepSeek 配置、WAV 转换器）
├── services/
│   ├── audio_converter_service.dart # 调用 Android 原生硬件转码通道
│   ├── model_manager_service.dart   # 离线模型流式下载与校验
│   ├── storage_service.dart         # 本地偏好与播放列表持久化
│   └── subtitle_service.dart        # 离线识别与 DeepSeek 批量翻译编排
└── widgets/
    ├── playlist_sheet.dart       # 播放列表底部弹窗
    └── subtitle_panel.dart       # 双语字幕滚动与时间轴微调面板