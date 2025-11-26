import 'dart:convert';

enum ScriptMode {
  simple, // 简单模式：只记录点击和输入
  normal, // 普通模式：记录更多交互
  expert, // 专家模式：允许自定义JS
}

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

class Script {
  String type; // '点击文字', '输入框提交', '自定义JS', '全局变量'
  Map<String, dynamic> params;
  bool isEnabled;

  Script({
    required this.type,
    required this.params,
    this.isEnabled = true,
  });

  Map<String, dynamic> getClickParams() {
    return params;
  }

  ScriptMode get mode {
    if (params.containsKey('mode')) {
      final modeStr = params['mode'];
      if (modeStr == 'expert') return ScriptMode.expert;
      if (modeStr == 'normal') return ScriptMode.normal;
    }
    // Fallback based on params presence
    if (params.containsKey('出现文字') || params.containsKey('在此之后')) {
      return ScriptMode.expert;
    }
    if (params.containsKey('出现文字')) {
      return ScriptMode.normal;
    }
    return ScriptMode.simple;
  }

  Map<String, dynamic> toMap() {
    return {
      'type': type,
      'params': params,
      'isEnabled': isEnabled,
    };
  }

  factory Script.fromMap(Map<String, dynamic> map) {
    return Script(
      type: map['type'],
      params: Map<String, dynamic>.from(map['params']),
      isEnabled: map['isEnabled'] ?? true,
    );
  }

  String toJson() => json.encode(toMap());

  factory Script.fromJson(String source) => Script.fromMap(json.decode(source));
}
