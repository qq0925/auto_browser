import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import '../models/script.dart';
import '../services/script_executor.dart';
import 'dart:convert';

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

  void setExecutionDelay(int delay) {
    _executionDelay = delay;
    notifyListeners();
  }

  void setDelayTimeUnit(TimeUnit unit) {
    _delayTimeUnit = unit;
    notifyListeners();
  }

  void setLoopCount(int count) {
    _originalLoopCount = count;
    _remainingLoopCount = count;
    notifyListeners();
  }

  void startRecording() {
    _isRecording = true;
    notifyListeners();
  }

  void stopRecording() {
    _isRecording = false;
    notifyListeners();
  }

  void clearScripts() {
    _scripts.clear();
    notifyListeners();
  }

  void addScript(Script script) {
    _scripts.add(script);
    notifyListeners();
  }

  void removeScript(int index) {
    if (index >= 0 && index < _scripts.length) {
      _scripts.removeAt(index);
      notifyListeners();
    }
  }

  void toggleScriptEnabled(int index, bool value) {
    if (index >= 0 && index < _scripts.length) {
      _scripts[index].isEnabled = value;
      notifyListeners();
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
          params: {'点击文字': content},
          isEnabled: true,
        ));
        break;
      case '输入框提交':
        try {
          final data = json.decode(content) as Map<String, dynamic>;
          addScript(Script(
            type: type,
            params: data,
            isEnabled: true,
          ));
        } catch (e) {
          debugPrint('Parse input data error: $e');
        }
        break;
    }
  }

  Future<void> startExecution(WebViewController controller) async {
    if (_scripts.isEmpty) return;

    _isExecuting = true;
    _isPaused = false;
    _currentScriptIndex = 0;
    _remainingLoopCount = _originalLoopCount;
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
          await _executor.execute(controller, script,
              executionDelay: _executionDelay);
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
    final List<String> lines = [];

    final globalScript = Script(
      type: "全局变量",
      params: {
        '执行延迟': _executionDelay ~/ _delayTimeUnit.multiplier,
        '时间单位': _delayTimeUnit.label,
        '循环次数': _originalLoopCount,
      },
      isEnabled: true,
    );
    lines.add(globalScript.toJson());

    for (var script in _scripts) {
      if (script.isEnabled) {
        lines.add(script.toJson());
      }
    }

    return lines.join('\n');
  }

  void importScript(String content) {
    try {
      final lines = content.split('\n');
      _scripts.clear();

      for (var line in lines) {
        if (line.trim().isEmpty) continue;

        try {
          final script = Script.fromJson(line);
          if (script.type == '全局变量') {
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
          debugPrint('Parse script line error: $e');
        }
      }
      notifyListeners();
    } catch (e) {
      debugPrint('Import script error: $e');
    }
  }
}
