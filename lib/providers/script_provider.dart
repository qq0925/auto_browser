import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import '../models/script.dart';
import '../services/script_executor.dart';
import 'dart:convert';
import 'dart:async';
import 'package:shared_preferences/shared_preferences.dart';

class ScriptProvider extends ChangeNotifier {
  final List<Script> _scripts = [];
  bool _isRecording = false;
  bool _isExecuting = false;
  bool _isPaused = false;
  int _currentScriptIndex = 0;
  int _executionDelay = 1000;
  int _originalLoopCount = 1;
  int _remainingLoopCount = 1;
  TimeUnit _delayTimeUnit = TimeUnit.milliseconds;
  int _successCount = 0;
  int _failureCount = 0;

  final ScriptExecutor _executor = ScriptExecutor();

  List<Script> get scripts => _scripts;
  bool get isRecording => _isRecording;
  bool get isExecuting => _isExecuting;
  bool get isPaused => _isPaused;
  int get currentScriptIndex => _currentScriptIndex;
  int get executionDelay => _executionDelay;
  int get originalLoopCount => _originalLoopCount;
  int get remainingLoopCount => _remainingLoopCount;
  TimeUnit get delayTimeUnit => _delayTimeUnit;
  int get successCount => _successCount;
  int get failureCount => _failureCount;

  ScriptProvider() {
    _loadScripts();
  }

  Future<void> _loadScripts() async {
    try {
      final prefs = await SharedPreferences.getInstance();

      // Load global settings
      _executionDelay = prefs.getInt('script_global_delay') ?? 1000;
      _originalLoopCount = prefs.getInt('script_global_loop') ?? 1;
      final unitIndex = prefs.getInt('script_global_unit') ?? 0;
      if (unitIndex >= 0 && unitIndex < TimeUnit.values.length) {
        _delayTimeUnit = TimeUnit.values[unitIndex];
      }

      // Load scripts
      final scriptsList = prefs.getStringList('scripts_list');
      if (scriptsList != null) {
        _scripts.clear();
        for (var jsonStr in scriptsList) {
          try {
            _scripts.add(Script.fromJson(jsonStr));
          } catch (e) {
            debugPrint('Error loading script item: $e');
          }
        }
      }
      notifyListeners();
    } catch (e) {
      debugPrint('Error loading scripts: $e');
    }
  }

  Future<void> _saveScripts() async {
    try {
      final prefs = await SharedPreferences.getInstance();

      // Save global settings
      await prefs.setInt('script_global_delay', _executionDelay);
      await prefs.setInt('script_global_loop', _originalLoopCount);
      await prefs.setInt('script_global_unit', _delayTimeUnit.index);

      // Save scripts
      final scriptsList = _scripts.map((s) => s.toJson()).toList();
      await prefs.setStringList('scripts_list', scriptsList);
    } catch (e) {
      debugPrint('Error saving scripts: $e');
    }
  }

  void setExecutionDelay(int delay) {
    _executionDelay = delay;
    _saveScripts();
    notifyListeners();
  }

  void setDelayTimeUnit(TimeUnit unit) {
    _delayTimeUnit = unit;
    _saveScripts();
    notifyListeners();
  }

  void setLoopCount(int count) {
    _originalLoopCount = count;
    _remainingLoopCount = count;
    _saveScripts();
    notifyListeners();
  }

  void startRecording() {
    if (_isExecuting) return; // Prevent recording while executing
    _isRecording = true;
    notifyListeners();
  }

  void stopRecording() {
    _isRecording = false;
    notifyListeners();
  }

  void clearScripts() {
    _scripts.clear();
    _saveScripts();
    notifyListeners();
  }

  void addScript(Script script) {
    _scripts.add(script);
    _saveScripts();
    notifyListeners();
  }

  void removeScript(int index) {
    if (index >= 0 && index < _scripts.length) {
      _scripts.removeAt(index);
      _saveScripts();
      notifyListeners();
    }
  }

  void toggleScriptEnabled(int index, bool value) {
    if (index >= 0 && index < _scripts.length) {
      _scripts[index].isEnabled = value;
      _saveScripts();
      notifyListeners();
    }
  }

  // Stream controller for last recorded action to trigger UI animation
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

    final parts = message.split('|');
    if (parts.length != 2) return;

    final type = parts[0];
    final content = parts[1];

    switch (type) {
      case '点击文字':
        addScript(Script(
          type: type,
          params: {'点击文本': content},
          isEnabled: true,
        ));
        _lastRecordedActionController.add('点击文字: $content');
        break;
      case '点击图片':
        // Image click from JS
        addScript(Script(
          type: '点击图片',
          params: {}, // Image click usually doesn't need params in this simple model
          isEnabled: true,
        ));
        _lastRecordedActionController.add('点击图片');
        break;
      case '输入框提交':
        try {
          final data = json.decode(content) as Map<String, dynamic>;
          addScript(Script(
            type: type,
            params: data,
            isEnabled: true,
          ));
          _lastRecordedActionController.add('输入框提交: ${data['value']}');
        } catch (e) {
          debugPrint('Parse input data error: $e');
        }
        break;
    }
  }

  void updateScript(int index, Script script) {
    if (index >= 0 && index < _scripts.length) {
      _scripts[index] = script;
      _saveScripts();
      notifyListeners();
    }
  }

  Future<void> startExecution(WebViewController controller) async {
    if (_scripts.isEmpty || _isRecording) return;

    _isExecuting = true;
    _isPaused = false;
    _currentScriptIndex = 0;
    _currentScriptIndex = 0;
    _remainingLoopCount = _originalLoopCount;
    _successCount = 0;
    _failureCount = 0;

    // Reset status for all scripts
    for (var script in _scripts) {
      script.status = ScriptStatus.idle;
      script.statusMessage = null;
    }
    notifyListeners();

    while (_remainingLoopCount > 0 && _isExecuting) {
      for (var i = 0; i < _scripts.length; i++) {
        if (!_isExecuting) break;

        // Handle pause
        while (_isPaused && _isExecuting) {
          await Future.delayed(const Duration(milliseconds: 100));
        }

        _currentScriptIndex = i;
        notifyListeners();

        final script = _scripts[i];
        if (script.isEnabled) {
          await _executor.execute(
            controller,
            script,
            executionDelay: _executionDelay,
            onStatusChanged: (status, message) {
              script.status = status;
              script.statusMessage = message;
              script.status = status;
              script.statusMessage = message;
              if (status == ScriptStatus.success) {
                _successCount++;
              } else if (status == ScriptStatus.failure) {
                _failureCount++;
              }
              notifyListeners();
            },
          );
        }

        // Global delay between scripts
        if (i < _scripts.length - 1) {
          await Future.delayed(Duration(milliseconds: _executionDelay));
        }
      }

      if (_isExecuting) {
        _remainingLoopCount--;
        notifyListeners();
      }
    }

    _isExecuting = false;
    _currentScriptIndex = 0;
    notifyListeners();
  }

  void stopExecution() {
    _isExecuting = false;
    _isPaused = false;
    notifyListeners();
  }

  void pauseExecution() {
    _isPaused = true;
    notifyListeners();
  }

  void resumeExecution() {
    _isPaused = false;
    notifyListeners();
  }

  String exportScript() {
    final List<Map<String, dynamic>> jsonList = [];

    // Add global settings
    jsonList.add({
      '脚本类型': '全局设置',
      '执行延迟': _executionDelay ~/ _delayTimeUnit.multiplier,
      // Note: User JSON example used '执行延迟' for global delay, assuming unit is implied or standard.
      // But to be safe and consistent with my internal logic, I'll save what I have.
      // The user example: "执行延迟": 1000.
    });

    for (var script in _scripts) {
      if (script.isEnabled) {
        jsonList.add(script.toUserMap());
      }
    }

    return json.encode(jsonList);
  }

  void importScript(String content) {
    try {
      final List<dynamic> jsonList = json.decode(content);
      _scripts.clear();

      for (var item in jsonList) {
        if (item is! Map<String, dynamic>) continue;

        final type = item['脚本类型'];
        if (type == '全局设置') {
          final delay = item['执行延迟'] as int? ?? 1000;
          // User JSON doesn't explicitly show unit, assuming milliseconds or matching current logic.
          // If the user JSON implies milliseconds:
          _executionDelay = delay;
          // If we want to respect the unit, we might need to infer or default.
          // Let's assume milliseconds for now as per "执行延迟": 1000 (1 second).
          _delayTimeUnit = TimeUnit.milliseconds;

          // User JSON didn't show loop count in global settings example, but if it exists:
          if (item.containsKey('循环次数')) {
            _originalLoopCount = item['循环次数'] as int;
          }
        } else {
          try {
            _scripts.add(Script.fromUserMap(item));
          } catch (e) {
            debugPrint('Parse script item error: $e');
          }
        }
      }
      _saveScripts();
      notifyListeners();
    } catch (e) {
      debugPrint('Import script error: $e');
      // Fallback to old line-by-line format if JSON decode fails
      _importScriptLegacy(content);
    }
  }

  void _importScriptLegacy(String content) {
    try {
      final lines = content.split('\n');
      _scripts.clear();

      for (var line in lines) {
        if (line.trim().isEmpty) continue;
        try {
          final script = Script.fromJson(line);
          if (script.type == '全局变量') {
            // Legacy global settings logic
            final delay = script.params['执行延迟'] as int;
            final unitLabel = script.params['时间单位'] as String;
            final loop = script.params['循环次数'] as int;
            _delayTimeUnit = TimeUnit.values.firstWhere(
              (u) => u.label == unitLabel,
              orElse: () => TimeUnit.milliseconds,
            );
            _executionDelay = delay * _delayTimeUnit.multiplier;
            _originalLoopCount = loop;
          } else {
            _scripts.add(script);
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

  static const String recordingJs = '''
    (function() {
      if (window._auokRecorderInjected) return;
      window._auokRecorderInjected = true;

      document.addEventListener('click', function(e) {
        let target = e.target;
        
        // Handle text nodes (nodeType 3)
        if (target.nodeType === 3) {
          target = target.parentElement;
        }
        
        if (!target) return;

        // Check for image
        // Safe check for getComputedStyle
        let isBgImage = false;
        try {
          isBgImage = window.getComputedStyle(target).backgroundImage !== 'none';
        } catch (e) {}

        if (target.tagName === 'IMG' || isBgImage) {
           ScriptRunner.postMessage('点击图片|');
           return;
        }

        let text = target.innerText || target.textContent;
        if (!text || text.trim() === '') {
          let parent = target.parentElement;
          if (parent) {
            text = parent.innerText || parent.textContent;
          }
        }
        
        if (text && text.trim().length > 0) {
          text = text.trim().substring(0, 50);
          ScriptRunner.postMessage('点击文字|' + text);
        }
      }, true);

      document.addEventListener('change', function(e) {
        let target = e.target;
        if (target.tagName === 'INPUT' || target.tagName === 'TEXTAREA') {
          let data = {
            'xpath': '',
            'value': target.value
          };
          ScriptRunner.postMessage('输入框提交|' + JSON.stringify(data));
        }
      }, true);
    })();
  ''';
}
