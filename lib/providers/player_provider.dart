import 'dart:async';
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';
import 'package:just_audio_background/just_audio_background.dart';
import '../models/audio_item.dart';
import '../services/model_manager_service.dart';
import '../services/storage_service.dart';
import '../services/subtitle_service.dart';

enum PlayLoopMode {
  sequence,   // 顺序播放
  singleLoop, // 单曲循环
  listLoop,   // 列表循环
}

class PlayerProvider extends ChangeNotifier {
  final AudioPlayer _player = AudioPlayer();
  final StorageService _storage = StorageService();
  final ModelManagerService _modelManager = ModelManagerService();
  final SubtitleService _subtitleService = SubtitleService();

  List<AudioItem> _playlist = [];
  int _currentIndex = -1;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  bool _isPlaying = false;
  double _speed = 1.0;
  int _seekSeconds = 5;
  PlayLoopMode _loopMode = PlayLoopMode.sequence;

  // DeepSeek 翻译配置与字幕三步独立进度状态
  DeepSeekApiConfig _deepSeekConfig = const DeepSeekApiConfig();
  SubtitleDisplayMode _subtitleMode = SubtitleDisplayMode.bilingual;
  bool _isGeneratingSubtitles = false;
  SubtitleStageProgress _subtitleStageProgress = SubtitleStageProgress.initial;

  // 字幕时间轴偏移量（毫秒）：正值表示字幕提前显示，负值表示字幕延后显示
  int _subtitleShiftMs = 300;

  // 本地离线 ASR 模型管理状态
  OfflineAsrModelType _selectedOfflineModel = OfflineAsrModelType.baseEn;
  ModelStatusMap _modelDownloadStatuses = {
    OfflineAsrModelType.tinyEn: false,
    OfflineAsrModelType.baseEn: false,
  };
  OfflineAsrModelType? _downloadingModel;
  double _downloadProgress = 0.0;

  late final StreamSubscription<Duration> _posSub;
  late final StreamSubscription<Duration?> _durSub;
  late final StreamSubscription<PlayerState> _stateSub;

  List<AudioItem> get playlist => List.unmodifiable(_playlist);
  int get currentIndex => _currentIndex;
  AudioItem? get currentItem =>
      (_currentIndex >= 0 && _currentIndex < _playlist.length)
          ? _playlist[_currentIndex]
          : null;
  Duration get position => _position;
  Duration get duration => _duration;
  bool get isPlaying => _isPlaying;
  double get speed => _speed;
  int get seekSeconds => _seekSeconds;
  PlayLoopMode get loopMode => _loopMode;

  DeepSeekApiConfig get deepSeekConfig => _deepSeekConfig;
  SubtitleDisplayMode get subtitleMode => _subtitleMode;
  bool get isGeneratingSubtitles => _isGeneratingSubtitles;
  SubtitleStageProgress get subtitleStageProgress => _subtitleStageProgress;
  double get subtitleProgress => _subtitleStageProgress
      .progressForStep(_subtitleStageProgress.currentStep);
  String get subtitleStatusText => _subtitleStageProgress.status;
  int get subtitleShiftMs => _subtitleShiftMs;

  OfflineAsrModelType get selectedOfflineModel => _selectedOfflineModel;
  ModelStatusMap get modelDownloadStatuses =>
      Map.unmodifiable(_modelDownloadStatuses);
  OfflineAsrModelType? get downloadingModel => _downloadingModel;
  double get downloadProgress => _downloadProgress;

  bool get isSelectedOfflineModelReady =>
      _modelDownloadStatuses[_selectedOfflineModel] ?? false;

  bool get hasAnyOfflineModelDownloaded =>
      _modelDownloadStatuses.values.any((downloaded) => downloaded);

  /// 结合偏移补偿计算当前播放位置匹配的字幕索引
  int get activeSubtitleIndex {
    final item = currentItem;
    if (item == null || item.subtitles.isEmpty) return -1;

    final effectiveMs = _position.inMilliseconds + _subtitleShiftMs;

    for (int i = 0; i < item.subtitles.length; i++) {
      final cue = item.subtitles[i];
      if (effectiveMs >= cue.startMs && effectiveMs <= cue.endMs) {
        return i;
      }
    }

    for (int i = item.subtitles.length - 1; i >= 0; i--) {
      if (effectiveMs >= item.subtitles[i].startMs) {
        return i;
      }
    }
    return 0;
  }

  Future<void> init() async {
    _playlist = await _storage.loadPlaylist();
    _seekSeconds = await _storage.loadSeekSeconds();
    _speed = await _storage.loadSpeed();
    _deepSeekConfig = await _storage.loadDeepSeekConfig();
    _subtitleMode = await _storage.loadSubtitleMode();
    _subtitleShiftMs = await _storage.loadSubtitleShiftMs();

    final savedModelName = await _storage.loadSelectedOfflineModelName();
    _selectedOfflineModel = OfflineAsrModelType.fromName(savedModelName);
    await refreshOfflineModelStatuses();

    final lastTrackId = await _storage.loadLastTrackId();
    await _player.setSpeed(_speed);

    _posSub = _player.positionStream.listen((pos) {
      _position = pos;
      notifyListeners();
    });

    _durSub = _player.durationStream.listen((dur) {
      _duration = dur ?? Duration.zero;
      notifyListeners();
    });

    _stateSub = _player.playerStateStream.listen((state) {
      _isPlaying = state.playing;
      if (state.processingState == ProcessingState.completed) {
        _handleTrackCompleted();
      }
      notifyListeners();
    });

    if (_playlist.isNotEmpty) {
      final restoredIdx = lastTrackId != null
          ? _playlist.indexWhere((e) => e.id == lastTrackId)
          : 0;
      await playTrackAt(restoredIdx >= 0 ? restoredIdx : 0, autoPlay: false);
    }
    notifyListeners();
  }

  Future<void> _handleTrackCompleted() async {
    switch (_loopMode) {
      case PlayLoopMode.singleLoop:
        await _player.seek(Duration.zero);
        await _player.play();
        break;
      case PlayLoopMode.listLoop:
        if (_playlist.isNotEmpty) {
          final nextIdx = (_currentIndex + 1) % _playlist.length;
          await playTrackAt(nextIdx, autoPlay: true);
        }
        break;
      case PlayLoopMode.sequence:
        if (_currentIndex + 1 < _playlist.length) {
          await playTrackAt(_currentIndex + 1, autoPlay: true);
        } else {
          await _player.pause();
          await _player.seek(Duration.zero);
        }
        break;
    }
  }

  Future<int> importAudioFiles() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.audio,
      allowMultiple: true,
    );
    if (result == null || result.files.isEmpty) return 0;

    final wasEmpty = _playlist.isEmpty;
    int addedCount = 0;

    for (final file in result.files) {
      final path = file.path;
      if (path == null) continue;

      final exists = _playlist.any((item) => item.filePath == path);
      if (exists) continue;

      final title = file.name.replaceFirst(RegExp(r'\.[^.]+$'), '');
      _playlist.add(
        AudioItem(
          id: '${DateTime.now().microsecondsSinceEpoch}_$addedCount',
          title: title,
          filePath: path,
        ),
      );
      addedCount++;
    }

    if (addedCount > 0) {
      await _storage.savePlaylist(_playlist);
      if (wasEmpty) {
        await playTrackAt(0, autoPlay: false);
      }
      notifyListeners();
    }
    return addedCount;
  }

  Future<void> playTrackAt(int index, {bool autoPlay = true}) async {
    if (index < 0 || index >= _playlist.length) return;
    final item = _playlist[index];

    if (!File(item.filePath).existsSync()) {
      return;
    }

    _currentIndex = index;
    _position = Duration.zero;
    notifyListeners();

    await _storage.saveLastTrackId(item.id);
    await _player.setAudioSource(
      AudioSource.file(
        item.filePath,
        tag: MediaItem(
          id: item.id,
          album: '听力助手 · ListenMate',
          title: item.title,
          artist: '英语精听',
        ),
      ),
    );
    await _player.setSpeed(_speed);

    if (autoPlay) {
      await _player.play();
    }
  }

  Future<void> removeTrackAt(int index) async {
    if (index < 0 || index >= _playlist.length) return;

    final isRemovingCurrent = index == _currentIndex;
    _playlist.removeAt(index);
    await _storage.savePlaylist(_playlist);

    if (_playlist.isEmpty) {
      await _player.stop();
      _currentIndex = -1;
      _position = Duration.zero;
      _duration = Duration.zero;
      await _storage.saveLastTrackId(null);
    } else if (isRemovingCurrent) {
      final nextIdx = index.clamp(0, _playlist.length - 1);
      await playTrackAt(nextIdx, autoPlay: false);
    } else if (index < _currentIndex) {
      _currentIndex--;
    }

    notifyListeners();
  }

  Future<void> togglePlayPause() async {
    if (currentItem == null) return;
    if (_isPlaying) {
      await _player.pause();
    } else {
      await _player.play();
    }
  }

  Future<void> seekTo(Duration target) async {
    if (currentItem == null) return;
    final clampedMs = target.inMilliseconds.clamp(0, _duration.inMilliseconds);
    await _player.seek(Duration(milliseconds: clampedMs));
  }

  Future<void> seekBackward() async {
    await seekTo(_position - Duration(seconds: _seekSeconds));
  }

  Future<void> seekForward() async {
    await seekTo(_position + Duration(seconds: _seekSeconds));
  }

  Future<void> playPrevious() async {
    if (_playlist.isEmpty) return;
    final prevIdx = (_currentIndex - 1 + _playlist.length) % _playlist.length;
    await playTrackAt(prevIdx, autoPlay: true);
  }

  Future<void> playNext() async {
    if (_playlist.isEmpty) return;
    final nextIdx = (_currentIndex + 1) % _playlist.length;
    await playTrackAt(nextIdx, autoPlay: true);
  }

  Future<void> setSpeed(double newSpeed) async {
    final clamped = double.parse(newSpeed.clamp(0.5, 2.5).toStringAsFixed(2));
    _speed = clamped;
    await _player.setSpeed(_speed);
    await _storage.saveSpeed(_speed);
    notifyListeners();
  }

  Future<void> setSeekSeconds(int seconds) async {
    final clamped = seconds.clamp(1, 60);
    _seekSeconds = clamped;
    await _storage.saveSeekSeconds(_seekSeconds);
    notifyListeners();
  }

  void cycleLoopMode() {
    final nextOrdinal = (_loopMode.index + 1) % PlayLoopMode.values.length;
    _loopMode = PlayLoopMode.values[nextOrdinal];
    notifyListeners();
  }

  // ==================== 离线模型按需下载与管理 ====================

  Future<void> refreshOfflineModelStatuses() async {
    _modelDownloadStatuses = await _modelManager.getAllModelStatuses();
    if (!(_modelDownloadStatuses[_selectedOfflineModel] ?? false)) {
      for (final entry in _modelDownloadStatuses.entries) {
        if (entry.value) {
          _selectedOfflineModel = entry.key;
          await _storage.saveSelectedOfflineModelName(entry.key.name);
          break;
        }
      }
    }
    notifyListeners();
  }

  Future<void> selectOfflineModel(OfflineAsrModelType type) async {
    _selectedOfflineModel = type;
    await _storage.saveSelectedOfflineModelName(type.name);
    notifyListeners();
  }

  Future<String?> downloadOfflineModel(
    OfflineAsrModelType type, {
    bool useChinaMirror = true,
  }) async {
    if (_downloadingModel != null) return '已有模型正在下载中';

    _downloadingModel = type;
    _downloadProgress = 0.0;
    notifyListeners();

    try {
      await _modelManager.downloadModel(
        type: type,
        useChinaMirror: useChinaMirror,
        onProgress: (progress) {
          _downloadProgress = progress;
          notifyListeners();
        },
      );
      await refreshOfflineModelStatuses();
      await selectOfflineModel(type);
      return null;
    } catch (e) {
      return e.toString().replaceFirst('Exception: ', '');
    } finally {
      _downloadingModel = null;
      _downloadProgress = 0.0;
      notifyListeners();
    }
  }

  void cancelModelDownload() {
    _modelManager.cancelDownload();
    _downloadingModel = null;
    _downloadProgress = 0.0;
    notifyListeners();
  }

  Future<void> deleteOfflineModel(OfflineAsrModelType type) async {
    await _modelManager.deleteModel(type);
    await refreshOfflineModelStatuses();
  }

  // ==================== 双语字幕功能 ====================

  Future<void> updateDeepSeekConfig(DeepSeekApiConfig newConfig) async {
    _deepSeekConfig = newConfig;
    await _storage.saveDeepSeekConfig(newConfig);
    notifyListeners();
  }

  Future<void> setSubtitleMode(SubtitleDisplayMode mode) async {
    _subtitleMode = mode;
    await _storage.saveSubtitleMode(mode);
    notifyListeners();
  }

  Future<void> adjustSubtitleShift(int deltaMs) async {
    _subtitleShiftMs = (_subtitleShiftMs + deltaMs).clamp(-5000, 5000);
    await _storage.saveSubtitleShiftMs(_subtitleShiftMs);
    notifyListeners();
  }

  Future<void> resetSubtitleShift() async {
    _subtitleShiftMs = 300;
    await _storage.saveSubtitleShiftMs(_subtitleShiftMs);
    notifyListeners();
  }

  Future<String?> generateSubtitlesForCurrent() async {
    final item = currentItem;
    final targetIndex = _currentIndex;
    if (item == null || _isGeneratingSubtitles) return null;

    if (!isSelectedOfflineModelReady) {
      return '请先在底部“设置”页下载离线语音识别模型';
    }

    _isGeneratingSubtitles = true;
    _subtitleStageProgress = SubtitleStageProgress.initial;
    notifyListeners();

    try {
      final cues = await _subtitleService.generateBilingualSubtitles(
        filePath: item.filePath,
        offlineModel: _selectedOfflineModel,
        deepSeekConfig: _deepSeekConfig,
        audioDuration: _duration,
        onProgress: (stageProgress) {
          _subtitleStageProgress = stageProgress;
          notifyListeners();
        },
      );

      if (targetIndex >= 0 && targetIndex < _playlist.length) {
        _playlist[targetIndex] =
            _playlist[targetIndex].copyWith(subtitles: cues);
        await _storage.savePlaylist(_playlist);
      }

      if (_subtitleMode == SubtitleDisplayMode.hidden) {
        await setSubtitleMode(SubtitleDisplayMode.bilingual);
      }
      return null;
    } catch (e) {
      return e.toString().replaceFirst('Exception: ', '');
    } finally {
      _isGeneratingSubtitles = false;
      _subtitleStageProgress = SubtitleStageProgress.initial;
      notifyListeners();
    }
  }

  /// 点击字幕跳转时扣除时间轴偏移，精准定位到人声开口处
  Future<void> replayFromSubtitle(SubtitleCue cue) async {
    if (currentItem == null) return;
    final targetMs = (cue.startMs - _subtitleShiftMs).clamp(
      0,
      _duration.inMilliseconds > 0 ? _duration.inMilliseconds : cue.startMs,
    );
    await seekTo(Duration(milliseconds: targetMs));
    if (!_isPlaying) {
      await _player.play();
    }
  }

  Future<void> bookmarkSubtitleCue(SubtitleCue cue) async {
    final item = currentItem;
    if (item == null) return;

    final preview = cue.english.length > 28
        ? '${cue.english.substring(0, 28)}...'
        : cue.english;

    final targetMs = (cue.startMs - _subtitleShiftMs).clamp(0, cue.startMs);

    final newMarker = AudioMarker(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      positionMs: targetMs,
      label: preview,
    );

    final updatedMarkers = [...item.markers, newMarker]
      ..sort((a, b) => a.positionMs.compareTo(b.positionMs));

    _playlist[_currentIndex] = item.copyWith(markers: updatedMarkers);
    await _storage.savePlaylist(_playlist);
    notifyListeners();
  }

  // ==================== 节点标注功能 ====================

  Future<void> addMarkerAtCurrentPosition({String? customLabel}) async {
    final item = currentItem;
    if (item == null) return;

    final markerIndex = item.markers.length + 1;
    final label = (customLabel != null && customLabel.trim().isNotEmpty)
        ? customLabel.trim()
        : '节点 #$markerIndex';

    final newMarker = AudioMarker(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      positionMs: _position.inMilliseconds,
      label: label,
    );

    final updatedMarkers = [...item.markers, newMarker]
      ..sort((a, b) => a.positionMs.compareTo(b.positionMs));

    _playlist[_currentIndex] = item.copyWith(markers: updatedMarkers);
    await _storage.savePlaylist(_playlist);
    notifyListeners();
  }

  Future<void> replayFromMarker(AudioMarker marker) async {
    if (currentItem == null) return;
    await seekTo(Duration(milliseconds: marker.positionMs));
    if (!_isPlaying) {
      await _player.play();
    }
  }

  Future<void> renameMarker(String markerId, String newLabel) async {
    final item = currentItem;
    if (item == null || newLabel.trim().isEmpty) return;

    final updatedMarkers = item.markers.map((m) {
      return m.id == markerId ? m.copyWith(label: newLabel.trim()) : m;
    }).toList();

    _playlist[_currentIndex] = item.copyWith(markers: updatedMarkers);
    await _storage.savePlaylist(_playlist);
    notifyListeners();
  }

  Future<void> deleteMarker(String markerId) async {
    final item = currentItem;
    if (item == null) return;

    final updatedMarkers =
        item.markers.where((m) => m.id != markerId).toList();

    _playlist[_currentIndex] = item.copyWith(markers: updatedMarkers);
    await _storage.savePlaylist(_playlist);
    notifyListeners();
  }

  @override
  void dispose() {
    _modelManager.cancelDownload();
    _posSub.cancel();
    _durSub.cancel();
    _stateSub.cancel();
    _player.dispose();
    super.dispose();
  }
}