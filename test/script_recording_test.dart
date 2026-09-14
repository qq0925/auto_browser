import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:auto_browser/models/browser_tab.dart';
import 'package:auto_browser/providers/script_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('脚本录制 - 点击文字完全匹配与智能多重筛选测试', () {
    late ScriptProvider scriptProvider;
    late BrowserTab testTab;

    setUp(() {
      SharedPreferences.setMockInitialValues({});
      scriptProvider = ScriptProvider();
      testTab = BrowserTab(id: 'test_tab');
      scriptProvider.setCurrentTab(testTab);
      scriptProvider.startRecording();
    });

    test('唯一文字元素录制：默认完全匹配且无多个筛选', () {
      final payload = json.encode({
        'text': '登录',
        'index': 1,
        'total': 1,
      });

      scriptProvider.handleScriptMessage('点击文字|$payload');

      expect(testTab.scripts.length, 1);
      final script = testTab.scripts[0];
      expect(script.type, '点击文字');
      expect(script.params['点击文本'], '登录');
      expect(script.params['完全匹配'], true);
      expect(script.params.containsKey('多个筛选'), false);
    });

    test('多重相同文字元素录制（点击第1个）：默认完全匹配并智能补全 多个筛选: 1', () {
      final payload = json.encode({
        'text': '删除',
        'index': 1,
        'total': 3,
      });

      scriptProvider.handleScriptMessage('点击文字|$payload');

      expect(testTab.scripts.length, 1);
      final script = testTab.scripts[0];
      expect(script.type, '点击文字');
      expect(script.params['点击文本'], '删除');
      expect(script.params['完全匹配'], true);
      expect(script.params['多个筛选'], 1);
    });

    test('多重相同文字元素录制（点击第2个）：默认完全匹配并智能补全 多个筛选: 2', () {
      final payload = json.encode({
        'text': '删除',
        'index': 2,
        'total': 3,
      });

      scriptProvider.handleScriptMessage('点击文字|$payload');

      expect(testTab.scripts.length, 1);
      final script = testTab.scripts[0];
      expect(script.type, '点击文字');
      expect(script.params['点击文本'], '删除');
      expect(script.params['完全匹配'], true);
      expect(script.params['多个筛选'], 2);
    });

    test('兼容性解析：传统竖线分隔消息亦默认开启完全匹配与筛选', () {
      scriptProvider.handleScriptMessage('点击文字|查看详情|3');

      expect(testTab.scripts.length, 1);
      final script = testTab.scripts[0];
      expect(script.type, '点击文字');
      expect(script.params['点击文本'], '查看详情');
      expect(script.params['完全匹配'], true);
      expect(script.params['多个筛选'], 3);
    });

    test('负数筛选（如 -1 倒数第1个）：能正常识别并保存', () {
      scriptProvider.handleScriptMessage('点击文字|末尾按钮|-1');

      expect(testTab.scripts.length, 1);
      final script = testTab.scripts[0];
      expect(script.type, '点击文字');
      expect(script.params['点击文本'], '末尾按钮');
      expect(script.params['完全匹配'], true);
      expect(script.params['多个筛选'], -1);
    });

    test('悬浮通知文本流验证', () async {
      final emittedActions = <String>[];
      final subscription = scriptProvider.lastRecordedActionStream.listen(
        emittedActions.add,
      );

      // 单个元素
      scriptProvider.handleScriptMessage(
        '点击文字|${json.encode({'text': '确定', 'index': 1, 'total': 1})}',
      );

      // 多个元素中的第2个
      scriptProvider.handleScriptMessage(
        '点击文字|${json.encode({'text': '编辑', 'index': 2, 'total': 4})}',
      );

      await Future.delayed(const Duration(milliseconds: 50));

      expect(emittedActions, [
        '点击文字: 确定',
        '点击文字: 编辑 (第2个/共4个)',
      ]);

      await subscription.cancel();
    });
  });
}
