import 'dart:convert';

// 添加脚本模式枚举
enum ScriptMode {
  simple('简单'),
  normal('普通'),
  expert('专家');

  final String label;
  const ScriptMode(this.label);
}

// 添加时间单位枚举
enum TimeUnit {
  milliseconds('毫秒', 1),
  seconds('秒', 1000),
  minutes('分钟', 60000);

  final String label;
  final int multiplier;
  const TimeUnit(this.label, this.multiplier);
}

// 修改 Script 类，添加模式属性
class Script {
  final String type;
  final Map<String, dynamic> params;
  bool isEnabled;
  ScriptMode mode;  // 添加模式属性

  Script({
    required this.type,
    required this.params,
    this.isEnabled = true,
    this.mode = ScriptMode.simple,  // 默认简单模式
  });

  // 修改 fromJson 和 toJson 方法以包含模式
  factory Script.fromJson(String json) {
    final data = jsonDecode(json);
    return Script(
      type: data['脚本类型'],
      params: Map<String, dynamic>.from(data['参数']),
      isEnabled: data['启用'] ?? true,
      mode: ScriptMode.values.firstWhere(
        (m) => m.label == (data['模式'] ?? '简单'),
        orElse: () => ScriptMode.simple,
      ),
    );
  }

  String toJson() {
    return jsonEncode({
      '脚本类型': type,
      '参数': params,
      '启用': isEnabled,
      '模式': mode.label,
    });
  }

  Map<String, dynamic> getClickParams() {
    if (type != "点击文字") return {};
    
    switch (mode) {
      case ScriptMode.simple:
        return {
          '点击文字': params['点击文字'] ?? '',
        };
      case ScriptMode.normal:
        return {
          '执行延迟': params['执行延迟'] ?? 0,
          '时间单位': params['时间单位'] ?? '毫秒',
          '出现文字': params['出现文字'] ?? '',
          '点击文字': params['点击文字'] ?? '',
          '完全匹配': params['完全匹配'] ?? false,
        };
      case ScriptMode.expert:
        return {
          '执行延迟': params['执行延迟'] ?? 0,
          '时间单位': params['时间单位'] ?? '毫秒',
          '出现文字': params['出现文字'] ?? '',
          '在此之后': params['在此之后'] ?? '',
          '在此之前': params['在此之前'] ?? '',
          '点击文字': params['点击文字'] ?? '',
          '完全匹配': params['完全匹配'] ?? false,
          '多个筛选': params['多个筛选'] ?? 1,
        };
    }
  }
}
