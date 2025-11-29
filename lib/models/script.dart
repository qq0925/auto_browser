import 'dart:convert';

enum TimeUnit {
  milliseconds,
  seconds,
  minutes;

  String get label {
    switch (this) {
      case TimeUnit.milliseconds:
        return '毫秒';
      case TimeUnit.seconds:
        return '秒';
      case TimeUnit.minutes:
        return '分钟';
    }
  }

  int get multiplier {
    switch (this) {
      case TimeUnit.milliseconds:
        return 1;
      case TimeUnit.seconds:
        return 1000;
      case TimeUnit.minutes:
        return 60000;
    }
  }
}

enum ScriptStatus {
  idle,
  running,
  success,
  failure,
  waiting,
  stopped,
  paused,
}

class Script {
  String type; // '点击文字', '输入框提交', '自定义JS', '全局变量'
  Map<String, dynamic> params;
  bool isEnabled;

  // Runtime state
  ScriptStatus status = ScriptStatus.idle;
  String? statusMessage;
  double? progress;

  Script({
    required this.type,
    required this.params,
    this.isEnabled = true,
    this.status = ScriptStatus.idle,
    this.statusMessage,
    this.progress,
  });

  Map<String, dynamic> getClickParams() {
    return params;
  }

  factory Script.fromMap(Map<String, dynamic> map) {
    return Script(
      type: map['type'],
      params: Map<String, dynamic>.from(map['params']),
      isEnabled: map['isEnabled'] ?? true,
    );
  }

  // Convert from User JSON (flat structure)
  factory Script.fromUserMap(Map<String, dynamic> map) {
    final type = map['脚本类型'] as String? ?? '未知类型';
    final params = Map<String, dynamic>.from(map);
    params.remove('脚本类型'); // Remove type from params
    return Script(
      type: type,
      params: params,
      isEnabled: true,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'type': type,
      'params': params,
      'isEnabled': isEnabled,
      // status and statusMessage are runtime only, not persisted
    };
  }

  // Convert to User JSON (flat structure)
  Map<String, dynamic> toUserMap() {
    final map = Map<String, dynamic>.from(params);
    map['脚本类型'] = type;
    return map;
  }

  String toJson() => json.encode(toMap());

  factory Script.fromJson(String source) => Script.fromMap(json.decode(source));
}
