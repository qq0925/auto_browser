import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import '../models/script.dart';
import '../services/script_executor.dart';
import 'dart:convert';
import 'dart:async';
import 'dart:io';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import '../models/browser_tab.dart';

class ScriptProvider extends ChangeNotifier {
  BrowserTab? _currentTab;
  final ScriptExecutor _executor = ScriptExecutor();
  final FlutterLocalNotificationsPlugin _flutterLocalNotificationsPlugin =
      FlutterLocalNotificationsPlugin();

  ScriptProvider() {
    _init();
    _loadScripts();
  }

  Future<void> _init() async {
    if (Platform.isWindows) {
      // Windows 平台使用本地日志，跳过移动端通知插件初始化
      return;
    }

    try {
      // 初始化本地通知插件
      const AndroidInitializationSettings initializationSettingsAndroid =
          AndroidInitializationSettings('@mipmap/ic_launcher');
      final DarwinInitializationSettings initializationSettingsDarwin =
          DarwinInitializationSettings();
      final LinuxInitializationSettings initializationSettingsLinux =
          LinuxInitializationSettings(defaultActionName: 'Open notification');
      final InitializationSettings initializationSettings =
          InitializationSettings(
        android: initializationSettingsAndroid,
        iOS: initializationSettingsDarwin,
        macOS: initializationSettingsDarwin,
        linux: initializationSettingsLinux,
      );
      await _flutterLocalNotificationsPlugin.initialize(initializationSettings);

      // 请求 Android 13+ 通知权限
      final androidPlatform = _flutterLocalNotificationsPlugin
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>();
      await androidPlatform?.requestNotificationsPermission();

      // 请求 iOS 通知权限
      final iosPlatform = _flutterLocalNotificationsPlugin
          .resolvePlatformSpecificImplementation<
              IOSFlutterLocalNotificationsPlugin>();
      await iosPlatform?.requestPermissions(
        alert: true,
        badge: true,
        sound: true,
      );
    } catch (e) {
      debugPrint('初始化通知插件失败: $e');
    }
  }

  bool _isRecording = false;
  // 按标签页独立维护执行与暂停状态，以下字段作为当前标签页的默认值或回退
  bool _isPaused = false;
  int _currentScriptIndex = 0;
  int _executionDelay = 1000;
  int _originalLoopCount = 1;
  int _remainingLoopCount = 1;
  TimeUnit _delayTimeUnit = TimeUnit.milliseconds;

  int _successCount = 0;
  int _failureCount = 0;

  Future<void> Function(
          {String? preNavToken, String? preUrl, BrowserTab? targetTab})?
      _waitForPageLoadCallback;

  // 获取当前标签页的脚本列表与执行状态（优先读取当前标签页自身状态）
  List<Script> get scripts => _currentTab?.scripts ?? [];
  BrowserTab? get currentTab => _currentTab;
  bool get isRecording => _isRecording;

  bool get isExecuting => _currentTab?.isExecutingScript ?? false;
  bool get isPaused => _currentTab?.isPaused ?? _isPaused;
  int get currentScriptIndex =>
      _currentTab?.currentScriptIndex ?? _currentScriptIndex;
  int get executionDelay =>
      (_currentTab != null && _currentTab!.hasCustomExecutionConfig)
          ? _currentTab!.executionDelay
          : _executionDelay;
  int get originalLoopCount =>
      (_currentTab != null && _currentTab!.hasCustomExecutionConfig)
          ? _currentTab!.originalLoopCount
          : _originalLoopCount;
  int get remainingLoopCount =>
      _currentTab?.remainingLoopCount ?? _remainingLoopCount;
  TimeUnit get delayTimeUnit =>
      (_currentTab != null && _currentTab!.hasCustomExecutionConfig)
          ? TimeUnit.values.firstWhere(
              (u) => u.label == _currentTab!.delayTimeUnit,
              orElse: () => _delayTimeUnit,
            )
          : _delayTimeUnit;
  int get successCount => _currentTab?.successCount ?? _successCount;
  int get failureCount => _currentTab?.failureCount ?? _failureCount;
  String? get currentScriptFilePath => _currentTab?.scriptFilePath;

  // 跨步骤动态变量字典
  final Map<String, String> _variables = {};
  Map<String, String> get variables => Map.unmodifiable(
        _currentTab != null && _currentTab!.variables.isNotEmpty
            ? _currentTab!.variables
            : _variables,
      );

  void setVariable(String key, String value) {
    _variables[key] = value;
    if (_currentTab != null) {
      _currentTab!.variables[key] = value;
    }
    notifyListeners();
  }

  void clearVariables() {
    _variables.clear();
    _currentTab?.variables.clear();
    notifyListeners();
  }

  void setWaitForPageLoadCallback(
      Future<void> Function(
              {String? preNavToken, String? preUrl, BrowserTab? targetTab})
          callback) {
    _waitForPageLoadCallback = callback;
  }

  void setCurrentTab(BrowserTab? tab) {
    if (_isRecording && _currentTab != tab) {
      if (_currentTab?.controller != null) {
        try {
          _currentTab!.controller!
              .removeUserScript(userScript: recordingUserScript);
        } catch (_) {}
      }
      if (tab?.controller != null) {
        try {
          tab!.controller!.evaluateJavascript(source: recordingJs);
          tab.controller!.addUserScript(userScript: recordingUserScript);
        } catch (_) {}
      }
    }
    _currentTab = tab;
    notifyListeners();
  }

  Future<void> _loadScripts() async {
    try {
      final prefs = await SharedPreferences.getInstance();

      // 加载全局默认执行设置（脚本列表按标签页隔离存储）
      _executionDelay = prefs.getInt('script_global_delay') ?? 1000;
      _originalLoopCount = prefs.getInt('script_global_loop') ?? 1;
      final unitIndex = prefs.getInt('script_global_unit') ?? 0;
      if (unitIndex >= 0 && unitIndex < TimeUnit.values.length) {
        _delayTimeUnit = TimeUnit.values[unitIndex];
      }
      notifyListeners();
    } catch (e) {
      debugPrint('Error loading global settings: $e');
    }
  }

  Future<void> _saveScripts() async {
    try {
      final prefs = await SharedPreferences.getInstance();

      // 保存全局默认执行设置
      await prefs.setInt('script_global_delay', _executionDelay);
      await prefs.setInt('script_global_loop', _originalLoopCount);
      await prefs.setInt('script_global_unit', _delayTimeUnit.index);
    } catch (e) {
      debugPrint('Error saving global settings: $e');
    }
  }

  void setExecutionDelay(int delay) {
    _executionDelay = delay;
    if (_currentTab != null) {
      _currentTab!.executionDelay = _executionDelay;
      _currentTab!.delayTimeUnit = _delayTimeUnit.label;
    }
    _saveScripts();
    notifyListeners();
  }

  void setDelayTimeUnit(TimeUnit unit) {
    _delayTimeUnit = unit;
    if (_currentTab != null) {
      _currentTab!.delayTimeUnit = unit.label;
    }
    _saveScripts();
    notifyListeners();
  }

  void setLoopCount(int count) {
    _originalLoopCount = count;
    _remainingLoopCount = count;
    if (_currentTab != null) {
      _currentTab!.originalLoopCount = count;
      _currentTab!.remainingLoopCount = count;
    }
    _saveScripts();
    notifyListeners();
  }

  UserScript? _recordingUserScript;

  UserScript get recordingUserScript {
    _recordingUserScript ??= UserScript(
      source: recordingJs,
      injectionTime: UserScriptInjectionTime.AT_DOCUMENT_START,
    );
    return _recordingUserScript!;
  }

  void startRecording() {
    // 若当前标签页正在执行脚本，禁止开启录制
    if (_currentTab?.isExecutingScript ?? false) return;
    _isRecording = true;

    // 若当前标签页控制器可用，立即注入录制脚本并注册 UserScript
    if (_currentTab?.controller != null) {
      _currentTab!.controller!.evaluateJavascript(source: recordingJs);
      _currentTab!.controller!.addUserScript(userScript: recordingUserScript);
    }

    notifyListeners();
  }

  void stopRecording() {
    _isRecording = false;
    if (_currentTab?.controller != null) {
      _currentTab!.controller!
          .removeUserScript(userScript: recordingUserScript);
    }
    notifyListeners();
  }

  void clearScripts() {
    if (_currentTab != null) {
      _currentTab!.scripts.clear();
      _currentTab!.scriptFilePath = null;
      _currentTab!.hasCustomExecutionConfig = false;
      notifyListeners();
    }
  }

  void addScript(Script script) {
    if (_currentTab != null) {
      _currentTab!.scripts.add(script);
      _lastRecordTime = DateTime.now();
      notifyListeners();
    }
  }

  void removeScript(int index) {
    if (_currentTab != null &&
        index >= 0 &&
        index < _currentTab!.scripts.length) {
      _currentTab!.scripts.removeAt(index);
      notifyListeners();
    }
  }

  void toggleScriptEnabled(int index, bool value) {
    if (_currentTab != null &&
        index >= 0 &&
        index < _currentTab!.scripts.length) {
      _currentTab!.scripts[index].isEnabled = value;
      notifyListeners();
    }
  }

  // 在指定索引位置插入脚本
  void insertScript(int index, Script script) {
    if (_currentTab != null &&
        index >= 0 &&
        index <= _currentTab!.scripts.length) {
      _currentTab!.scripts.insert(index, script);
      _lastRecordTime = DateTime.now();
      notifyListeners();
    }
  }

  // 复制指定索引的脚本（深拷贝参数并保留子脚本路径）
  Script? duplicateScript(int index) {
    if (_currentTab != null &&
        index >= 0 &&
        index < _currentTab!.scripts.length) {
      final original = _currentTab!.scripts[index];
      return Script(
        type: original.type,
        params: Map<String, dynamic>.from(
          jsonDecode(jsonEncode(original.params)) as Map,
        ),
        isEnabled: original.isEnabled,
        targetScriptPath: original.targetScriptPath,
      );
    }
    return null;
  }

  // 更新当前标签页关联的脚本文件路径
  void updateScriptFilePath(String? filePath) {
    if (_currentTab != null) {
      _currentTab!.scriptFilePath = filePath;
      notifyListeners();
    }
  }

  DateTime? _lastRecordTime;
  DateTime? _ignoreRecordingUntil;

  /// 暂时忽略指定时间内的录制消息，防止侧边栏切换、弹窗或悬浮条被误录制
  void temporarilyIgnoreRecording(
      [Duration duration = const Duration(milliseconds: 600)]) {
    _ignoreRecordingUntil = DateTime.now().add(duration);
  }

  /// 如果最近几百毫秒内误录制了一条动作（例如点击悬浮条/侧边栏手柄被穿透捕获），立即撤销并忽略后续点击
  void cancelLastRecordingIfRecent(
      [Duration duration = const Duration(milliseconds: 500)]) {
    temporarilyIgnoreRecording(const Duration(milliseconds: 600));
    if (_currentTab != null &&
        _currentTab!.scripts.isNotEmpty &&
        _lastRecordTime != null) {
      if (DateTime.now().difference(_lastRecordTime!) < duration) {
        _currentTab!.scripts.removeLast();
        notifyListeners();
      }
    }
  }

  // 最新录制动作广播流，用于触发 UI 动画提示
  final _lastRecordedActionController = StreamController<String>.broadcast();
  Stream<String> get lastRecordedActionStream =>
      _lastRecordedActionController.stream;

  void recordAction(String actionType, [String? detail]) {
    if (!_isRecording) return;

    String actionDescription = '';

    switch (actionType) {
      case '网页后退':
        addScript(Script(type: '网页后退', params: {}, isEnabled: true));
        actionDescription = '网页后退';
        break;
      case '网页前进':
        addScript(Script(type: '网页前进', params: {}, isEnabled: true));
        actionDescription = '网页前进';
        break;
      case '刷新网页':
        addScript(Script(type: '刷新网页', params: {}, isEnabled: true));
        actionDescription = '刷新网页';
        break;
      case '进入网址':
        if (detail != null && detail.isNotEmpty) {
          addScript(
              Script(type: '进入网址', params: {'网址': detail}, isEnabled: true));
          actionDescription = '进入网址: $detail';
        }
        break;
      case '点击图片':
        addScript(Script(type: '点击图片', params: {}, isEnabled: true));
        actionDescription = '点击图片';
        break;
    }

    if (actionDescription.isNotEmpty) {
      _lastRecordedActionController.add(actionDescription);
    }
  }

  void handleScriptMessage(String message) {
    if (!_isRecording) return;
    if (_ignoreRecordingUntil != null &&
        DateTime.now().isBefore(_ignoreRecordingUntil!)) {
      debugPrint(
          '[ScriptRecorder] Discarded recording event during ignore window: $message');
      return;
    }

    final separatorIndex = message.indexOf('|');
    if (separatorIndex == -1) return;

    final type = message.substring(0, separatorIndex);
    final content = message.substring(separatorIndex + 1);

    switch (type) {
      case '点击文字':
        // 解析文字与位置筛选参数（支持结构化 JSON 与传统分隔符格式）
        String text = '';
        int selectionIndex = 1;
        int totalMatches = 1;

        if (content.startsWith('{')) {
          try {
            final data = json.decode(content) as Map<String, dynamic>;
            text = (data['text'] ?? '').toString();
            selectionIndex = (data['index'] as num?)?.toInt() ?? 1;
            totalMatches = (data['total'] as num?)?.toInt() ?? 1;
          } catch (_) {}
        }
        if (text.isEmpty) {
          final parts = content.split('|');
          text = parts[0];
          selectionIndex =
              parts.length > 1 ? (int.tryParse(parts[1]) ?? 1) : 1;
          totalMatches = parts.length > 2
              ? (int.tryParse(parts[2]) ?? 1)
              : selectionIndex;
        }

        final params = <String, dynamic>{
          '点击文本': text,
          '完全匹配': true, // 录制默认完全匹配
        };

        // 智能补全：当页面检测到多个完全匹配文字或指定非首项筛选（如 -1 倒数、0 随机）时，自动填充筛选
        if (totalMatches > 1 || selectionIndex != 1) {
          params['多个筛选'] = selectionIndex;
        }

        addScript(Script(
          type: '点击文字',
          params: params,
          isEnabled: true,
        ));

        final String hint;
        if (selectionIndex == 0) {
          hint = ' (随机)';
        } else if (selectionIndex < 0) {
          hint = ' (倒数第${-selectionIndex}个)';
        } else if (totalMatches > 1) {
          hint = ' (第$selectionIndex个/共$totalMatches个)';
        } else if (selectionIndex > 1) {
          hint = ' (第$selectionIndex个)';
        } else {
          hint = '';
        }
        _lastRecordedActionController.add('点击文字: $text$hint');
        break;

      case '点击提交按钮':
        try {
          final data = json.decode(content) as Map<String, dynamic>;
          final buttonText = data['按钮文本'] as String? ?? '提交';
          final formData = data['表单数据'];

          addScript(Script(
            type: '输入框提交',
            params: {
              '提交按钮文字': buttonText,
              '表单数据': formData ?? {},
            },
            isEnabled: true,
          ));
          _lastRecordedActionController.add('输入框提交: $buttonText');
        } catch (e) {
          debugPrint('Parse submit button data error: $e');
        }
        break;

      case '点击图片':
        addScript(Script(
          type: '点击图片',
          params: {
            '图片地址': content,
          },
          isEnabled: true,
        ));
        _lastRecordedActionController.add('点击图片: $content');
        break;

      case '点击选择器':
        final parts = content.split('|');
        final selector = parts[0];
        final description = parts.length > 1 && parts[1].isNotEmpty
            ? parts[1]
            : selector;

        addScript(Script(
          type: '自定义JS',
          params: {
            'js内容': '''
(function() {
  const el = document.querySelector(${jsonEncode(selector)});
  if (el) {
    el.click();
    return true;
  }
  return false;
})();
'''
                .trim(),
            '脚本名称': '点击元素 ($description)',
          },
          isEnabled: true,
        ));
        _lastRecordedActionController.add('点击元素: $description');
        break;
    }
  }

  void updateScript(int index, Script script) {
    if (_currentTab != null &&
        index >= 0 &&
        index < _currentTab!.scripts.length) {
      _currentTab!.scripts[index] = script;
      notifyListeners();
    }
  }

  Future<void> startExecution(
      InAppWebViewController controller, int tabIndex,
      [BrowserTab? targetTab]) async {
    final executingTab = targetTab ?? _currentTab;
    if (executingTab == null || executingTab.scripts.isEmpty || _isRecording) {
      return;
    }

    // 防重入拦截：若当前标签页已在执行脚本，忽略重复触发
    if (executingTab.isExecutingScript) {
      debugPrint(
          'Tab ${executingTab.id} is already executing script, skipping duplicate start.');
      return;
    }

    // 绑定执行控制器到当前目标标签页（避免切换标签页导致控制器错位）
    final executingController = executingTab.controller ?? controller;

    // 标记标签页进入执行状态（使用标签页独立状态，防止多标签页并发互相干扰）
    executingTab.isExecutingScript = true;
    executingTab.isPaused = false;
    executingTab.currentScriptIndex = 0;
    executingTab.successCount = 0;
    executingTab.failureCount = 0;

    if (!executingTab.hasCustomExecutionConfig) {
      executingTab.originalLoopCount = _originalLoopCount;
      executingTab.executionDelay = _executionDelay;
      executingTab.delayTimeUnit = _delayTimeUnit.label;
    }
    executingTab.remainingLoopCount = executingTab.originalLoopCount;
    executingTab.currentLoopIndex = 1;

    if (executingTab == _currentTab) {
      _isPaused = false;
      _currentScriptIndex = 0;
      _remainingLoopCount = executingTab.remainingLoopCount;
      _successCount = 0;
      _failureCount = 0;
    }

    // 初始化当前标签页独立变量字典（以全局预设变量为初始种子）
    executingTab.variables = Map<String, String>.from(_variables);

    for (var script in executingTab.scripts) {
      script.status = ScriptStatus.idle;
      script.statusMessage = null;
    }
    notifyListeners();

    // 自动化执行期间自动保持屏幕常亮与 CPU 保活
    try {
      await WakelockPlus.enable();
    } catch (_) {}

    // 循环执行：originalLoopCount 为 0 表示无限循环，否则按指定次数循环
    int startScriptIndex = 0;

    while (executingTab.isExecutingScript) {
      // 当前脚本集合的循环执行
      while (executingTab.isExecutingScript &&
          (executingTab.originalLoopCount == 0 ||
              executingTab.remainingLoopCount > 0)) {
        for (var i = startScriptIndex; i < executingTab.scripts.length; i++) {
          if (!executingTab.isExecutingScript) break;

          // 处理当前标签页的暂停状态（仅检查 executingTab.isPaused，避免阻塞其他后台标签页）
          while (executingTab.isPaused && executingTab.isExecutingScript) {
            await Future.delayed(const Duration(milliseconds: 100));
          }
          if (!executingTab.isExecutingScript) break;

          executingTab.currentScriptIndex = i;
          if (executingTab == _currentTab) {
            _currentScriptIndex = i;
          }
          notifyListeners();

          final script = executingTab.scripts[i];
          if (script.isEnabled) {
            await _executor.execute(
              executingController,
              script,
              executionDelay: executingTab.executionDelay,
              variables: executingTab.variables,
              onStatusChanged: (status, message, progress) async {
                script.status = status;
                script.statusMessage = message;
                script.progress = progress;

                if (status == ScriptStatus.success) {
                  executingTab.successCount++;
                  if (executingTab == _currentTab) {
                    _successCount = executingTab.successCount;
                  }
                } else if (status == ScriptStatus.failure) {
                  executingTab.failureCount++;
                  if (executingTab == _currentTab) {
                    _failureCount = executingTab.failureCount;
                  }
                } else if (status == ScriptStatus.stopped) {
                  executingTab.isExecutingScript = false;
                  if (script.params['执行完成提醒'] == true) {
                    _showNotification('Auok浏览器窗口${tabIndex + 1}', '脚本已停止');
                  }
                } else if (status == ScriptStatus.paused) {
                  executingTab.isPaused = true;
                  if (executingTab == _currentTab) {
                    _isPaused = true;
                  }
                  if (script.params['执行完成提醒'] == true) {
                    _showNotification('Auok浏览器窗口${tabIndex + 1}', '脚本已暂停');
                  }
                } else if (status == ScriptStatus.notification) {
                  // 处理脚本通知消息
                  _showNotification(
                      'Auok浏览器窗口${tabIndex + 1}', message ?? '');
                }

                notifyListeners();
              },
              waitForPageLoad: _waitForPageLoadCallback != null
                  ? ({String? preNavToken, String? preUrl}) =>
                      _waitForPageLoadCallback!(
                        preNavToken: preNavToken,
                        preUrl: preUrl,
                        targetTab: executingTab,
                      )
                  : null,
              scripts: executingTab.scripts,
            );

            // 处理脚本替换
            if (script.status == ScriptStatus.replaced &&
                script.statusMessage != null) {
              try {
                final newPath = script.statusMessage!;
                final file = File(newPath);
                if (await file.exists()) {
                  final content = await file.readAsString();
                  final jsonList = jsonDecode(content) as List;
                  final rawScripts =
                      jsonList.map((e) => Script.fromUserMap(e)).toList();

                  int newLoopCount = executingTab.originalLoopCount;
                  for (final s in rawScripts) {
                    if (s.type == '全局设置') {
                      if (s.params.containsKey('循环次数')) {
                        newLoopCount = s.params['循环次数'] as int? ?? 1;
                      }
                      if (s.params.containsKey('执行延迟')) {
                        final delay = s.params['执行延迟'] as int? ?? 1000;
                        final unitLabel = s.params['时间单位'] as String?;
                        final unit = unitLabel != null
                            ? TimeUnit.values.firstWhere(
                                (u) => u.label == unitLabel,
                                orElse: () => TimeUnit.milliseconds,
                              )
                            : TimeUnit.milliseconds;
                        executingTab.executionDelay = delay * unit.multiplier;
                        executingTab.delayTimeUnit = unit.label;
                      }
                    }
                  }

                  final newScripts =
                      rawScripts.where((s) => s.type != '全局设置').toList();

                  executingTab.scripts = newScripts;
                  executingTab.scriptFilePath = newPath;
                  executingTab.originalLoopCount = newLoopCount;
                  executingTab.remainingLoopCount = newLoopCount;
                  executingTab.currentLoopIndex = 1;
                  if (executingTab == _currentTab) {
                    _remainingLoopCount = newLoopCount;
                  }

                  i = -1; // 从新脚本列表开头重新开始
                  notifyListeners();
                } else {
                  debugPrint('Replacement script file not found: $newPath');
                }
              } catch (e) {
                debugPrint('Script replacement failed: $e');
              }
            }
            // 处理子脚本调用（压栈保存当前状态，执行完子脚本后恢复）
            else if (script.status == ScriptStatus.callSubroutine &&
                script.statusMessage != null) {
              try {
                final newPath = script.statusMessage!;
                final file = File(newPath);
                if (await file.exists()) {
                  final content = await file.readAsString();
                  final jsonList = jsonDecode(content) as List;
                  final rawScripts =
                      jsonList.map((e) => Script.fromUserMap(e)).toList();

                  // 将当前执行状态压入执行栈
                  executingTab.executionStack.add(ExecutionState(
                    scripts: List.from(executingTab.scripts),
                    currentScriptIndex: i,
                    originalLoopCount: executingTab.originalLoopCount,
                    remainingLoopCount: executingTab.remainingLoopCount,
                    currentLoopIndex: executingTab.currentLoopIndex,
                    scriptFilePath: executingTab.scriptFilePath,
                  ));

                  // 解析子脚本全局设置并过滤掉 '全局设置' 伪步骤
                  int newLoopCount = 1;
                  for (final s in rawScripts) {
                    if (s.type == '全局设置') {
                      newLoopCount = s.params['循环次数'] as int? ?? 1;
                      if (s.params.containsKey('执行延迟')) {
                        final delay = s.params['执行延迟'] as int? ?? 1000;
                        final unitLabel = s.params['时间单位'] as String?;
                        final unit = unitLabel != null
                            ? TimeUnit.values.firstWhere(
                                (u) => u.label == unitLabel,
                                orElse: () => TimeUnit.milliseconds,
                              )
                            : TimeUnit.milliseconds;
                        executingTab.executionDelay = delay * unit.multiplier;
                        executingTab.delayTimeUnit = unit.label;
                      }
                    }
                  }

                  final newScripts =
                      rawScripts.where((s) => s.type != '全局设置').toList();

                  // 切换到子脚本列表并重置循环计数器
                  executingTab.scripts = newScripts;
                  executingTab.scriptFilePath = newPath;
                  executingTab.originalLoopCount = newLoopCount;
                  executingTab.remainingLoopCount = newLoopCount;
                  executingTab.currentLoopIndex = 1;
                  if (executingTab == _currentTab) {
                    _remainingLoopCount = newLoopCount;
                  }

                  i = -1; // 从子脚本列表开头重新开始
                  notifyListeners();
                } else {
                  debugPrint('Subroutine script file not found: $newPath');
                }
              } catch (e) {
                debugPrint('Script subroutine call failed: $e');
              }
            }
            // 处理脚本跳转
            else if (script.status == ScriptStatus.jump &&
                script.statusMessage != null) {
              final targetIndex = int.tryParse(script.statusMessage!);
              if (targetIndex != null) {
                // 用户输入为 1 基索引，转换为 0 基索引
                final adjustedIndex = targetIndex - 1;
                if (adjustedIndex >= 0 &&
                    adjustedIndex < executingTab.scripts.length) {
                  // 设为 adjustedIndex - 1，因为 for 循环末尾会执行 i++
                  i = adjustedIndex - 1;
                  notifyListeners();
                } else {
                  debugPrint('Invalid jump index: $targetIndex');
                }
              }
            }
          }
        }

        // 重置下一轮循环的起始脚本索引
        startScriptIndex = 0;

        // 循环轮次递增
        executingTab.currentLoopIndex++;

        // 仅在非无限循环模式下递减剩余循环次数（0 表示无限循环）
        if (executingTab.isExecutingScript &&
            executingTab.originalLoopCount > 0) {
          executingTab.remainingLoopCount--;
          if (executingTab == _currentTab) {
            _remainingLoopCount = executingTab.remainingLoopCount;
          }
          notifyListeners();
        }
      }

      // 当前脚本集合执行完毕，检查执行栈是否需要返回上层脚本
      if (executingTab.isExecutingScript &&
          executingTab.executionStack.isNotEmpty) {
        final state = executingTab.executionStack.removeLast();
        executingTab.scripts = state.scripts;
        executingTab.originalLoopCount = state.originalLoopCount;
        executingTab.remainingLoopCount = state.remainingLoopCount;
        if (executingTab == _currentTab) {
          _remainingLoopCount = state.remainingLoopCount;
        }
        if (state.currentLoopIndex != null) {
          executingTab.currentLoopIndex = state.currentLoopIndex!;
        }
        executingTab.scriptFilePath = state.scriptFilePath;

        // 从子脚本调用处的下一条脚本继续执行
        startScriptIndex = state.currentScriptIndex + 1;

        notifyListeners();
      } else {
        break; // 全部脚本执行结束
      }
    }

    // 清理执行状态
    if (executingTab == _currentTab) {
      _currentScriptIndex = 0;
      _isPaused = false;
    }
    executingTab.isExecutingScript = false;
    executingTab.isPaused = false;
    executingTab.currentScriptIndex = 0;
    executingTab.executionStack.clear();
    notifyListeners();

    // 释放屏幕常亮
    try {
      await WakelockPlus.disable();
    } catch (_) {}
  }

  void stopExecution([BrowserTab? tab]) {
    final targetTab = tab ?? _currentTab;
    if (targetTab != null) {
      targetTab.isExecutingScript = false;
      targetTab.isPaused = false;
    }
    if (targetTab == _currentTab) {
      _isPaused = false;
    }
    notifyListeners();

    // 释放屏幕常亮
    try {
      WakelockPlus.disable();
    } catch (_) {}
  }

  void pauseExecution([BrowserTab? targetTab]) {
    final tab = targetTab ?? _currentTab;
    if (tab != null) {
      tab.isPaused = true;
    }
    if (tab == _currentTab) {
      _isPaused = true;
    }
    notifyListeners();
  }

  void resumeExecution([BrowserTab? targetTab]) {
    final tab = targetTab ?? _currentTab;
    if (tab != null) {
      tab.isPaused = false;
    }
    if (tab == _currentTab) {
      _isPaused = false;
    }
    notifyListeners();
  }

  String exportScript() {
    if (_currentTab == null) return '[]';

    final List<Map<String, dynamic>> jsonList = [];

    // 导出全局设置（优先使用当前标签页生效的延迟、单位与循环次数）
    final exportUnit = delayTimeUnit;
    final exportDelay = executionDelay;
    final exportLoop = originalLoopCount;
    jsonList.add({
      '脚本类型': '全局设置',
      '执行延迟': exportDelay ~/ exportUnit.multiplier,
      '时间单位': exportUnit.label,
      '循环次数': exportLoop,
    });

    for (var script in _currentTab!.scripts) {
      if (script.isEnabled) {
        jsonList.add(script.toUserMap());
      }
    }

    return json.encode(jsonList);
  }

  Future<void> _showNotification(String title, String body) async {
    if (Platform.isWindows) return;
    try {
      const AndroidNotificationDetails androidPlatformChannelSpecifics =
          AndroidNotificationDetails(
        'script_notification_channel',
        'Script Notifications',
        channelDescription: 'Notifications from scripts',
        importance: Importance.max,
        priority: Priority.high,
        ticker: 'Script Notification',
      );
      const DarwinNotificationDetails darwinPlatformSpecifics =
          DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
      );
      const NotificationDetails platformChannelSpecifics = NotificationDetails(
        android: androidPlatformChannelSpecifics,
        iOS: darwinPlatformSpecifics,
        macOS: darwinPlatformSpecifics,
      );
      await _flutterLocalNotificationsPlugin.show(
        DateTime.now().millisecondsSinceEpoch ~/ 1000,
        title,
        body,
        platformChannelSpecifics,
      );
    } catch (e) {
      debugPrint('Notification failed: $e');
    }
  }

  /// 将脚本内容批量导入到指定的标签页
  void importScriptToTab(String content, BrowserTab tab, [String? filePath]) {
    try {
      final List<dynamic> jsonList = json.decode(content);
      tab.scripts.clear();
      if (filePath != null) {
        tab.scriptFilePath = filePath;
      }

      for (var item in jsonList) {
        if (item is! Map<String, dynamic>) continue;

        final type = item['脚本类型'];
        if (type == '全局设置') {
          final delay = item['执行延迟'] as int? ?? 1000;
          final unitLabel = item['时间单位'] as String?;
          final unit = unitLabel != null
              ? TimeUnit.values.firstWhere(
                  (u) => u.label == unitLabel,
                  orElse: () => TimeUnit.milliseconds,
                )
              : TimeUnit.milliseconds;
          tab.delayTimeUnit = unit.label;
          tab.executionDelay = delay * unit.multiplier;
          if (item.containsKey('循环次数')) {
            tab.originalLoopCount = item['循环次数'] as int? ?? 1;
            tab.remainingLoopCount = tab.originalLoopCount;
          }
          tab.hasCustomExecutionConfig = true;

          if (tab == _currentTab) {
            _delayTimeUnit = unit;
            _executionDelay = tab.executionDelay;
            _originalLoopCount = tab.originalLoopCount;
            _remainingLoopCount = tab.remainingLoopCount;
          }
        } else {
          try {
            tab.scripts.add(Script.fromUserMap(item));
          } catch (e) {
            debugPrint('Parse script item error: $e');
          }
        }
      }
      notifyListeners();
    } catch (e) {
      debugPrint('Import script to tab error: $e');
    }
  }

  void importScript(String content) {
    if (_currentTab == null) return;

    try {
      final List<dynamic> jsonList = json.decode(content);
      _currentTab!.scripts.clear();

      for (var item in jsonList) {
        if (item is! Map<String, dynamic>) continue;

        final type = item['脚本类型'];
        if (type == '全局设置') {
          final delay = item['执行延迟'] as int? ?? 1000;
          final unitLabel = item['时间单位'] as String?;
          if (unitLabel != null) {
            _delayTimeUnit = TimeUnit.values.firstWhere(
              (u) => u.label == unitLabel,
              orElse: () => TimeUnit.milliseconds,
            );
            _executionDelay = delay * _delayTimeUnit.multiplier;
          } else {
            _delayTimeUnit = TimeUnit.milliseconds;
            _executionDelay = delay;
          }

          if (item.containsKey('循环次数')) {
            _originalLoopCount = item['循环次数'] as int? ?? 1;
            _remainingLoopCount = _originalLoopCount;
          }

          _currentTab!.delayTimeUnit = _delayTimeUnit.label;
          _currentTab!.executionDelay = _executionDelay;
          _currentTab!.originalLoopCount = _originalLoopCount;
          _currentTab!.remainingLoopCount = _remainingLoopCount;
          _currentTab!.hasCustomExecutionConfig = true;
        } else {
          try {
            _currentTab!.scripts.add(Script.fromUserMap(item));
          } catch (e) {
            debugPrint('Parse script item error: $e');
          }
        }
      }
      _saveScripts();
      notifyListeners();
    } catch (e) {
      debugPrint('Import script error: $e');
      // JSON 解析失败时回退到旧版逐行格式解析
      _importScriptLegacy(content);
    }
  }

  @override
  void dispose() {
    _lastRecordedActionController.close();
    super.dispose();
  }

  void _importScriptLegacy(String content) {
    if (_currentTab == null) return;

    try {
      final lines = content.split('\n');
      _currentTab!.scripts.clear();

      for (var line in lines) {
        if (line.trim().isEmpty) continue;
        try {
          final script = Script.fromJson(line);
          if (script.type == '全局变量') {
            // 兼容旧版全局设置逻辑
            final delay = script.params['执行延迟'] as int;
            final unitLabel = script.params['时间单位'] as String;
            final loop = script.params['循环次数'] as int;
            _delayTimeUnit = TimeUnit.values.firstWhere(
              (u) => u.label == unitLabel,
              orElse: () => TimeUnit.milliseconds,
            );
            _executionDelay = delay * _delayTimeUnit.multiplier;
            _originalLoopCount = loop;
            _remainingLoopCount = loop;
            _currentTab!.delayTimeUnit = _delayTimeUnit.label;
            _currentTab!.executionDelay = _executionDelay;
            _currentTab!.originalLoopCount = _originalLoopCount;
            _currentTab!.remainingLoopCount = _remainingLoopCount;
            _currentTab!.hasCustomExecutionConfig = true;
          } else {
            _currentTab!.scripts.add(script);
          }
        } catch (e) {
          debugPrint('Legacy parse error: $e');
        }
      }
      _saveScripts();
      notifyListeners();
    } catch (e) {
      debugPrint('Legacy import error: $e');
    }
  }

  static const String recordingJs = r'''
    (function() {
      if (window._auokRecorderInjected) return;
      window._auokRecorderInjected = true;

      function postMessage(msg) {
        if (window.flutter_inappwebview && window.flutter_inappwebview.callHandler) {
          window.flutter_inappwebview.callHandler('ScriptRunner', msg);
        } else if (window.ScriptRunner) {
          // 兼容旧版 WebView 桥接方式
          window.ScriptRunner.postMessage(msg);
        }
      }

      // 收集表单输入数据
      function collectFormData(form) {
        let formData = {};
        let inputs = form.querySelectorAll('input, textarea, select');
        
        inputs.forEach(function(input) {
          if (input.type === 'hidden' || 
              input.type === 'button' || 
              input.type === 'submit' ||
              input.type === 'reset' ||
              input.type === 'image') {
            return;
          }
          
          if (input.name) {
            formData[input.name] = input.value;
          } else if (input.id) {
             // 若缺少 name 属性则回退使用 id
             formData[input.id] = input.value;
          }
        });
        return formData;
      }

      // 1. 捕获表单提交事件
      document.addEventListener('submit', function(e) {
        let form = e.target;
        let formData = collectFormData(form);
        
        // 查找触发表单提交的按钮文字，若未找到则默认使用“提交”
        let submitBtn = form.querySelector('button[type="submit"], input[type="submit"]');
        let buttonText = '提交';
        if (submitBtn) {
           buttonText = submitBtn.value || submitBtn.innerText || submitBtn.textContent || '提交';
        }

        let data = {
          '按钮文本': buttonText.trim(),
          '表单数据': formData
        };
        postMessage('点击提交按钮|' + JSON.stringify(data));
      }, true);

      // 2. 捕获输入框回车提交事件
      document.addEventListener('keydown', function(e) {
        if (e.key === 'Enter') {
          let target = e.target;
          if (target.tagName === 'INPUT') {
            let form = target.closest('form');
            if (form) {
              setTimeout(function() {
                 let formData = collectFormData(form);
                 let data = {
                   '按钮文本': 'Enter键提交',
                   '表单数据': formData
                 };
                 postMessage('点击提交按钮|' + JSON.stringify(data));
              }, 100);
            }
          }
        }
      }, true);

      // 3. 白鹭引擎 (Egret) Canvas 游戏虚拟点击捕获机制 (捕获阶段深度拦截)
      var lastCanvasRecordTime = 0;
      function tryRecordEgretCanvas(target, clientX, clientY) {
        if (!target) return false;
        var now = Date.now();
        if (now - lastCanvasRecordTime < 400) return true; // 400ms防抖去重

        try {
          function findEgretStage(obj, depth) {
            if (!obj || depth > 3) return null;
            if (obj.$hitTest || obj.hitTest) return obj;
            if (obj.stage && (obj.stage.$hitTest || obj.stage.hitTest)) return obj.stage;
            for (var k in obj) {
              try {
                if (k.startsWith('$') || k.indexOf('egret') !== -1 || k === 'player' || k === 'stage') {
                  var res = findEgretStage(obj[k], depth + 1);
                  if (res) return res;
                }
              } catch(_) {}
            }
            return null;
          }

          function getEgretContext(initialTarget) {
            var targetCanvas = initialTarget && initialTarget.tagName === 'CANVAS' ? initialTarget : null;
            var stage = targetCanvas ? findEgretStage(targetCanvas, 0) : null;

            if (!stage) {
              var canvases = Array.from(document.querySelectorAll('canvas'));
              for (var i = 0; i < canvases.length; i++) {
                stage = findEgretStage(canvases[i], 0);
                if (stage) { targetCanvas = canvases[i]; break; }
              }
            }

            if (!stage) {
              var player = document.querySelector('.egret-player, [data-entry-class]');
              if (player) {
                stage = findEgretStage(player, 0);
                if (stage) targetCanvas = player.querySelector('canvas') || document.querySelector('canvas');
              }
            }

            if (!stage && typeof window !== 'undefined') {
              if (window.stage) stage = findEgretStage(window.stage, 0);
              if (!stage && window.egret) {
                if (window.egret.MainContext && window.egret.MainContext.instance && window.egret.MainContext.instance.stage) {
                  stage = window.egret.MainContext.instance.stage;
                } else if (window.egret.lifecycle && window.egret.lifecycle.stage) {
                  stage = window.egret.lifecycle.stage;
                } else {
                  stage = findEgretStage(window.egret, 0);
                }
              }
              if (!stage && window.player) stage = findEgretStage(window.player, 0);
              if (stage && !targetCanvas) targetCanvas = document.querySelector('canvas');
            }

            if (!stage) {
              var iframes = Array.from(document.querySelectorAll('iframe'));
              for (var f = 0; f < iframes.length; f++) {
                try {
                  var idoc = iframes[f].contentDocument || (iframes[f].contentWindow && iframes[f].contentWindow.document);
                  var iwin = iframes[f].contentWindow;
                  if (idoc) {
                    var icanvases = Array.from(idoc.querySelectorAll('canvas'));
                    for (var c = 0; c < icanvases.length; c++) {
                      stage = findEgretStage(icanvases[c], 0);
                      if (stage) { targetCanvas = icanvases[c]; break; }
                    }
                    if (stage) break;
                  }
                } catch(_) {}
              }
            }

            return (stage && targetCanvas) ? { stage: stage, canvas: targetCanvas } : null;
          }

          var ctx = getEgretContext(target);
          if (!ctx) return false;

          var stage = ctx.stage;
          var canvas = ctx.canvas;
          var rect = canvas.getBoundingClientRect();

          // 核心换算：基于白鹭舞台逻辑分辨率精确折算物理触控点
          var stageW = (stage && stage.stageWidth) ? stage.stageWidth : (canvas.width || rect.width);
          var stageH = (stage && stage.stageHeight) ? stage.stageHeight : (canvas.height || rect.height);
          var scaleX = stageW / (rect.width || 1);
          var scaleY = stageH / (rect.height || 1);
          var stageX = (clientX - rect.left) * scaleX;
          var stageY = (clientY - rect.top) * scaleY;

          var egretItems = [];
          function traverse(node) {
            if (!node || node.visible === false) return;
            var rawText = node.text || (node.labelDisplay && node.labelDisplay.text) || node.label || node.title || node.prompt;
            if (typeof rawText === 'string') {
              var cleanText = rawText.trim();
              if (cleanText !== '') {
                var isClickable = Boolean(
                  node.touchEnabled ||
                  (node.$EventDispatcher && node.$EventDispatcher.$events && node.$EventDispatcher.$events['touchTap']) ||
                  (typeof node.hasEventListener === 'function' && node.hasEventListener('touchTap'))
                );

                var p = node.parent;
                var climb = 0;
                while (p && climb < 4) {
                  if (p.touchEnabled ||
                      (p.$EventDispatcher && p.$EventDispatcher.$events && p.$EventDispatcher.$events['touchTap']) ||
                      (typeof p.hasEventListener === 'function' && p.hasEventListener('touchTap'))) {
                    isClickable = true;
                    break;
                  }
                  p = p.parent;
                  climb++;
                }

                var gx = Math.round(node.x || 0);
                var gy = Math.round(node.y || 0);
                if (typeof node.localToGlobal === 'function') {
                  try {
                    var pt = node.localToGlobal(0, 0);
                    if (pt && typeof pt.x === 'number') {
                      gx = Math.round(pt.x);
                      gy = Math.round(pt.y);
                    }
                  } catch(_) {}
                }

                egretItems.push({
                  text: cleanText,
                  rawText: rawText,
                  target: node,
                  x: gx,
                  y: gy,
                  w: node.width || (p && p.width) || 60,
                  h: node.height || (p && p.height) || 30,
                  isClickable: isClickable
                });
              }
            }

            if (node.$children && node.$children.length > 0) {
              for (var i = 0; i < node.$children.length; i++) traverse(node.$children[i]);
            } else if (node.numChildren && node.getChildAt) {
              for (var i = 0; i < node.numChildren; i++) traverse(node.getChildAt(i));
            }
          }

          traverse(stage);

          var hitCandidate = null;
          var minDistance = 999999;

          for (var i = 0; i < egretItems.length; i++) {
            var item = egretItems[i];
            var padding = 20; // 宽裕容错区，确保点在按钮附近也能准确识别
            var inside = (stageX >= item.x - padding && stageX <= item.x + item.w + padding &&
                          stageY >= item.y - padding && stageY <= item.y + item.h + padding);
            var centerX = item.x + item.w / 2;
            var centerY = item.y + item.h / 2;
            var dist = Math.hypot(stageX - centerX, stageY - centerY);

            if (inside) {
              if (!hitCandidate || (item.isClickable && !hitCandidate.isClickable) || (dist < minDistance)) {
                hitCandidate = item;
                minDistance = dist;
              }
            } else if (!hitCandidate && dist < 65 && dist < minDistance) {
              hitCandidate = item;
              minDistance = dist;
            }
          }

          if (hitCandidate) {
            lastCanvasRecordTime = now;
            var candidateText = hitCandidate.text;

            // 录制成功视觉动效反馈
            try {
              var ring = document.createElement('div');
              ring.className = '_auok_tap_indicator';
              var ringW = Math.max(32, hitCandidate.w * (rect.width / stageW));
              var ringH = Math.max(22, hitCandidate.h * (rect.height / stageH));
              var ringLeft = rect.left + hitCandidate.x * (rect.width / stageW);
              var ringTop = rect.top + hitCandidate.y * (rect.height / stageH);
              ring.style.cssText = 'position:fixed;left:' + ringLeft + 'px;top:' + ringTop + 'px;width:' + ringW + 'px;height:' + ringH + 'px;border-radius:6px;box-shadow:0 0 0 3px #10b981, 0 0 16px rgba(16,185,129,0.7);background:rgba(16,185,129,0.25);pointer-events:none;z-index:2147483647;transition:all 0.28s ease-out;';
              document.documentElement.appendChild(ring);
              setTimeout(function() {
                ring.style.transform = 'scale(1.15)';
                ring.style.opacity = '0';
                setTimeout(function() { if (ring.parentNode) ring.parentNode.removeChild(ring); }, 300);
              }, 220);
            } catch(_) {}

            var sameTextItems = egretItems.filter(function(it) { return it.text === candidateText; });
            var itemIdx = sameTextItems.indexOf(hitCandidate);
            var idx = itemIdx !== -1 ? itemIdx + 1 : 1;
            var total = sameTextItems.length;

            postMessage('点击文字|' + JSON.stringify({
              text: candidateText,
              index: idx,
              total: total
            }));
            return true;
          }
        } catch(err) {
          console.warn('[Auok] Egret canvas recording error:', err);
        }
        return false;
      }

      // 4. 多重事件深度捕获 (针对白鹭移动端 touchstart 被 preventDefault 场景进行兜底拦截)
      function extractCanvasFromEvent(e) {
        if (e.target && e.target.tagName === 'CANVAS') return e.target;
        if (e.composedPath) {
          var path = e.composedPath();
          for (var i = 0; i < path.length; i++) {
            if (path[i] && path[i].tagName === 'CANVAS') return path[i];
          }
        }
        return null;
      }

      // 捕获阶段监听 touchstart / touchend (关键修复：移动端白鹭引擎调用了 preventDefault，click事件不会发生)
      document.addEventListener('touchend', function(e) {
        var touch = (e.changedTouches && e.changedTouches[0]) || (e.touches && e.touches[0]);
        if (!touch) return;
        var canvas = extractCanvasFromEvent(e);
        if (canvas) {
          tryRecordEgretCanvas(canvas, touch.clientX, touch.clientY);
        }
      }, true);

      document.addEventListener('touchstart', function(e) {
        var touch = (e.touches && e.touches[0]) || (e.changedTouches && e.changedTouches[0]);
        if (!touch) return;
        var canvas = extractCanvasFromEvent(e);
        if (canvas) {
          tryRecordEgretCanvas(canvas, touch.clientX, touch.clientY);
        }
      }, true);

      // 捕获 PointerUp
      document.addEventListener('pointerup', function(e) {
        var canvas = extractCanvasFromEvent(e);
        if (canvas) {
          tryRecordEgretCanvas(canvas, e.clientX, e.clientY);
        }
      }, true);

      // 5. 捕获页面点击事件
      document.addEventListener('click', function(e) {
        // 过滤右侧侧边栏切换手柄区域 (防止手柄点击被网页穿透录制)
        var winW = window.innerWidth || (document.documentElement && document.documentElement.clientWidth) || 360;
        var winH = window.innerHeight || (document.documentElement && document.documentElement.clientHeight) || 640;
        if (e.clientX >= (winW - 45) && e.clientY >= (winH / 2 - 140) && e.clientY <= (winH / 2 + 100)) {
          return;
        }

        let target = e.target;
        
        // 处理文本节点
        if (target.nodeType === 3) {
          target = target.parentElement;
        }
        
        if (!target) return;

        // 优先拦截 Canvas 游戏虚拟点击
        var canvas = extractCanvasFromEvent(e);
        if (canvas) {
          if (tryRecordEgretCanvas(canvas, e.clientX, e.clientY)) {
            return;
          }
        }

        // 优先级 1：图片元素
        if (target.tagName === 'IMG') {
          postMessage('点击图片|' + (target.src || ''));
          return;
        }

        // 背景图片元素
        let isBgImage = false;
        try {
          let computedStyle = window.getComputedStyle(target);
          isBgImage = computedStyle.backgroundImage !== 'none';
          if (!isBgImage && target.parentElement) {
             computedStyle = window.getComputedStyle(target.parentElement);
             isBgImage = computedStyle.backgroundImage !== 'none';
          }
        } catch (e) {}
        
        if (isBgImage) {
          postMessage('点击图片|');
          return;
        }

        // 智能完全匹配与多重元素定位函数（算法与 ScriptExecutor 100% 对齐）
        function getExactMatchInfo(clickedElement, targetText) {
          var trimmedTarget = (targetText || '').trim();
          if (!trimmedTarget) return { index: 1, total: 1 };

          // 优先检索常见可交互与文本容器节点，与执行器 candidateSelectors 一致
          var candidateSelectors = 'a, button, input, [role="button"], [onclick], label, span, p, h1, h2, h3, h4, h5, h6, li, td, th, b, strong, em, div';
          var allElements = Array.from(document.querySelectorAll(candidateSelectors));

          // 严格完全匹配 (trim 后全等)
          var matchedElements = allElements.filter(function(el) {
            var text = el.innerText || el.textContent || el.value || '';
            return text.trim() === trimmedTarget;
          });

          // 高效剪枝：优先保留最深层叶子匹配节点（与 ScriptExecutor 剪枝算法 100% 对齐）
          if (matchedElements.length > 1) {
            var leafMatched = [];
            for (var i = 0; i < matchedElements.length; i++) {
              var el = matchedElements[i];
              var isContainerOfOther = false;
              for (var j = 0; j < matchedElements.length; j++) {
                if (i !== j && el.contains(matchedElements[j])) {
                  isContainerOfOther = true;
                  break;
                }
              }
              if (!isContainerOfOther) {
                leafMatched.push(el);
              }
            }
            if (leafMatched.length > 0) {
              matchedElements = leafMatched;
            }
          }

          var total = matchedElements.length;
          if (total === 0) return { index: 1, total: 1 };

          // 定位当前被点击元素在 matchedElements 中的位置（支持精确节点或父子包含）
          var index = matchedElements.findIndex(function(el) {
            return el === clickedElement || el.contains(clickedElement) || clickedElement.contains(el);
          });

          return {
            index: index !== -1 ? index + 1 : 1,
            total: total
          };
        }

        // 优先级 2：链接与按钮交互元素 (a, button, role=button, input[type=button/submit])
        var linkElement = target.closest('a');
        if (linkElement) {
          var linkText = (linkElement.innerText || linkElement.textContent || '').trim();
          if (linkText && linkText.length < 100) {
            var linkInfo = getExactMatchInfo(linkElement, linkText);
            postMessage('点击文字|' + JSON.stringify({
              text: linkText,
              index: linkInfo.index,
              total: linkInfo.total
            }));
            return;
          }
        }

        var btnElement = target.closest('button');
        if (btnElement) {
          var btnText = (btnElement.innerText || btnElement.textContent || btnElement.value || '').trim();
          if (btnText && btnText.length < 100) {
            var btnInfo = getExactMatchInfo(btnElement, btnText);
            postMessage('点击文字|' + JSON.stringify({
              text: btnText,
              index: btnInfo.index,
              total: btnInfo.total
            }));
            return;
          }
        }

        var roleBtn = target.closest('[role="button"]');
        if (roleBtn) {
          var roleBtnText = (roleBtn.innerText || roleBtn.textContent || '').trim();
          if (roleBtnText && roleBtnText.length < 100) {
            var roleBtnInfo = getExactMatchInfo(roleBtn, roleBtnText);
            postMessage('点击文字|' + JSON.stringify({
              text: roleBtnText,
              index: roleBtnInfo.index,
              total: roleBtnInfo.total
            }));
            return;
          }
        }

        // input 按钮（type="button", "submit", "reset"）
        if (target.tagName === 'INPUT' && (target.type === 'button' || target.type === 'submit' || target.type === 'reset')) {
          var btnVal = (target.value || '').trim();
          if (btnVal && btnVal.length < 100) {
            var inputBtnInfo = getExactMatchInfo(target, btnVal);
            postMessage('点击文字|' + JSON.stringify({
              text: btnVal,
              index: inputBtnInfo.index,
              total: inputBtnInfo.total
            }));
            return;
          }
        }

        // 通用文本节点（span, p, div, label, li 等）
        if (target.tagName !== 'INPUT' && target.tagName !== 'TEXTAREA' && target.tagName !== 'SELECT') {
          var text = (target.innerText || target.textContent || '').trim();
          if (text.length > 0 && text.length < 60) {
            var genericInfo = getExactMatchInfo(target, text);
            postMessage('点击文字|' + JSON.stringify({
              text: text,
              index: genericInfo.index,
              total: genericInfo.total
            }));
            return;
          }
        }

        // 优先级 3：无文本交互元素（SVG 图标、字体图标、纯图标按钮）生成 CSS 选择器
        function getCssSelector(el) {
          if (el.id) return '#' + el.id;
          let path = [];
          let current = el;
          while (current && current.nodeType === 1 && current.tagName.toLowerCase() !== 'body' && current.tagName.toLowerCase() !== 'html') {
            let selector = current.tagName.toLowerCase();
            if (current.id) {
              selector += '#' + current.id;
              path.unshift(selector);
              break;
            } else if (current.className && typeof current.className === 'string') {
              let classes = current.className.trim().split(new RegExp('\\\\s+')).filter(c => c && !c.includes(':') && !c.startsWith('ng-'));
              if (classes.length > 0) {
                selector += '.' + classes.slice(0, 2).join('.');
              }
            }
            let parent = current.parentElement;
            if (parent) {
              let siblings = Array.from(parent.children).filter(child => child.tagName === current.tagName);
              if (siblings.length > 1) {
                let index = siblings.indexOf(current) + 1;
                selector += ':nth-of-type(' + index + ')';
              }
            }
            path.unshift(selector);
            current = parent;
            if (path.length >= 3) break;
          }
          return path.join(' > ');
        }

        // 仅针对真正无文本的可交互元素（如 SVG矢量图标、字体图标、纯图标按钮、或声明了 cursor: pointer 的交互组件）
        var clickableParent = target.closest('button, [role="button"], a, svg, i, [onclick]');
        if (!clickableParent) {
          try {
            var compStyle = window.getComputedStyle(target);
            if (compStyle.cursor === 'pointer' && target.tagName !== 'BODY' && target.tagName !== 'HTML') {
              clickableParent = target;
            }
          } catch (_) {}
        }

        // 核心过滤：若仅是普通网页空白区域（如无文字背景容器、body、html等），直接忽略不录制
        if (!clickableParent) {
          return;
        }

        if (clickableParent.tagName !== 'INPUT' && clickableParent.tagName !== 'TEXTAREA') {
          var selector = getCssSelector(clickableParent);
          if (selector) {
            var tagDesc = clickableParent.tagName.toLowerCase();
            postMessage('点击选择器|' + selector + '|' + tagDesc);
          }
        }
      }, true);
    })();
  ''';
}
