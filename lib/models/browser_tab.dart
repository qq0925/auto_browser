import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'script.dart';
import 'dart:async';

class BrowserTab {
  final String id;
  InAppWebViewController? controller;
  String title; // 网页标题
  String url; // 网页URL
  bool isLoading; // 加载状态
  bool isExecutingScript; // 是否正在执行脚本
  bool isPaused = false; // 是否处于暂停状态
  int currentScriptIndex = 0; // 当前执行的脚本索引
  int successCount = 0; // 成功执行的脚本计数
  int failureCount = 0; // 失败执行的脚本计数
  int remainingLoopCount = 1; // 剩余循环次数
  List<Script> scripts = []; // 添加每个标签页自己的脚本列表
  double progress; // 网页加载进度
  String? scriptFilePath; // 脚本的物理文件路径，null表示未保存
  bool canGoBack = false;
  bool canGoForward = false;
  String? customName; // 自定义窗口名称
  String? customUserAgent; // 自定义UA

  // Call Stack for Subroutines
  List<ExecutionState> executionStack = [];

  // Auto Refresh
  Timer? _autoRefreshTimer;
  bool isAutoRefreshActive = false;
  int autoRefreshInterval = 0; // in seconds
  int autoRefreshCount = 0; // 0 means infinite
  int _currentRefreshCount = 0;

  BrowserTab({
    required this.id,
    this.controller,
    this.title = '新标签页',
    this.url = 'about:blank',
    this.isLoading = false,
    this.isExecutingScript = false,
    this.isPaused = false,
    this.progress = 0.0,
    this.customName,
    this.customUserAgent,
  });

  void setController(InAppWebViewController newController) {
    controller = newController;
  }

  void startAutoRefresh(int intervalSeconds, int count) {
    stopAutoRefresh();
    autoRefreshInterval = intervalSeconds;
    autoRefreshCount = count;
    _currentRefreshCount = 0;
    isAutoRefreshActive = true;

    _autoRefreshTimer =
        Timer.periodic(Duration(seconds: intervalSeconds), (timer) {
      if (count > 0 && _currentRefreshCount >= count) {
        stopAutoRefresh();
        return;
      }
      controller?.reload();
      _currentRefreshCount++;
    });
  }

  void stopAutoRefresh() {
    _autoRefreshTimer?.cancel();
    _autoRefreshTimer = null;
    isAutoRefreshActive = false;
  }
}

class ExecutionState {
  final List<Script> scripts;
  final int currentScriptIndex;
  final int remainingLoopCount;
  final String? scriptFilePath;

  ExecutionState({
    required this.scripts,
    required this.currentScriptIndex,
    required this.remainingLoopCount,
    this.scriptFilePath,
  });
}
