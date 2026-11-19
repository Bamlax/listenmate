enum SubtitleDisplayMode {
  bilingual,   // 中英双语
  englishOnly, // 仅显示英文
  hidden,      // 隐藏字幕
}

class SubtitleCue {
  final String id;
  final int startMs;
  final int endMs;
  final String english;
  final String chinese;

  const SubtitleCue({
    required this.id,
    required this.startMs,
    required this.endMs,
    required this.english,
    required this.chinese,
  });

  SubtitleCue copyWith({
    String? id,
    int? startMs,
    int? endMs,
    String? english,
    String? chinese,
  }) {
    return SubtitleCue(
      id: id ?? this.id,
      startMs: startMs ?? this.startMs,
      endMs: endMs ?? this.endMs,
      english: english ?? this.english,
      chinese: chinese ?? this.chinese,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'startMs': startMs,
        'endMs': endMs,
        'english': english,
        'chinese': chinese,
      };

  factory SubtitleCue.fromJson(Map<String, dynamic> json) {
    return SubtitleCue(
      id: json['id'] as String,
      startMs: json['startMs'] as int,
      endMs: json['endMs'] as int,
      english: json['english'] as String,
      chinese: json['chinese'] as String? ?? '',
    );
  }
}

class AudioMarker {
  final String id;
  final int positionMs;
  final String label;

  const AudioMarker({
    required this.id,
    required this.positionMs,
    required this.label,
  });

  AudioMarker copyWith({
    String? id,
    int? positionMs,
    String? label,
  }) {
    return AudioMarker(
      id: id ?? this.id,
      positionMs: positionMs ?? this.positionMs,
      label: label ?? this.label,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'positionMs': positionMs,
        'label': label,
      };

  factory AudioMarker.fromJson(Map<String, dynamic> json) {
    return AudioMarker(
      id: json['id'] as String,
      positionMs: json['positionMs'] as int,
      label: json['label'] as String,
    );
  }
}

class AudioItem {
  final String id;
  final String title;
  final String filePath;
  final List<AudioMarker> markers;
  final List<SubtitleCue> subtitles;

  const AudioItem({
    required this.id,
    required this.title,
    required this.filePath,
    this.markers = const [],
    this.subtitles = const [],
  });

  AudioItem copyWith({
    String? id,
    String? title,
    String? filePath,
    List<AudioMarker>? markers,
    List<SubtitleCue>? subtitles,
  }) {
    return AudioItem(
      id: id ?? this.id,
      title: title ?? this.title,
      filePath: filePath ?? this.filePath,
      markers: markers ?? this.markers,
      subtitles: subtitles ?? this.subtitles,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'filePath': filePath,
        'markers': markers.map((m) => m.toJson()).toList(),
        'subtitles': subtitles.map((s) => s.toJson()).toList(),
      };

  factory AudioItem.fromJson(Map<String, dynamic> json) {
    final rawMarkers = json['markers'] as List<dynamic>? ?? [];
    final rawSubtitles = json['subtitles'] as List<dynamic>? ?? [];
    return AudioItem(
      id: json['id'] as String,
      title: json['title'] as String,
      filePath: json['filePath'] as String,
      markers: rawMarkers
          .map((e) => AudioMarker.fromJson(e as Map<String, dynamic>))
          .toList(),
      subtitles: rawSubtitles
          .map((e) => SubtitleCue.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }
}

String formatDuration(Duration duration) {
  final totalSeconds = duration.inSeconds;
  final hours = totalSeconds ~/ 3600;
  final minutes = (totalSeconds % 3600) ~/ 60;
  final seconds = totalSeconds % 60;

  final mm = minutes.toString().padLeft(2, '0');
  final ss = seconds.toString().padLeft(2, '0');
  if (hours > 0) {
    final hh = hours.toString().padLeft(2, '0');
    return '$hh:$mm:$ss';
  }
  return '$mm:$ss';
}