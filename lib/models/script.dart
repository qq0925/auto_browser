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
  replaced,
  callSubroutine,
  notification,
  jump,
}

class Script {
  String type; // '点击文字', '输入框提交', '自定义JS', '全局变量'
  Map<String, dynamic> params;
  bool isEnabled;

  // 运行时状态
  ScriptStatus status = ScriptStatus.idle;
  String? statusMessage;
  double? progress;
  String? targetScriptPath; // 用于 '脚本替换' 和 '执行本地脚本集'

  Script({
    required this.type,
    required this.params,
    this.isEnabled = true,
    this.status = ScriptStatus.idle,
    this.statusMessage,
    this.progress,
    String? targetScriptPath,
  }) : targetScriptPath = targetScriptPath ??
            ((type == '脚本替换' || type == '执行本地脚本集') &&
                    params['脚本集'] != null
                ? params['脚本集']?.toString()
                : null);

  Map<String, dynamic> getClickParams() {
    return params;
  }

  factory Script.fromMap(Map<String, dynamic> map) {
    final parsedParams = map['params'] is Map
        ? Map<String, dynamic>.from(map['params'] as Map)
        : <String, dynamic>{};
    return Script(
      type: map['type']?.toString() ?? '未知类型',
      params: parsedParams,
      isEnabled: map['isEnabled'] as bool? ?? true,
      targetScriptPath: map['targetScriptPath']?.toString() ??
          parsedParams['脚本集']?.toString(),
    );
  }

  // 从用户导出的扁平 JSON 结构转换
  factory Script.fromUserMap(Map<String, dynamic> map) {
    final type = map['脚本类型']?.toString() ?? '未知类型';
    final params = Map<String, dynamic>.from(map);
    params.remove('脚本类型');

    String? targetScriptPath;
    if ((type == '脚本替换' || type == '执行本地脚本集') && params.containsKey('脚本集')) {
      targetScriptPath = params['脚本集']?.toString();
      params.remove('脚本集');
    }

    return Script(
      type: type,
      params: params,
      isEnabled: true,
      targetScriptPath: targetScriptPath,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'type': type,
      'params': params,
      'isEnabled': isEnabled,
      'targetScriptPath': targetScriptPath,
    };
  }

  // 转换为用户扁平 JSON 结构
  Map<String, dynamic> toUserMap() {
    final map = Map<String, dynamic>.from(params);
    map['脚本类型'] = type;
    if (targetScriptPath != null) {
      map['脚本集'] = targetScriptPath;
    }
    return map;
  }

  String toJson() => json.encode(toMap());

  factory Script.fromJson(String source) => Script.fromMap(json.decode(source));
}
