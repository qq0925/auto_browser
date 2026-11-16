import 'dart:convert';

import 'package:auto_browser/models/browser_tab.dart';
import 'package:auto_browser/models/script.dart';
import 'package:auto_browser/providers/script_provider.dart';
import 'package:auto_browser/services/script_executor.dart';
import 'package:auto_browser/widgets/global_settings_dialog.dart';
import 'package:auto_browser/widgets/right_script_panel.dart';
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 高速性能基准与惰性探针验证用的轻量模拟 WebView 控制器
class _BenchmarkWebViewController implements InAppWebViewController {
  final List<String> evaluatedSources = [];
  bool helpersInstalled = false;
  bool egretInjected = false;
  bool simulateCanvasPage = false;
  bool nextIsNavTrigger = true;
  int domLoadingRemaining = 0;

  @override
  Future<dynamic> evaluateJavascript({
    required String source,
    ContentWorld? contentWorld,
  }) async {
    evaluatedSources.add(source);

    // 模拟 AT_DOCUMENT_END 预注入后的快速调用
    if (source.startsWith('window.__auok_helpers_v===')) {
      if (!helpersInstalled) {
        return '__NEED_INIT__';
      }
      if (domLoadingRemaining > 0) {
        domLoadingRemaining--;
        return jsonEncode({
          'success': false,
          'reason': 'dom_loading',
          'isNavTrigger': false,
        });
      }
      if (simulateCanvasPage && !egretInjected) {
        return jsonEncode({
          'success': false,
          'reason': 'need_egret_probe',
          'isNavTrigger': false,
        });
      }
      return jsonEncode({
        'success': true,
        'isNavTrigger': nextIsNavTrigger,
        'navMark': 'nav_bench',
        'preUrl': 'https://bench.local/p1',
      });
    }

    if (source.contains('function _auokFindEgretStage')) {
      egretInjected = true;
      return true;
    }

    if (source.contains('window._auokExecuteClick = function')) {
      helpersInstalled = true;
      return jsonEncode({
        'success': true,
        'isNavTrigger': true,
        'navMark': 'nav_bench',
        'preUrl': 'https://bench.local/p1',
      });
    }

    return null;
  }

  @override
  Future<bool> isLoading() async => false;

  @override
  Future<WebUri?> getUrl() async => WebUri('https://bench.local/p2');

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('高亮光圈移除、白鹭惰性探测与 0ms 点击速度基准测试', () {
    test('已彻底移除所有脉冲光圈 DOM 与 Egret 强制随页捆绑体积大幅下降', () {
      final executor = ScriptExecutor();
      final installJs = ScriptExecutor.clickHelpersInstallJs;
      final clickJs = executor.buildClickScriptLogic({'点击文本': '下一页'});
      final formJs = executor.buildFormSubmitScriptLogic({
        '提交按钮文字': '提交',
        '表单数据': {'user': 'tester'},
      });

      // 1. 不再包含任何高亮光圈逻辑
      expect(installJs.contains('_auokHighlight'), false);
      expect(installJs.contains('_auok_tap_indicator'), false);
      expect(clickJs.contains('_auokHighlight'), false);
      expect(formJs.contains('_auokHighlight'), false);
      expect(ScriptExecutor.egretCanvasProbeJs.contains('_auok_tap_indicator'),
          false);

      // 2. 默认点击注入不再内联 400+ 行白鹭探针源码（体积由 ~36.8KB 降至 ~21.3KB，已剥离 ~15.4KB 探针）
      expect(installJs.contains('function _auokFindEgretStage'), false);
      expect(installJs.contains('_auokHasCanvasGameCandidate'), true);
      expect(installJs.length, lessThan(25000));
      // ignore: avoid_print
      print(
          '[Benchmark] 预注入脚本体积: ${installJs.length}B（已剥离 ${ScriptExecutor.egretCanvasProbeJs.length}B 白鹭探针）');
    });

    test('标签页自动探测白鹭 Canvas：普通页 0 注入，Canvas 页惰性注入一次并触发回调', () async {
      final executor = ScriptExecutor();
      final controller = _BenchmarkWebViewController()
        ..helpersInstalled = true
        ..simulateCanvasPage = true;
      final tab = BrowserTab(id: 'egret_auto_tab');

      expect(tab.isEgretGame, false);

      final ok = await executor.execute(
        controller,
        Script(type: '点击文字', params: {'点击文本': '开始游戏'}),
        executionDelay: 0,
        getTabLoadState: () => (
          isLoading: tab.isLoading,
          startEpoch: tab.loadStartEpoch,
          stopEpoch: tab.loadStopEpoch,
        ),
        isEgretGameTab: () => tab.isEgretGame,
        onEgretDetected: () {
          tab.isEgretGame = true;
        },
      );

      expect(ok, true);
      expect(tab.isEgretGame, true);
      expect(controller.egretInjected, true);

      // 切到新页面后 markLoadStarted 自动复位，等待新页面按需识别
      tab.markLoadStarted();
      expect(tab.isEgretGame, false);
    });

    test('0ms 点击 <a> 链接 200 次闭环吞吐基准（含事件驱动 waitForPageLoad 唤醒）', () async {
      final executor = ScriptExecutor();
      final controller = _BenchmarkWebViewController()
        ..helpersInstalled = true;
      final tab = BrowserTab(id: 'speed_tab');
      final script = Script(type: '点击文字', params: {'点击文本': '下一页'});

      const iterations = 200;
      final sw = Stopwatch()..start();

      for (int i = 0; i < iterations; i++) {
        final ok = await executor.execute(
          controller,
          script,
          executionDelay: 0,
          getTabLoadState: () => (
            isLoading: tab.isLoading,
            startEpoch: tab.loadStartEpoch,
            stopEpoch: tab.loadStopEpoch,
          ),
          waitForPageLoad: ({
            preNavToken,
            preUrl,
            preLoadStartEpoch,
            preLoadStopEpoch,
            probeWindowMs = 80,
          }) async {
            // 模拟真实 WebView onLoadStart -> onLoadStop 异步完成事件唤醒
            tab.markLoadStarted();
            tab.markLoadStopped();
          },
        );
        expect(ok, true);
      }

      sw.stop();
      final totalMs = sw.elapsedMilliseconds;
      final avgUs = (sw.elapsedMicroseconds / iterations).toStringAsFixed(1);
      // 模拟零延迟框架调度开销检查：200 次完整周期（不含真实网络 RTT）应在 1 秒内完成
      expect(totalMs, lessThan(1000));
      // 验证单次预注入点击仅发 1 次 evaluateJavascript，无 __NEED_INIT__ 二次往返
      expect(controller.evaluatedSources.length, iterations);
      // 输出实测帧时用于诊断对比
      // ignore: avoid_print
      print(
          '[Benchmark] 200次点击调度总耗时: ${totalMs}ms (单次框架开销约 ${avgUs}us, IPC数: ${controller.evaluatedSources.length})');
    });

    test('极速/稳定模式与 dom_loading 防误跳过校验', () async {
      final executor = ScriptExecutor();
      final controller = _BenchmarkWebViewController()
        ..helpersInstalled = true
        ..nextIsNavTrigger = false;
      final tab = BrowserTab(id: 'mode_tab')..isLoading = true;
      int waitCalls = 0;

      // 1. 极速模式（非导航点击）：即使图片仍在加载 (tab.isLoading == true)，步前不阻塞
      final fastNonNavOk = await executor.execute(
        controller,
        Script(type: '点击文字', params: {'点击文本': '下一页'}),
        executionDelay: 0,
        fastMode: true,
        getTabLoadState: () => (
          isLoading: tab.isLoading,
          startEpoch: tab.loadStartEpoch,
          stopEpoch: tab.loadStopEpoch,
        ),
        waitForPageLoad: ({
          preNavToken,
          preUrl,
          preLoadStartEpoch,
          preLoadStopEpoch,
          probeWindowMs = 80,
        }) async {
          waitCalls++;
        },
      );
      expect(fastNonNavOk, true);
      expect(waitCalls, 0);

      // 2. 极速模式遭遇切页过渡期 dom_loading：即使未找到时跳过=true 也自动微等待 body 解析，不误报未找到目标
      controller
        ..nextIsNavTrigger = true
        ..domLoadingRemaining = 2;
      final statuses = <ScriptStatus>[];
      final fastDomRecoveryOk = await executor.execute(
        controller,
        Script(type: '点击文字', params: {'点击文本': '下一页', '未找到时跳过': true}),
        executionDelay: 0,
        fastMode: true,
        onStatusChanged: (s, m, p) => statuses.add(s),
        getTabLoadState: () => (
          isLoading: tab.isLoading,
          startEpoch: tab.loadStartEpoch,
          stopEpoch: tab.loadStopEpoch,
        ),
        waitForPageLoad: ({
          preNavToken,
          preUrl,
          preLoadStartEpoch,
          preLoadStopEpoch,
          probeWindowMs = 80,
        }) async {
          waitCalls++;
        },
      );
      expect(fastDomRecoveryOk, true);
      expect(statuses.contains(ScriptStatus.skipped), false);
      expect(waitCalls, 1);

      // 3. 稳定模式：点击 <a> 前后均触发页面等待
      waitCalls = 0;
      final stableOk = await executor.execute(
        controller,
        Script(type: '点击文字', params: {'点击文本': '下一页'}),
        executionDelay: 0,
        fastMode: false,
        getTabLoadState: () => (
          isLoading: tab.isLoading,
          startEpoch: tab.loadStartEpoch,
          stopEpoch: tab.loadStopEpoch,
        ),
        waitForPageLoad: ({
          preNavToken,
          preUrl,
          preLoadStartEpoch,
          preLoadStopEpoch,
          probeWindowMs = 80,
        }) async {
          waitCalls++;
          tab.isLoading = false;
        },
      );
      expect(stableOk, true);
      expect(waitCalls, greaterThanOrEqualTo(2));
    });

    testWidgets('全局设置模式默认极速，支持在弹窗切换为稳定并在面板/状态简报中展示', (tester) async {
      SharedPreferences.setMockInitialValues({});
      final scriptProvider = ScriptProvider();
      final tab = BrowserTab(id: 'mode_ui_tab');
      tab.scripts.add(Script(type: '点击文字', params: {'点击文本': '继续'}));
      scriptProvider.setCurrentTab(tab);

      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 30));
      });

      expect(scriptProvider.executionMode, '极速');
      tab.isExecutingScript = true;
      expect(tab.executionStatusSummary, contains('模式:极速'));

      await tester.pumpWidget(
        ChangeNotifierProvider.value(
          value: scriptProvider,
          child: MaterialApp(
            home: Scaffold(
              body: SizedBox(
                width: 240,
                height: 600,
                child: Builder(
                  builder: (ctx) => RightScriptPanel(
                    onAddScript: () {},
                    onGlobalSettings: () {
                      showDialog(
                        context: ctx,
                        builder: (_) => const GlobalSettingsDialog(),
                      );
                    },
                    onExecute: () {},
                    onLoad: () {},
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // 右侧脚本面板显示当前模式为「极速」
      expect(find.text('模式: '), findsOneWidget);
      expect(find.text('极速'), findsOneWidget);

      // 点击全局模式栏打开 GlobalSettingsDialog 并切换为「稳定」
      await tester.tap(find.text('极速'));
      await tester.pumpAndSettle();

      expect(find.text('运行模式'), findsOneWidget);
      await tester.tap(find.text('稳定'));
      await tester.pump();
      await tester.tap(find.text('确定'));
      await tester.pumpAndSettle();

      expect(scriptProvider.executionMode, '稳定');
      expect(tab.executionMode, '稳定');
      expect(tab.executionStatusSummary, contains('模式:稳定'));
      expect(find.text('稳定'), findsOneWidget);

      // 导出与重新导入闭环保留「模式」字段
      final exported = scriptProvider.exportScript();
      expect(exported, contains('"模式":"稳定"'));
      scriptProvider.setExecutionMode('极速');
      expect(scriptProvider.executionMode, '极速');
      scriptProvider.importScript(exported);
      expect(scriptProvider.executionMode, '稳定');
    });
  });
}
