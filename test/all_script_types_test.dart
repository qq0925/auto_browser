import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:auto_browser/models/browser_tab.dart';
import 'package:auto_browser/models/script.dart';
import 'package:auto_browser/providers/browser_provider.dart';
import 'package:auto_browser/providers/script_provider.dart';
import 'package:auto_browser/services/script_executor.dart';
import 'package:auto_browser/widgets/add_script_dialog.dart';
import 'package:auto_browser/widgets/right_script_panel.dart';

/// 轻量级模拟 WebView 控制器：捕获所有 JS 注入与页面导航指令
class _FakeWebViewController implements InAppWebViewController {
  final List<String> evaluatedSources = [];
  final List<String> loadedUrls = [];
  int reloadCount = 0;
  int goBackCount = 0;
  int goForwardCount = 0;
  bool canGoBackValue = true;
  bool canGoForwardValue = true;
  bool isLoadingValue = false;
  WebUri? currentUrl = WebUri('https://example.com/game');

  dynamic Function(String source)? onEvaluateJavascript;

  @override
  Future<dynamic> evaluateJavascript({
    required String source,
    ContentWorld? contentWorld,
  }) async {
    evaluatedSources.add(source);
    if (onEvaluateJavascript != null) {
      return onEvaluateJavascript!(source);
    }
    return null;
  }

  @override
  Future<void> loadUrl({
    required URLRequest urlRequest,
    WebUri? allowingReadAccessTo,
    Uri? iosAllowingReadAccessTo,
  }) async {
    loadedUrls.add(urlRequest.url?.toString() ?? '');
  }

  @override
  Future<void> reload() async {
    reloadCount++;
  }

  @override
  Future<bool> canGoBack() async => canGoBackValue;

  @override
  Future<void> goBack() async {
    goBackCount++;
  }

  @override
  Future<bool> canGoForward() async => canGoForwardValue;

  @override
  Future<void> goForward() async {
    goForwardCount++;
  }

  @override
  Future<WebUri?> getUrl() async => currentUrl;

  @override
  Future<bool> isLoading() async => isLoadingValue;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('全脚本类型与全部内设参数探索测试 (ScriptExecutor)', () {
    late ScriptExecutor executor;
    late _FakeWebViewController controller;

    setUp(() {
      executor = ScriptExecutor();
      controller = _FakeWebViewController();
    });

    test('公共基础能力：禁用状态、重复次数、动态变量插值与 window._auokVars 注入、执行延迟与前后置嵌套脚本', () async {
      // 1. 禁用脚本应直接跳过执行，不调用 controller
      final disabled = Script(
        type: '刷新网页',
        params: {},
        isEnabled: false,
      );
      expect(await executor.execute(controller, disabled), false);
      expect(controller.reloadCount, 0);

      // 2. 重复次数 + 前置脚本 + 后置脚本 + 动态变量插值
      final events = <String>[];
      controller.onEvaluateJavascript = (src) {
        if (src.contains('window._auokVars')) return null;
        if (src.contains('before_flag')) {
          events.add('before');
          return jsonEncode({'ok': true, 'result': 'b'});
        }
        if (src.contains('after_flag')) {
          events.add('after');
          return jsonEncode({'ok': true, 'result': 'a'});
        }
        return null;
      };

      final mainScript = Script(
        type: '进入网址',
        params: {
          '网址': 'https://site.test/item/\${itemId}?role=\$roleName',
          '重复次数': 2,
          '执行延迟': 0,
          '执行每个脚本前执行': {
            '脚本类型': '自定义JS',
            '代码': '/* before_flag */ return true;',
          },
          '执行每个脚本后执行': {
            '脚本类型': '自定义JS',
            '代码': '/* after_flag */ return true;',
          },
        },
      );

      final ok = await executor.execute(
        controller,
        mainScript,
        executionDelay: 0,
        variables: {'itemId': '8899', 'roleName': 'YanQing'},
      );

      expect(ok, true);
      expect(controller.loadedUrls, [
        'https://site.test/item/8899?role=YanQing',
        'https://site.test/item/8899?role=YanQing',
      ]);
      expect(events, ['before', 'after', 'before', 'after']);
      expect(
        controller.evaluatedSources.any((s) => s.contains('window._auokVars')),
        true,
      );
    });

    test('1. 点击文字：全部内设（留空全链、多词分号、完全匹配、正负/随机筛选、前后边界、出现文字前置、跳过与失败、导航等待）', () async {
      // A. JS 生成覆盖：留空、完全匹配 false/true、多词分隔、正负/随机筛选
      final jsEmpty = executor.buildClickScriptLogic({
        '点击文本': '',
        '完全匹配': true,
        '多个筛选': 0, // 随机
        '在此之后': '背包区',
        '在此之前': '底部导航',
        '出现文字': '可操作',
      }, navMark: 'nav_mark_1');

      expect(jsEmpty.contains('a[href], a[onclick]'), true);
      expect(jsEmpty.contains('_auokIsClickableElement'), true);
      expect(jsEmpty.contains('const selectionIndex = 0;'), true);
      expect(jsEmpty.contains('const exactMatch = true;'), true);
      expect(jsEmpty.contains('背包区'), true);
      expect(jsEmpty.contains('底部导航'), true);
      expect(jsEmpty.contains('可操作'), true);
      expect(jsEmpty.contains('nav_mark_1'), true);

      // B. 触发跨页导航时 waitForPageLoad 应被调用
      int waitLoadCalled = 0;
      String? passedNavMark;
      controller.onEvaluateJavascript = (src) {
        if (src.contains('window.__auok_helpers_v===')) return '__NEED_INIT__';
        return jsonEncode({
          'success': true,
          'isNavTrigger': true,
          'navMark': 'nav_test_abc',
          'preUrl': 'https://example.com/a',
        });
      };

      bool? actionExecutedFlag;
      final clickOk = await executor.execute(
        controller,
        Script(type: '点击文字', params: {'点击文本': '确认;确定；提交', '多个筛选': -1}),
        executionDelay: 0,
        waitForPageLoad: ({
          preNavToken,
          preUrl,
          preLoadStartEpoch,
          preLoadStopEpoch,
          probeWindowMs = 60,
        }) async {
          waitLoadCalled++;
          passedNavMark = preNavToken;
        },
        onActionExecuted: (did) => actionExecutedFlag = did,
      );
      expect(clickOk, true);
      expect(waitLoadCalled, 1);
      expect(passedNavMark, 'nav_test_abc');
      expect(actionExecutedFlag, true);

      // C. 未找到目标：未找到时跳过=true -> 返回 true 且发射 skipped 状态
      final skipEvents = <(ScriptStatus, String?)>[];
      controller.onEvaluateJavascript = (src) => jsonEncode({
            'success': false,
            'reason': 'trigger_not_met',
          });
      final skipOk = await executor.execute(
        controller,
        Script(type: '点击文字', params: {
          '出现文字': '前置按钮',
          '点击文本': '出征',
          '未找到时跳过': true,
          '目标等待': 0,
        }),
        executionDelay: 0,
        onStatusChanged: (s, m, p) => skipEvents.add((s, m)),
      );
      expect(skipOk, true);
      expect(
        skipEvents.any((e) =>
            e.$1 == ScriptStatus.skipped && (e.$2?.contains('前置条件未满足') ?? false)),
        true,
      );

      // D. 未找到目标：未找到时跳过=false -> 返回 false 且发射 failure 状态
      final failEvents = <(ScriptStatus, String?)>[];
      controller.onEvaluateJavascript = (src) => jsonEncode({'success': false});
      final failOk = await executor.execute(
        controller,
        Script(type: '点击文字', params: {
          '点击文本': '不存在按钮',
          '未找到时跳过': false,
          '超时时间': 20,
          '超时单位': 'ms',
        }),
        executionDelay: 0,
        onStatusChanged: (s, m, p) => failEvents.add((s, m)),
      );
      expect(failOk, false);
      expect(
        failEvents.any((e) =>
            e.$1 == ScriptStatus.failure && (e.$2?.contains('未找到目标') ?? false)),
        true,
      );
    });

    test('2. 输入框提交：全部内设（多表单筛选 0/正/负、Enter键提交、启用正则、输入空以当前值提交）', () async {
      // A. JS 逻辑验证：勾选【输入空以当前值提交】+ 表单部分留空
      final jsPartialEmpty = executor.buildFormSubmitScriptLogic({
        '提交按钮文字': 'Enter键提交',
        '多个筛选': -1,
        '启用正则': true,
        '输入空以当前值提交': true,
        '表单数据': {
          'code': '[0-9]{6}',
          'lower': '[a-z]{3}',
          'upper': '[A-Z]{2}',
          'mixed': 'ab[a-zA-Z]{2}[0-9]{3}',
          'keepField': '', // 空输入应走保留当前值分支
        },
      });
      expect(jsPartialEmpty.contains('const submitCurrentWhenEmpty = true;'), true);
      expect(jsPartialEmpty.contains('if (submitCurrentWhenEmpty && isEmptyValue)'), true);
      expect(jsPartialEmpty.contains('findCurrentTarget'), true);
      expect(jsPartialEmpty.contains('const multipleSelection = -1;'), true);
      expect(jsPartialEmpty.contains("buttonText === 'Enter键提交'"), true);

      // 验证正则占位已经被成功替换，且 keepField 保留为空字符串
      final match = RegExp(r'const formData = (\{.*?\});').firstMatch(jsPartialEmpty);
      expect(match, isNotNull);
      final decodedForm = jsonDecode(match!.group(1)!) as Map<String, dynamic>;
      expect(RegExp(r'^\d{6}$').hasMatch(decodedForm['code']), true);
      expect(RegExp(r'^[a-z]{3}$').hasMatch(decodedForm['lower']), true);
      expect(RegExp(r'^[A-Z]{2}$').hasMatch(decodedForm['upper']), true);
      expect(RegExp(r'^ab[a-zA-Z]{2}\d{3}$').hasMatch(decodedForm['mixed']), true);
      expect(decodedForm['keepField'], '');

      // B. 完全未添加字段时：未勾选【输入空以当前值提交】直接失败；勾选时允许提交
      expect(
        await executor.execute(
          controller,
          Script(type: '输入框提交', params: {
            '提交按钮文字': '确定',
            '输入空以当前值提交': false,
          }),
          executionDelay: 0,
        ),
        false,
      );

      controller.onEvaluateJavascript = (_) => 'true';
      final submitCurrentOnly = await executor.execute(
        controller,
        Script(type: '输入框提交', params: {
          '提交按钮文字': '确定',
          '多个筛选': 0,
          '输入空以当前值提交': true,
        }),
        executionDelay: 0,
      );
      expect(submitCurrentOnly, true);
      expect(
        controller.evaluatedSources.last.contains('entries.length === 0'),
        true,
      );
    });

    test('3. 进入网址：正常 URL / 省略协议自动补 http / 特殊协议保留 / 空网址失败', () async {
      expect(
        await executor.execute(
          controller,
          Script(type: '进入网址', params: {'网址': 'game.example.com/index'}),
          executionDelay: 0,
        ),
        true,
      );
      expect(controller.loadedUrls.last, 'http://game.example.com/index');

      expect(
        await executor.execute(
          controller,
          Script(type: '进入网址', params: {'网址': 'https://secure.example.com'}),
          executionDelay: 0,
        ),
        true,
      );
      expect(controller.loadedUrls.last, 'https://secure.example.com');

      expect(
        await executor.execute(
          controller,
          Script(type: '进入网址', params: {'网址': 'about:blank'}),
          executionDelay: 0,
        ),
        true,
      );
      expect(controller.loadedUrls.last, 'about:blank');

      expect(
        await executor.execute(
          controller,
          Script(type: '进入网址', params: {'网址': ''}),
          executionDelay: 0,
        ),
        false,
      );
    });

    test('4. 间隔时间：0秒立即通过 与 倒计时结束调用子脚本集', () async {
      expect(
        await executor.execute(
          controller,
          Script(type: '间隔时间', params: {
            '时间间隔-小时': 0,
            '时间间隔-分钟': 0,
            '时间间隔-秒': 0,
          }),
          executionDelay: 0,
        ),
        true,
      );

      final statuses = <ScriptStatus>[];
      String? subPath;
      final ok = await executor.execute(
        controller,
        Script(type: '间隔时间', params: {
          '时间间隔-秒': 1,
          '间隔时间后执行脚本': 'sub/next_step.json',
        }),
        executionDelay: 0,
        onStatusChanged: (s, m, p) {
          statuses.add(s);
          if (s == ScriptStatus.callSubroutine) subPath = m;
        },
      );
      expect(ok, true);
      expect(statuses.contains(ScriptStatus.waiting), true);
      expect(subPath, 'sub/next_step.json');
    });

    test('5. 自定义JS：空代码、正常返回值、返回 false 判定失败、异常捕获', () async {
      expect(
        await executor.execute(
          controller,
          Script(type: '自定义JS', params: {'代码': ''}),
          executionDelay: 0,
        ),
        true,
      );

      final jsOkEvents = <(ScriptStatus, String?)>[];
      controller.onEvaluateJavascript = (src) {
        if (src.contains('window._auokVars')) return null;
        return jsonEncode({'ok': true, 'result': 'done_42'});
      };
      expect(
        await executor.execute(
          controller,
          Script(type: '自定义JS', params: {'代码': 'return "done_42";'}),
          executionDelay: 0,
          onStatusChanged: (s, m, p) => jsOkEvents.add((s, m)),
        ),
        true,
      );
      expect(
        jsOkEvents.any(
            (e) => e.$1 == ScriptStatus.success && e.$2 == 'JS执行完成: done_42'),
        true,
      );

      final jsFailEvents = <(ScriptStatus, String?)>[];
      controller.onEvaluateJavascript = (_) => jsonEncode({
            'ok': false,
            'message': '脚本执行结果为 false',
          });
      expect(
        await executor.execute(
          controller,
          Script(type: '自定义JS', params: {
            'js内容': 'return false;',
            '超时时间': 0,
          }),
          executionDelay: 0,
          onStatusChanged: (s, m, p) => jsFailEvents.add((s, m)),
        ),
        false,
      );
      expect(
        jsFailEvents.any((e) =>
            e.$1 == ScriptStatus.failure &&
            (e.$2?.contains('JS执行未成功') ?? false)),
        true,
      );
    });

    test('6. 点击图片：关键词/筛选/边界、空地址跳过与失败、命中导航与未找到跳过', () async {
      // 空地址跳过
      ScriptStatus? st;
      expect(
        await executor.execute(
          controller,
          Script(type: '点击图片', params: {'图片地址': '', '未找到时跳过': true}),
          executionDelay: 0,
          onStatusChanged: (s, m, p) => st = s,
        ),
        true,
      );
      expect(st, ScriptStatus.skipped);

      // 空地址关闭跳过 -> 失败
      expect(
        await executor.execute(
          controller,
          Script(type: '点击图片', params: {'图片地址': '', '未找到时跳过': false}),
          executionDelay: 0,
        ),
        false,
      );

      // 命中图片触发导航
      bool waitedNav = false;
      controller.onEvaluateJavascript = (_) => jsonEncode({
            'success': true,
            'isNavTrigger': true,
            'navMark': 'img_nav_1',
          });
      expect(
        await executor.execute(
          controller,
          Script(type: '点击图片', params: {
            '图片地址': 'attack.png',
            '多个筛选': -1,
            '在此之后': '战斗区',
            '在此之前': '状态栏',
          }),
          executionDelay: 0,
          waitForPageLoad: ({
            preNavToken,
            preUrl,
            preLoadStartEpoch,
            preLoadStopEpoch,
            probeWindowMs = 60,
          }) async {
            waitedNav = true;
          },
        ),
        true,
      );
      expect(waitedNav, true);
      expect(
        controller.evaluatedSources.last.contains('attack.png'),
        true,
      );
    });

    test('7-9. 刷新网页 / 网页后退 / 网页前进（含不可后退/前进边界）', () async {
      expect(
        await executor.execute(controller, Script(type: '刷新网页', params: {}),
            executionDelay: 0),
        true,
      );
      expect(controller.reloadCount, 1);

      controller.canGoBackValue = true;
      expect(
        await executor.execute(controller, Script(type: '网页后退', params: {}),
            executionDelay: 0),
        true,
      );
      expect(controller.goBackCount, 1);

      controller.canGoBackValue = false;
      expect(
        await executor.execute(controller, Script(type: '网页后退', params: {}),
            executionDelay: 0),
        true,
      );
      expect(controller.goBackCount, 1); // 未触发多余 goBack

      controller.canGoForwardValue = true;
      expect(
        await executor.execute(controller, Script(type: '网页前进', params: {}),
            executionDelay: 0),
        true,
      );
      expect(controller.goForwardCount, 1);

      controller.canGoForwardValue = false;
      expect(
        await executor.execute(controller, Script(type: '网页前进', params: {}),
            executionDelay: 0),
        true,
      );
      expect(controller.goForwardCount, 1);
    });

    test('10-15. 控制流程类：脚本停止 / 脚本暂停 / 脚本替换 / 执行本地脚本集 / 控制脚本开关 / 通知栏提醒 / 延时脚本', () async {
      // 10. 脚本停止 & 11. 脚本暂停 (无需 controller 也可运行)
      ScriptStatus? st;
      String? msg;
      expect(
        await executor.execute(
          null,
          Script(type: '脚本停止', params: {'执行完成提醒': true}),
          executionDelay: 0,
          onStatusChanged: (s, m, p) {
            st = s;
            msg = m;
          },
        ),
        true,
      );
      expect(st, ScriptStatus.stopped);

      expect(
        await executor.execute(
          null,
          Script(type: '脚本暂停', params: {'执行完成提醒': false}),
          executionDelay: 0,
          onStatusChanged: (s, m, p) => st = s,
        ),
        true,
      );
      expect(st, ScriptStatus.paused);

      // 12. 脚本替换（含缺失路径失败分支）
      expect(
        await executor.execute(
          null,
          Script(type: '脚本替换', params: {}, targetScriptPath: 'sets/new.json'),
          executionDelay: 0,
          onStatusChanged: (s, m, p) {
            st = s;
            msg = m;
          },
        ),
        true,
      );
      expect(st, ScriptStatus.replaced);
      expect(msg, 'sets/new.json');
      expect(
        await executor.execute(null, Script(type: '脚本替换', params: {}),
            executionDelay: 0),
        false,
      );

      // 13. 执行本地脚本集（含缺失路径失败分支）
      expect(
        await executor.execute(
          null,
          Script(
              type: '执行本地脚本集',
              params: {},
              targetScriptPath: 'sets/sub.json'),
          executionDelay: 0,
          onStatusChanged: (s, m, p) {
            st = s;
            msg = m;
          },
        ),
        true,
      );
      expect(st, ScriptStatus.callSubroutine);
      expect(msg, 'sets/sub.json');
      expect(
        await executor.execute(null, Script(type: '执行本地脚本集', params: {}),
            executionDelay: 0),
        false,
      );

      // 14. 控制脚本开关：禁用 / 启用 / 反相 + 多分隔符 + 越界忽略 + 缺参失败
      final targetList = [
        Script(type: '点击文字', params: {}, isEnabled: true),
        Script(type: '点击文字', params: {}, isEnabled: false),
        Script(type: '点击文字', params: {}, isEnabled: true),
      ];
      expect(
        await executor.execute(
          null,
          Script(type: '控制脚本开关', params: {'脚本序号': '1, 2，99', '开关动作': '禁用'}),
          scripts: targetList,
          executionDelay: 0,
        ),
        true,
      );
      expect(targetList.map((e) => e.isEnabled).toList(), [false, false, true]);

      expect(
        await executor.execute(
          null,
          Script(type: '控制脚本开关', params: {'脚本序号': '1;2', '开关动作': '启用'}),
          scripts: targetList,
          executionDelay: 0,
        ),
        true,
      );
      expect(targetList.map((e) => e.isEnabled).toList(), [true, true, true]);

      expect(
        await executor.execute(
          null,
          Script(type: '控制脚本开关', params: {'脚本序号': '2；3', '开关动作': '反相'}),
          scripts: targetList,
          executionDelay: 0,
        ),
        true,
      );
      expect(targetList.map((e) => e.isEnabled).toList(), [true, false, false]);

      expect(
        await executor.execute(
          null,
          Script(type: '控制脚本开关', params: {}),
          scripts: targetList,
          executionDelay: 0,
        ),
        false,
      );

      // 15. 通知栏提醒 & 延时脚本
      final notifyEvents = <(ScriptStatus, String?)>[];
      expect(
        await executor.execute(
          null,
          Script(type: '通知栏提醒', params: {'提醒内容': '体力已满！'}),
          executionDelay: 0,
          onStatusChanged: (s, m, p) => notifyEvents.add((s, m)),
        ),
        true,
      );
      expect(
        notifyEvents.any(
            (e) => e.$1 == ScriptStatus.notification && e.$2 == '体力已满！'),
        true,
      );
      expect(
        await executor.execute(null, Script(type: '通知栏提醒', params: {}),
            executionDelay: 0),
        false,
      );

      expect(
        await executor.execute(
          null,
          Script(type: '延时脚本', params: {'执行延迟': 10}),
          executionDelay: 0,
        ),
        true,
      );
    });

    test('16. 逻辑脚本-出现文字：出现/未出现分支、前后边界、空参数失败与内联子弹窗分支', () async {
      String? calledPath;
      controller.onEvaluateJavascript = (_) => 'true';
      expect(
        await executor.execute(
          controller,
          Script(type: '逻辑脚本-出现文字', params: {
            '出现文字': '胜利',
            '在此之后': '战斗结果',
            '在此之前': '返回首页',
            '出现时执行': 'win.json',
            '未出现时执行': 'lose.json',
          }),
          executionDelay: 0,
          onStatusChanged: (s, m, p) {
            if (s == ScriptStatus.callSubroutine) calledPath = m;
          },
        ),
        true,
      );
      expect(calledPath, 'win.json');

      controller.onEvaluateJavascript = (_) => 'false';
      expect(
        await executor.execute(
          controller,
          Script(type: '逻辑脚本-出现文字', params: {
            '出现文字': '胜利',
            '出现时执行': 'win.json',
            '未出现时执行': 'lose.json',
          }),
          executionDelay: 0,
          onStatusChanged: (s, m, p) {
            if (s == ScriptStatus.callSubroutine) calledPath = m;
          },
        ),
        true,
      );
      expect(calledPath, 'lose.json');

      // 内联子脚本分支：支持变量插值，且跳转流控状态不被后续 success 覆盖
      String? executedChildScript;
      final emittedStatuses = <ScriptStatus>[];
      controller.onEvaluateJavascript = (src) {
        if (src.contains('searchAreaText') || src.contains('bodyText.includes')) {
          return 'true';
        }
        executedChildScript = src;
        return 'clicked_no_nav';
      };
      final inlineOk = await executor.execute(
        controller,
        Script(type: '逻辑脚本-出现文字', params: {
          '出现文字': '继续',
          '出现时执行': {
            'type': '点击文字',
            '点击文本': '\$nextBtn',
          },
        }),
        executionDelay: 0,
        variables: {'nextBtn': '确认提交'},
        onStatusChanged: (s, m, p) => emittedStatuses.add(s),
      );
      expect(inlineOk, true);
      expect(executedChildScript, contains('确认提交'));
      expect(emittedStatuses.last, ScriptStatus.success);

      final jumpStatuses = <ScriptStatus>[];
      controller.onEvaluateJavascript = (_) => 'false';
      expect(
        await executor.execute(
          controller,
          Script(type: '逻辑脚本-出现文字', params: {
            '出现文字': '继续',
            '未出现时执行': {
              'type': '跳转脚本',
              '跳转的脚本序号': '3',
            },
          }),
          executionDelay: 0,
          onStatusChanged: (s, m, p) => jumpStatuses.add(s),
        ),
        true,
      );
      expect(jumpStatuses.last, ScriptStatus.jump);

      expect(
        await executor.execute(
          controller,
          Script(type: '逻辑脚本-出现文字', params: {'出现文字': ''}),
          executionDelay: 0,
        ),
        false,
      );
    });

    test('17. 逻辑脚本-时间对比：完整日期/时分秒/+相对偏移与内联子脚本分支', () async {
      // 1) 三种时间格式解析与 +HH:mm:ss 会话缓存校验
      final fixedNow = DateTime(2026, 5, 1, 10, 0, 0);
      expect(
        executor.resolveComparisonTargetTime('2013-01-01 09:30:58',
            now: fixedNow),
        DateTime(2013, 1, 1, 9, 30, 58),
      );
      expect(
        executor.resolveComparisonTargetTime('09:30:58', now: fixedNow),
        DateTime(2026, 5, 1, 9, 30, 58),
      );
      final cacheScript =
          Script(type: '逻辑脚本-时间对比', params: {'目标值': '+02:00:00'});
      expect(
        executor.resolveComparisonTargetTime('+02:00:00',
            cacheOwner: cacheScript, now: fixedNow),
        DateTime(2026, 5, 1, 12, 0, 0),
      );
      // 同一会话内再次解析应命中缓存，不随当前时间继续向后顺延
      expect(
        executor.resolveComparisonTargetTime('+02:00:00',
            cacheOwner: cacheScript,
            now: fixedNow.add(const Duration(minutes: 45))),
        DateTime(2026, 5, 1, 12, 0, 0),
      );
      // 非法日期（2月30日、25点）应被拦截
      expect(
        executor.resolveComparisonTargetTime('2025-02-30 10:00:00',
            now: fixedNow),
        isNull,
      );
      expect(
        executor.resolveComparisonTargetTime('25:00:00', now: fixedNow),
        isNull,
      );

      String? calledPath;
      final futureTime = DateTime.now().add(const Duration(minutes: 2));
      final pastTime = DateTime.now().subtract(const Duration(minutes: 2));
      String fmt(DateTime dt) =>
          '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}:${dt.second.toString().padLeft(2, '0')}';

      // 若恰好跨午夜，用安全分支避免临界抖动
      if (pastTime.day == DateTime.now().day) {
        await executor.execute(
          controller,
          Script(type: '逻辑脚本-时间对比', params: {
            '目标值': fmt(pastTime),
            '出现时执行': 'after.json',
            '未出现时执行': 'before.json',
          }),
          executionDelay: 0,
          onStatusChanged: (s, m, p) {
            if (s == ScriptStatus.callSubroutine) calledPath = m;
          },
        );
        expect(calledPath, 'after.json');
      }

      if (futureTime.day == DateTime.now().day) {
        await executor.execute(
          controller,
          Script(type: '逻辑脚本-时间对比', params: {
            '目标值': fmt(futureTime),
            '出现时执行': 'after.json',
            '未出现时执行': 'before.json',
          }),
          executionDelay: 0,
          onStatusChanged: (s, m, p) {
            if (s == ScriptStatus.callSubroutine) calledPath = m;
          },
        );
        expect(calledPath, 'before.json');
      }

      // 2) 完整日期（历史时刻 -> 触发时间后内联子脚本）与 +02:00:00（未到 -> 触发时间前内联子脚本）
      String? loadedUrl;
      controller.onLoadUrl = (url) => loadedUrl = url;
      expect(
        await executor.execute(
          controller,
          Script(type: '逻辑脚本-时间对比', params: {
            '目标值': '2013-01-01 09:30:58',
            '出现时执行': {'type': '进入网址', '网址': 'https://after.example.com'},
          }),
          executionDelay: 0,
        ),
        true,
      );
      expect(loadedUrl, 'https://after.example.com');

      final relScript = Script(type: '逻辑脚本-时间对比', params: {
        '目标值': '+02:00:00',
        '未出现时执行': {'type': '进入网址', '网址': 'https://before.example.com'},
      });
      expect(
        await executor.execute(controller, relScript, executionDelay: 0),
        true,
      );
      expect(loadedUrl, 'https://before.example.com');
      expect(relScript.runtimeTargetTime, isNotNull);

      expect(
        await executor.execute(
          controller,
          Script(type: '逻辑脚本-时间对比', params: {'目标值': 'invalid'}),
          executionDelay: 0,
        ),
        false,
      );
    });

    test('18. 逻辑脚本-数值对比：5种对比方式 (>/< /=/ >=/ <=)、内联分支与异常边界', () async {
      final cases = [
        ('>', 150, '100', 'true.json'),
        ('>', 90, '100', 'false.json'),
        ('<', 50, '100', 'true.json'),
        ('=', 100.0, '100', 'true.json'),
        ('>=', 100, '100', 'true.json'),
        ('<=', 101, '100', 'false.json'),
      ];

      for (final (op, extracted, target, expectedBranch) in cases) {
        String? branch;
        controller.onEvaluateJavascript = (_) => extracted;
        final ok = await executor.execute(
          controller,
          Script(type: '逻辑脚本-数值对比', params: {
            '目标值': target,
            '对比方式': op,
            '多个筛选': -1,
            '在此之后': '当前血量',
            '在此之前': '经验值',
            '出现时执行': 'true.json',
            '未出现时执行': 'false.json',
          }),
          executionDelay: 0,
          onStatusChanged: (s, m, p) {
            if (s == ScriptStatus.callSubroutine) branch = m;
          },
        );
        expect(ok, true);
        expect(branch, expectedBranch, reason: 'op=$op val=$extracted');
      }

      // 内联子脚本分支：满足时执行子跳转脚本且保持 jump 状态
      final jumpStatuses = <ScriptStatus>[];
      controller.onEvaluateJavascript = (_) => 200;
      expect(
        await executor.execute(
          controller,
          Script(type: '逻辑脚本-数值对比', params: {
            '目标值': '100',
            '对比方式': '>',
            '出现时执行': {'type': '跳转脚本', '跳转的脚本序号': '2'},
          }),
          executionDelay: 0,
          onStatusChanged: (s, m, p) => jumpStatuses.add(s),
        ),
        true,
      );
      expect(jumpStatuses.last, ScriptStatus.jump);

      // 页面无数值 / 非法目标值
      controller.onEvaluateJavascript = (_) => null;
      expect(
        await executor.execute(
          controller,
          Script(type: '逻辑脚本-数值对比', params: {'目标值': '100'}),
          executionDelay: 0,
        ),
        false,
      );
      expect(
        await executor.execute(
          controller,
          Script(type: '逻辑脚本-数值对比', params: {'目标值': 'abc'}),
          executionDelay: 0,
        ),
        false,
      );
    });

    test('19. 数值对比-点击文字：条件满足点击/不满足放行/未找到跳过与失败', () async {
      // A. 条件满足且触发点击导航
      bool navWaited = false;
      controller.onEvaluateJavascript = (_) => 'clicked_nav';
      expect(
        await executor.execute(
          controller,
          Script(type: '数值对比-点击文字', params: {
            '点击文本': '购买体力',
            '目标值': '50',
            '对比方式': '<=',
            '多个筛选': 1,
            '在此之后': '体力:',
            '在此之前': '金币:',
          }),
          executionDelay: 0,
          waitForPageLoad: ({
            preNavToken,
            preUrl,
            preLoadStartEpoch,
            preLoadStopEpoch,
            probeWindowMs = 60,
          }) async {
            navWaited = true;
          },
        ),
        true,
      );
      expect(navWaited, true);

      // B. 条件不满足属于正常分支判断，返回 true
      controller.onEvaluateJavascript = (_) => 'condition_not_met: 99';
      expect(
        await executor.execute(
          controller,
          Script(type: '数值对比-点击文字', params: {
            '点击文本': '购买体力',
            '目标值': '50',
            '对比方式': '<',
          }),
          executionDelay: 0,
        ),
        true,
      );

      // C. not_found 时：跳过 vs 失败
      ScriptStatus? st;
      controller.onEvaluateJavascript = (_) => 'not_found';
      expect(
        await executor.execute(
          controller,
          Script(type: '数值对比-点击文字', params: {
            '点击文本': '补给',
            '目标值': '10',
            '未找到时跳过': true,
          }),
          executionDelay: 0,
          onStatusChanged: (s, m, p) => st = s,
        ),
        true,
      );
      expect(st, ScriptStatus.skipped);

      expect(
        await executor.execute(
          controller,
          Script(type: '数值对比-点击文字', params: {
            '点击文本': '补给',
            '目标值': '10',
            '未找到时跳过': false,
            '超时时间': 0,
          }),
          executionDelay: 0,
        ),
        false,
      );
    });

    test('20. 跳转脚本：兼容整数、字符串及非法序号拦截', () async {
      ScriptStatus? st;
      String? msg;
      expect(
        await executor.execute(
          null,
          Script(type: '跳转脚本', params: {'跳转的脚本序号': 3}),
          executionDelay: 0,
          onStatusChanged: (s, m, p) {
            st = s;
            msg = m;
          },
        ),
        true,
      );
      expect(st, ScriptStatus.jump);
      expect(msg, '3');

      expect(
        await executor.execute(
          null,
          Script(type: '跳转脚本', params: {'跳转的脚本序号': '7'}),
          executionDelay: 0,
          onStatusChanged: (s, m, p) => msg = m,
        ),
        true,
      );
      expect(msg, '7');

      expect(
        await executor.execute(
          null,
          Script(type: '跳转脚本', params: {'跳转的脚本序号': '非数字'}),
          executionDelay: 0,
          onStatusChanged: (s, m, p) => st = s,
        ),
        false,
      );
      expect(st, ScriptStatus.failure);
    });

    test('21-22. Cookie 脚本边界校验：设置Cookie / 清除Cookie 无网页 URL 或缺参拦截', () async {
      final events1 = <(ScriptStatus, String?)>[];
      controller.currentUrl = null;

      expect(
        await executor.execute(
          controller,
          Script(type: '设置Cookie', params: {'Cookie名称': 'sid', 'Cookie值': '1'}),
          executionDelay: 0,
          onStatusChanged: (s, m, p) => events1.add((s, m)),
        ),
        false,
      );
      expect(
        events1.any((e) =>
            e.$1 == ScriptStatus.failure && e.$2 == '无法获取当前页面网址'),
        true,
      );

      final events2 = <(ScriptStatus, String?)>[];
      controller.currentUrl = WebUri('https://example.com');
      expect(
        await executor.execute(
          controller,
          Script(type: '设置Cookie', params: {}),
          executionDelay: 0,
          onStatusChanged: (s, m, p) => events2.add((s, m)),
        ),
        false,
      );
      expect(
        events2.any((e) =>
            e.$1 == ScriptStatus.failure && e.$2 == '未指定账号存档名称或 Cookie 名称'),
        true,
      );

      // 清除当前站点 Cookie 且 URL 为空 -> 安全完成或跳过不崩溃
      controller.currentUrl = null;
      expect(
        await executor.execute(
          controller,
          Script(type: '清除Cookie', params: {'清除全部站点': false, '清除后刷新页面': false}),
          executionDelay: 0,
        ),
        true,
      );
    });

    test('23. 提取文字：text/html/属性 全部提取模式与变量写回共享池', () async {
      final sharedVars = <String, String>{};
      controller.onEvaluateJavascript = (src) {
        if (src.contains('const attr = "text";')) return 'Lv.99 吕布';
        if (src.contains('const attr = "html";')) return '<b>Lv.99</b>';
        if (src.contains('const attr = "href";')) return 'zhsh.do?cmd=100';
        return null;
      };

      expect(
        await executor.execute(
          controller,
          Script(type: '提取文字', params: {
            'CSS选择器': '.hero-name',
            '属性': 'text',
            '变量名': 'hero',
          }),
          executionDelay: 0,
          variables: sharedVars,
        ),
        true,
      );
      expect(sharedVars['hero'], 'Lv.99 吕布');

      expect(
        await executor.execute(
          controller,
          Script(type: '提取文字', params: {
            'CSS选择器': '.hero-link',
            '属性': 'href',
            '保存至变量': 'heroUrl',
          }),
          executionDelay: 0,
          variables: sharedVars,
        ),
        true,
      );
      expect(sharedVars['heroUrl'], 'zhsh.do?cmd=100');

      // 后续步骤自动引用提取结果
      final resolved = executor.resolveVariables(
        Script(type: '进入网址', params: {'网址': 'https://game.com/\${heroUrl}'}),
        sharedVars,
      );
      expect(resolved.params['网址'], 'https://game.com/zhsh.do?cmd=100');

      // 缺少选择器直接失败
      expect(
        await executor.execute(
          controller,
          Script(type: '提取文字', params: {'CSS选择器': ''}),
          executionDelay: 0,
        ),
        false,
      );
    });

    test('24-25. 内部扩展类型：滑动页面（4种方向）与 等待文字出现（命中/超时/缺参）', () async {
      for (final dir in ['向下', '向上', '到顶', '到底']) {
        controller.onEvaluateJavascript = (_) => 'true';
        expect(
          await executor.execute(
            controller,
            Script(type: '滑动页面', params: {'方向': dir, '距离': 600}),
            executionDelay: 0,
          ),
          true,
        );
        expect(controller.evaluatedSources.last.contains(dir), true);
        expect(controller.evaluatedSources.last.contains('_auokSimulateCanvasSwipe'), true);
      }

      // 等待文字出现 - 立即命中
      ScriptStatus? st;
      controller.onEvaluateJavascript = (_) => 'true';
      expect(
        await executor.execute(
          controller,
          Script(type: '等待文字出现', params: {
            '出现文字': '加载完成',
            '超时时间': 200,
            '超时单位': 'ms',
          }),
          executionDelay: 0,
          onStatusChanged: (s, m, p) => st = s,
        ),
        true,
      );
      expect(st, ScriptStatus.success);

      // 等待文字出现 - 超时失败
      controller.onEvaluateJavascript = (_) => 'false';
      expect(
        await executor.execute(
          controller,
          Script(type: '等待文字出现', params: {
            '出现文字': '永远不会出现',
            '超时时间': 60,
            '超时单位': 'ms',
          }),
          executionDelay: 0,
          onStatusChanged: (s, m, p) => st = s,
        ),
        false,
      );
      expect(st, ScriptStatus.failure);
    });

    test('26. 超时策略与跳过策略全组合解析测试 (ms / s / 历史数字兼容 / 目标等待 / 未找到时跳过)', () {
      // 目标等待优先
      expect(
        executor.getElementWaitTimeout(Script(
          type: '点击文字',
          params: {'目标等待': 350, '未找到时跳过': true, '超时时间': 30, '超时单位': 's'},
        )),
        const Duration(milliseconds: 350),
      );
      // 未找到时跳过=true 且无目标等待 -> 0ms
      expect(
        executor.getElementWaitTimeout(Script(
          type: '点击文字',
          params: {'未找到时跳过': true, '超时时间': 15, '超时单位': 's'},
        )),
        Duration.zero,
      );
      // 未找到时跳过=false 且无单位时兼容 <=120 秒 / >120 毫秒
      expect(
        executor.getElementWaitTimeout(Script(
          type: '点击文字',
          params: {'未找到时跳过': false, '超时时间': 12},
        )),
        const Duration(seconds: 12),
      );
      expect(
        executor.getElementWaitTimeout(Script(
          type: '点击文字',
          params: {'未找到时跳过': false, '超时时间': 800},
        )),
        const Duration(milliseconds: 800),
      );
    });

    test('27. 全部脚本类型 JSON 序列化闭环 (toUserMap <-> fromUserMap <-> toMap <-> fromMap)', () {
      final allSamples = <Script>[
        Script(type: '点击文字', params: {'点击文本': '确定', '完全匹配': true, '多个筛选': 1}),
        Script(type: '输入框提交', params: {
          '提交按钮文字': '提交',
          '多个筛选': 1,
          '启用正则': true,
          '输入空以当前值提交': true,
          '表单数据': {'a': '[0-9]{4}', 'b': ''},
        }),
        Script(type: '进入网址', params: {'网址': 'https://example.com'}),
        Script(type: '间隔时间', params: {'时间间隔-小时': 1, '时间间隔-分钟': 2, '时间间隔-秒': 3}),
        Script(type: '自定义JS', params: {'代码': 'return 1;', 'js内容': 'return 1;'}),
        Script(type: '点击图片', params: {'图片地址': 'btn.png', '多个筛选': -1}),
        Script(type: '刷新网页', params: {}),
        Script(type: '网页后退', params: {}),
        Script(type: '网页前进', params: {}),
        Script(type: '脚本替换', params: {}, targetScriptPath: 'a.json'),
        Script(type: '脚本停止', params: {'执行完成提醒': true}),
        Script(type: '脚本暂停', params: {'执行完成提醒': false}),
        Script(type: '执行本地脚本集', params: {}, targetScriptPath: 'b.json'),
        Script(type: '控制脚本开关', params: {'脚本序号': '1,2', '开关动作': '反相'}),
        Script(type: '通知栏提醒', params: {'提醒内容': '提示'}),
        Script(type: '逻辑脚本-出现文字', params: {'出现文字': '完成', '出现时执行': 't.json'}),
        Script(type: '逻辑脚本-时间对比', params: {'目标值': '12:00:00'}),
        Script(type: '逻辑脚本-数值对比', params: {'目标值': '10', '对比方式': '>='}),
        Script(type: '延时脚本', params: {'执行延迟': 500}),
        Script(type: '数值对比-点击文字', params: {'点击文本': '购买', '目标值': '100', '对比方式': '<'}),
        Script(type: '新建窗口并执行脚本', params: {'窗口名称': '小号1', '窗口UA': 'Desktop', '网址': 'https://a.com', '立即执行': true}),
        Script(type: '跳转脚本', params: {'跳转的脚本序号': '2'}),
        Script(type: '设置Cookie', params: {'账号存档名称': 'main', '设置后刷新页面': true}),
        Script(type: '清除Cookie', params: {'清除全部站点': true, '清除后刷新页面': false}),
        Script(type: '提取文字', params: {'CSS选择器': '.id', '属性': 'text', '变量名': 'id'}),
      ];

      for (final s in allSamples) {
        final userMap = s.toUserMap();
        final fromUser = Script.fromUserMap(userMap);
        expect(fromUser.type, s.type);
        expect(fromUser.targetScriptPath, s.targetScriptPath);

        final roundTrip = Script.fromMap(fromUser.toMap());
        expect(roundTrip.type, s.type);
        expect(roundTrip.targetScriptPath, s.targetScriptPath);
        expect(roundTrip.params, fromUser.params);
      }
    });
  });

  group('UI 与跨标签页端到端 Widget 探索测试', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    testWidgets('28. 新建窗口并执行脚本：真实挂载 navigatorKey 创建带 UA/名称/脚本集的标签页', (tester) async {
      final tempDir = Directory.systemTemp.createTempSync('auok_new_win_test_');
      final scriptFile = File('${tempDir.path}/sub_flow.json');
      scriptFile.writeAsStringSync(jsonEncode([
        {'脚本类型': '刷新网页'},
        {'脚本类型': '点击文字', '点击文本': '开始'},
      ]));

      final browserProvider = BrowserProvider();
      final scriptProvider = ScriptProvider();

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider.value(value: browserProvider),
            ChangeNotifierProvider.value(value: scriptProvider),
          ],
          child: MaterialApp(
            navigatorKey: BrowserProvider.navigatorKey,
            home: const Scaffold(body: SizedBox.shrink()),
          ),
        ),
      );
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 50));
      });
      await tester.pump();

      final initialTabs = browserProvider.tabs.length;
      final executor = ScriptExecutor();

      // 必须在 runAsync 中执行，避免 _executeNewWindowScript 的 dart:io 文件读取在 FakeAsync 中阻塞
      final ok = await tester.runAsync(() => executor.execute(
            null,
            Script(type: '新建窗口并执行脚本', params: {
              '窗口名称': '副将窗口',
              '窗口UA': 'Desktop',
              '网址': 'game.example.org/play',
              '脚本集': scriptFile.path,
              '立即执行': false,
            }),
            executionDelay: 0,
          ));

      expect(ok, true);
      expect(browserProvider.tabs.length, initialTabs + 1);
      final newTab = browserProvider.tabs.last;
      expect(newTab.customName, '副将窗口');
      expect(newTab.customUserAgent, 'Desktop');
      expect(newTab.url, 'http://game.example.org/play');
      expect(newTab.scripts.length, 2);
      expect(newTab.scripts[1].params['点击文本'], '开始');

      tempDir.deleteSync(recursive: true);
    });

    testWidgets('29. AddScriptDialog 界面探索：脚本类型切换 & 输入框提交【输入空以当前值提交】保存验证', (tester) async {
      final browserProvider = BrowserProvider();
      final scriptProvider = ScriptProvider();
      final tab = BrowserTab(id: 'ui_tab');
      scriptProvider.setCurrentTab(tab);

      Script? savedScript;

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider.value(value: browserProvider),
            ChangeNotifierProvider.value(value: scriptProvider),
          ],
          child: MaterialApp(
            home: Builder(
              builder: (ctx) => Scaffold(
                body: ElevatedButton(
                  onPressed: () async {
                    savedScript = await showDialog<Script>(
                      context: ctx,
                      builder: (_) => const AddScriptDialog(),
                    );
                  },
                  child: const Text('打开弹窗'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 50));
      });
      await tester.pumpAndSettle();

      await tester.tap(find.text('打开弹窗'));
      await tester.pumpAndSettle();

      // 1. 打开脚本类型选择器，验证内置置顶与底部类型（通过滚动弹窗 ListView），再选「输入框提交」
      await tester.tap(find.text('点击文字').first);
      await tester.pumpAndSettle();

      final popupScrollable = find.byType(Scrollable).last;
      expect(find.text('输入框提交'), findsWidgets);
      await tester.scrollUntilVisible(
        find.text('点击图片'),
        150,
        scrollable: popupScrollable,
      );
      expect(find.text('点击图片'), findsOneWidget);

      await tester.scrollUntilVisible(
        find.text('输入框提交'),
        -150,
        scrollable: popupScrollable,
      );
      await tester.tap(find.text('输入框提交').last);
      await tester.pumpAndSettle();

      // 2. 验证「启用正则」和「输入空以当前值提交」以及 ? 提示按钮均显示
      expect(find.text('启用正则'), findsOneWidget);
      expect(find.text('输入空以当前值提交'), findsOneWidget);
      expect(find.text('?'), findsNWidgets(2));

      // 按行文本精准勾选两个复选框
      final regexCheckbox = find.descendant(
        of: find.ancestor(of: find.text('启用正则'), matching: find.byType(Row)),
        matching: find.byType(Checkbox),
      );
      final keepCurrentCheckbox = find.descendant(
        of: find.ancestor(
            of: find.text('输入空以当前值提交'), matching: find.byType(Row)),
        matching: find.byType(Checkbox),
      );

      await tester.ensureVisible(regexCheckbox);
      await tester.tap(regexCheckbox);
      await tester.pump();
      await tester.ensureVisible(keepCurrentCheckbox);
      await tester.tap(keepCurrentCheckbox);
      await tester.pump();

      expect(
        find.textContaining('将页面上当前选中的值作为提交的值'),
        findsOneWidget,
      );

      // 点击「添加字段」并保留字段值为空
      await tester.ensureVisible(find.text('添加字段'));
      await tester.tap(find.text('添加字段'));
      await tester.pump();

      // 点击「确认」保存并返回 Script 对象
      await tester.tap(find.text('确认'));
      await tester.pumpAndSettle();

      expect(savedScript, isNotNull);
      expect(savedScript!.type, '输入框提交');
      expect(savedScript!.params['启用正则'], true);
      expect(savedScript!.params['输入空以当前值提交'], true);
      expect(savedScript!.params['表单数据'], {'field1': ''});
    });

    testWidgets('30. 循环次数迁移：编辑弹窗隐藏并保留原值，长按菜单【在前插入新脚本】下方可修改', (tester) async {
      final browserProvider = BrowserProvider();
      final scriptProvider = ScriptProvider();
      final tab = BrowserTab(id: 'repeat_ui_tab');
      tab.scripts.add(Script(
        type: '点击文字',
        params: {'点击文本': '去签到', '重复次数': 3},
        isEnabled: true,
      ));
      scriptProvider.setCurrentTab(tab);

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider.value(value: browserProvider),
            ChangeNotifierProvider.value(value: scriptProvider),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: SizedBox(
                width: 260,
                height: 600,
                child: RightScriptPanel(
                  onAddScript: () {},
                  onGlobalSettings: () {},
                  onExecute: () {},
                  onLoad: () {},
                ),
              ),
            ),
          ),
        ),
      );
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 50));
      });
      await tester.pumpAndSettle();

      // 1. 点击单个脚本打开编辑弹窗：确认弹窗内不再显示「循环次数」，保存后原重复次数 3 被保留
      await tester.tap(find.text('去签到'));
      await tester.pumpAndSettle();

      expect(find.text('编辑脚本'), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(AddScriptDialog),
          matching: find.text('循环次数'),
        ),
        findsNothing,
      );
      await tester.tap(find.text('确认'));
      await tester.pumpAndSettle();
      expect(scriptProvider.scripts[0].params['重复次数'], 3);

      // 2. 长按单个脚本：验证「循环次数」位于「在前插入新脚本」下方，且显示当前 3次
      await tester.longPress(find.text('去签到'));
      await tester.pumpAndSettle();

      final insertTileFinder = find.text('在前插入新脚本');
      final repeatTileFinder = find.text('循环次数');
      expect(insertTileFinder, findsOneWidget);
      expect(repeatTileFinder, findsOneWidget);
      expect(find.text('3次'), findsOneWidget);
      expect(
        tester.getTopLeft(repeatTileFinder).dy,
        greaterThan(tester.getTopLeft(insertTileFinder).dy),
      );

      // 3. 点击「循环次数」修改为 5 并确定
      await tester.tap(repeatTileFinder);
      await tester.pumpAndSettle();

      expect(find.text('设置循环次数'), findsOneWidget);
      await tester.enterText(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.byType(TextField),
        ),
        '5',
      );
      await tester.tap(find.text('确定'));
      await tester.pumpAndSettle();

      expect(scriptProvider.scripts[0].params['重复次数'], 5);
    });

    testWidgets('31. 逻辑脚本弹窗：设定时间格式提示 与 三个逻辑脚本分支子弹窗配置闭环', (tester) async {
      Script? savedScript;
      final browserProvider = BrowserProvider();
      final scriptProvider = ScriptProvider();

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider.value(value: browserProvider),
            ChangeNotifierProvider.value(value: scriptProvider),
          ],
          child: MaterialApp(
            home: Builder(
              builder: (ctx) => Scaffold(
                body: ElevatedButton(
                  onPressed: () async {
                    savedScript = await showDialog<Script>(
                      context: ctx,
                      builder: (_) => AddScriptDialog(
                        script: Script(type: '逻辑脚本-时间对比', params: {}),
                      ),
                    );
                  },
                  child: const Text('打开时间对比弹窗'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 50));
      });
      await tester.pumpAndSettle();

      await tester.tap(find.text('打开时间对比弹窗'));
      await tester.pumpAndSettle();

      // 1. 验证「设定时间」、格式说明 `?` 提示及两个分支设置按钮
      expect(find.text('设定时间'), findsOneWidget);
      expect(find.text('时间之后,则执行:'), findsOneWidget);
      expect(find.text('时间之前,则执行:'), findsOneWidget);
      expect(find.text('点击设置脚本(选填)'), findsNWidgets(2));
      expect(find.text('?'), findsWidgets);

      // 点击最后一个 `?` 按钮，验证弹出格式规则说明
      await tester.tap(find.text('?').last);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.textContaining('2013-01-01 09:30:58'), findsOneWidget);
      expect(find.textContaining('+02:00:00'), findsOneWidget);

      // 2. 填写相对时间 +02:00:00
      final targetTimeField = find.descendant(
        of: find
            .ancestor(
              of: find.text('设定时间'),
              matching: find.byType(Padding),
            )
            .first,
        matching: find.byType(TextField),
      );
      await tester.enterText(targetTimeField, '+02:00:00');
      await tester.pump();

      // 3. 点击第一个分支弹出内嵌子弹窗配置子脚本
      await tester.ensureVisible(find.text('点击设置脚本(选填)').first);
      await tester.tap(find.text('点击设置脚本(选填)').first);
      await tester.pumpAndSettle();

      expect(find.text('添加脚本'), findsOneWidget);
      final childClickField = find.descendant(
        of: find
            .ancestor(
              of: find.text('点击文本').last,
              matching: find.byType(Padding),
            )
            .first,
        matching: find.byType(TextField),
      );
      await tester.enterText(childClickField, '去付款');
      await tester.pump();

      await tester.tap(find.text('确认').last);
      await tester.pumpAndSettle();

      // 主弹窗应展示已配子脚本摘要，另一分支仍为未配置
      expect(find.text('点击文字   去付款'), findsOneWidget);
      expect(find.text('点击设置脚本(选填)'), findsOneWidget);

      // 4. 保存外层逻辑脚本并校验持久化的内嵌子脚本结构
      await tester.tap(find.text('确认').first);
      await tester.pumpAndSettle();

      expect(savedScript, isNotNull);
      expect(savedScript!.type, '逻辑脚本-时间对比');
      expect(savedScript!.params['目标值'], '+02:00:00');
      expect(savedScript!.params['出现时执行'], isA<Map<String, dynamic>>());
      final trueBranch =
          savedScript!.params['出现时执行'] as Map<String, dynamic>;
      expect(trueBranch['type'], '点击文字');
      expect(trueBranch['点击文本'], '去付款');
      expect(savedScript!.params.containsKey('未出现时执行'), false);
    });
  });
}

