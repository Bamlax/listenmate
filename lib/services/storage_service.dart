import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/audio_item.dart';

class DeepSeekApiConfig {
  final String baseUrl;
  final String apiKey;
  final String model;

  const DeepSeekApiConfig({
    this.baseUrl = 'https://api.deepseek.com',
    this.apiKey = '',
    this.model = 'deepseek-flash',
  });

  bool get isConfigured =>
      baseUrl.trim().isNotEmpty && apiKey.trim().isNotEmpty;
}

class StorageService {
  static const _keyPlaylist = 'cet_playlist_v1';
  static const _keySeekSeconds = 'cet_seek_seconds_v1';
  static const _keySpeed = 'cet_playback_speed_v1';
  static const _keyLastTrackId = 'cet_last_track_id_v1';

  static const _keyLlmBaseUrl = 'cet_llm_base_url_v2';
  static const _keyLlmApiKey = 'cet_llm_api_key_v2';
  static const _keyLlmModel = 'cet_llm_model_v2';
  static const _keyOfflineModelName = 'cet_offline_asr_model_v1';
  static const _keySubtitleMode = 'cet_subtitle_mode_v1';
  static const _keySubtitleShiftMs = 'cet_subtitle_shift_ms_v1';

  Future<List<AudioItem>> loadPlaylist() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_keyPlaylist);
    if (raw == null || raw.isEmpty) return [];

    final List<dynamic> decoded = jsonDecode(raw) as List<dynamic>;
    return decoded
        .map((e) => AudioItem.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<void> savePlaylist(List<AudioItem> playlist) async {
    final prefs = await SharedPreferences.getInstance();
    final encoded = jsonEncode(playlist.map((e) => e.toJson()).toList());
    await prefs.setString(_keyPlaylist, encoded);
  }

  Future<int> loadSeekSeconds() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_keySeekSeconds) ?? 5;
  }

  Future<void> saveSeekSeconds(int seconds) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_keySeekSeconds, seconds);
  }

  Future<double> loadSpeed() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getDouble(_keySpeed) ?? 1.0;
  }

  Future<void> saveSpeed(double speed) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_keySpeed, speed);
  }

  Future<String?> loadLastTrackId() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_keyLastTrackId);
  }

  Future<void> saveLastTrackId(String? id) async {
    final prefs = await SharedPreferences.getInstance();
    if (id == null) {
      await prefs.remove(_keyLastTrackId);
    } else {
      await prefs.setString(_keyLastTrackId, id);
    }
  }

  Future<DeepSeekApiConfig> loadDeepSeekConfig() async {
    final prefs = await SharedPreferences.getInstance();
    return DeepSeekApiConfig(
      baseUrl: prefs.getString(_keyLlmBaseUrl) ?? 'https://api.deepseek.com',
      apiKey: prefs.getString(_keyLlmApiKey) ?? '',
      model: prefs.getString(_keyLlmModel) ?? 'deepseek-flash',
    );
  }

  Future<void> saveDeepSeekConfig(DeepSeekApiConfig config) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyLlmBaseUrl, config.baseUrl.trim());
    await prefs.setString(_keyLlmApiKey, config.apiKey.trim());
    await prefs.setString(_keyLlmModel, config.model.trim());
  }

  Future<String> loadSelectedOfflineModelName() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_keyOfflineModelName) ?? 'baseEn';
  }

  Future<void> saveSelectedOfflineModelName(String name) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyOfflineModelName, name);
  }

  Future<SubtitleDisplayMode> loadSubtitleMode() async {
    final prefs = await SharedPreferences.getInstance();
    final idx = prefs.getInt(_keySubtitleMode) ?? 0;
    if (idx < 0 || idx >= SubtitleDisplayMode.values.length) {
      return SubtitleDisplayMode.bilingual;
    }
    return SubtitleDisplayMode.values[idx];
  }

  Future<void> saveSubtitleMode(SubtitleDisplayMode mode) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_keySubtitleMode, mode.index);
  }

  /// 默认提前 300ms（+300），补偿 Whisper 语音起始点识别延迟
  Future<int> loadSubtitleShiftMs() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_keySubtitleShiftMs) ?? 300;
  }

  Future<void> saveSubtitleShiftMs(int shiftMs) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_keySubtitleShiftMs, shiftMs);
  }
}