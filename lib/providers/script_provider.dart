import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import '../models/script.dart';
import '../models/browser_tab.dart';
import '../services/script_runner.dart';
import 'browser_provider.dart';
import 'dart:convert';
import 'dart:async';

class ScriptProvider extends ChangeNotifier {
  BrowserProvider? _browserProvider;
  final Map<String, ScriptRunner> _runners = {};

  bool _isRecording = false;
  Future<void> Function()? _waitForPageLoadCallback;

  // Getters that delegate to current tab/runner
  BrowserTab? get _currentTab => _browserProvider?.currentTab;
  ScriptRunner? get _currentRunner {
    if (_currentTab == null) return null;
    if (!_runners.containsKey(_currentTab!.id)) {
      _runners[_currentTab!.id] = ScriptRunner(_currentTab!);
      // Listen to runner changes to propagate notifications
      _runners[_currentTab!.id]!.addListener(notifyListeners);
    }
    return _runners[_currentTab!.id];
  }

  List<Script> get scripts => _currentTab?.scripts ?? [];
  bool get isRecording => _isRecording;
  bool get isExecuting => _currentTab?.isExecutingScript ?? false;
  bool get isPaused => _currentRunner?.isPaused ?? false;
  int get currentScriptIndex => _currentTab?.currentScriptIndex ?? 0;

  int get executionDelay => _currentTab?.executionDelay ?? 1000;
  int get originalLoopCount => _currentTab?.originalLoopCount ?? 1;
  int get remainingLoopCount => _currentTab?.remainingLoopCount ?? 1;
  TimeUnit get delayTimeUnit =>
      _currentTab?.delayTimeUnit ?? TimeUnit.milliseconds;

  int get successCount => _currentTab?.successCount ?? 0;
  int get failureCount => _currentTab?.failureCount ?? 0;

  void update(BrowserProvider browserProvider) {
    _browserProvider = browserProvider;
    notifyListeners();
  }

  void setWaitForPageLoadCallback(Future<void> Function() callback) {
    _waitForPageLoadCallback = callback;
  }

  ScriptProvider();

  // Settings Setters
  void setExecutionDelay(int delay) {
    if (_currentTab != null) {
      _currentTab!.executionDelay = delay;
      _browserProvider?.notifyListeners(); // Trigger save
      notifyListeners();
    }
  }

  void setDelayTimeUnit(TimeUnit unit) {
    if (_currentTab != null) {
      _currentTab!.delayTimeUnit = unit;
      _browserProvider?.notifyListeners();
      notifyListeners();
    }
  }

  void setLoopCount(int count) {
    if (_currentTab != null) {
      _currentTab!.originalLoopCount = count;
      _currentTab!.remainingLoopCount = count;
      _browserProvider?.notifyListeners();
      notifyListeners();
    }
  }

  // Recording
  void startRecording() {
    if (isExecuting) return;
    _isRecording = true;
    notifyListeners();
  }

  void stopRecording() {
    _isRecording = false;
    notifyListeners();
  }

  // Script Management
  void clearScripts() {
    if (_currentTab != null) {
      _currentTab!.scripts.clear();
      _browserProvider?.notifyListeners();
      notifyListeners();
    }
  }

  void addScript(Script script) {
    if (_currentTab != null) {
      _currentTab!.scripts.add(script);
      _browserProvider?.notifyListeners();
      notifyListeners();
    }
  }

  void removeScript(int index) {
    if (_currentTab != null && index >= 0 && index < scripts.length) {
      _currentTab!.scripts.removeAt(index);
      _browserProvider?.notifyListeners();
      notifyListeners();
    }
  }

  void toggleScriptEnabled(int index, bool value) {
    if (_currentTab != null && index >= 0 && index < scripts.length) {
      _currentTab!.scripts[index].isEnabled = value;
      _browserProvider?.notifyListeners();
      notifyListeners();
    }
  }

  void updateScript(int index, Script script) {
    if (_currentTab != null && index >= 0 && index < scripts.length) {
      _currentTab!.scripts[index] = script;
      _browserProvider?.notifyListeners();
      notifyListeners();
    }
  }

  // Execution Control
  Future<void> startExecution(WebViewController controller) async {
    if (_currentRunner != null) {
      await _currentRunner!.start(_waitForPageLoadCallback);
    }
  }

  void stopExecution() {
    _currentRunner?.stop();
  }

  void pauseExecution() {
    _currentRunner?.pause();
  }

  void resumeExecution() {
    _currentRunner?.resume();
  }

  // Import/Export
  String exportScript() {
    if (_currentTab == null) return '[]';

    final List<Map<String, dynamic>> jsonList = [];

    // Add global settings
    jsonList.add({
      '脚本类型': '全局设置',
      '执行延迟': executionDelay ~/ delayTimeUnit.multiplier,
      '循环次数': originalLoopCount,
    });

    for (var script in scripts) {
      if (script.isEnabled) {
        jsonList.add(script.toUserMap());
      }
    }

    return json.encode(jsonList);
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
          final unitLabel = item['时间单位'] as String? ?? '毫秒';
          final unit = TimeUnit.values.firstWhere(
            (u) => u.label == unitLabel,
            orElse: () => TimeUnit.milliseconds,
          );

          setExecutionDelay(delay * unit.multiplier);
          setDelayTimeUnit(unit);

          if (item.containsKey('循环次数')) {
            setLoopCount(item['循环次数'] as int);
          }
        } else {
          try {
            _currentTab!.scripts.add(Script.fromUserMap(item));
          } catch (e) {
            debugPrint('Parse script item error: $e');
          }
        }
      }
      _browserProvider?.notifyListeners();
      notifyListeners();
    } catch (e) {
      debugPrint('Import script error: $e');
      // Fallback legacy
      _importScriptLegacy(content);
    }
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
            final delay = script.params['执行延迟'] as int;
            final unitLabel = script.params['时间单位'] as String;
            final loop = script.params['循环次数'] as int;

            final unit = TimeUnit.values.firstWhere(
              (u) => u.label == unitLabel,
              orElse: () => TimeUnit.milliseconds,
            );

            setExecutionDelay(delay * unit.multiplier);
            setDelayTimeUnit(unit);
            setLoopCount(loop);
          } else {
            _currentTab!.scripts.add(script);
          }
        } catch (e) {
          debugPrint('Legacy parse error: $e');
        }
      }
      _browserProvider?.notifyListeners();
      notifyListeners();
    } catch (e) {
      debugPrint('Legacy import error: $e');
    }
  }

  // Recording Stream & Logic
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
        addScript(Script(
          type: '点击图片',
          params: {},
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

  static const String recordingJs = '''
    (function() {
      if (window._auokRecorderInjected) return;
      window._auokRecorderInjected = true;

      document.addEventListener('click', function(e) {
        let target = e.target;
        
        if (target.nodeType === 3) {
          target = target.parentElement;
        }
        
        if (!target) return;

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
