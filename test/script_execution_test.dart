import 'package:flutter_test/flutter_test.dart';
import 'package:auto_browser/models/script.dart';
import 'package:auto_browser/services/script_executor.dart';

void main() {
  group('ScriptExecutor 核心逻辑与漏洞审计测试', () {
    late ScriptExecutor executor;

    setUp(() {
      executor = ScriptExecutor();
    });

    test('控制脚本开关：支持多种分隔符 (空格/逗号/中文逗号/分号)', () async {
      final scripts = [
        Script(type: '点击文字', params: {'点击文本': 'A'}, isEnabled: true),
        Script(type: '点击文字', params: {'点击文本': 'B'}, isEnabled: false),
        Script(type: '点击文字', params: {'点击文本': 'C'}, isEnabled: true),
        Script(type: '点击文字', params: {'点击文本': 'D'}, isEnabled: false),
      ];

      // 1. 使用逗号与空格混合测试
      final switchScript = Script(
        type: '控制脚本开关',
        params: {
          '脚本序号': '1, 2，3;4',
          '开关动作': '反相',
        },
      );

      final ok = await executor.execute(
        null,
        switchScript,
        scripts: scripts,
      );

      expect(ok, true);
      expect(scripts[0].isEnabled, false); // true -> false
      expect(scripts[1].isEnabled, true);  // false -> true
      expect(scripts[2].isEnabled, false); // true -> false
      expect(scripts[3].isEnabled, true);  // false -> true
    });

    test(r'动态变量跨步骤插值替换 (${var} 与 $var 语法)', () async {
      final script = Script(
        type: '进入网址',
        params: {
          '网址': 'https://api.example.com/order/\${orderId}?token=\$userToken',
          '嵌套配置': {
            '备注': '处理订单 \${orderId}',
          },
          '列表参数': ['\${orderId}', '固定值'],
        },
      );

      final vars = {
        'orderId': 'AUOK-2026-9988',
        'userToken': 'SECRET_TOKEN_XYZ',
      };

      // 验证变量替换逻辑
      final resolved = executor.resolveVariables(script, vars);

      expect(
        resolved.params['网址'],
        'https://api.example.com/order/AUOK-2026-9988?token=SECRET_TOKEN_XYZ',
      );
      expect(
        (resolved.params['嵌套配置'] as Map)['备注'],
        '处理订单 AUOK-2026-9988',
      );
      expect(
        (resolved.params['列表参数'] as List)[0],
        'AUOK-2026-9988',
      );
    });

    test('跳转脚本：兼容数字与字符串序号', () async {
      ScriptStatus? receivedStatus;
      String? receivedMessage;

      final jumpScript = Script(
        type: '跳转脚本',
        params: {
          '跳转的脚本序号': 5, // int 类型安全兼容
        },
      );

      final ok = await executor.execute(
        null,
        jumpScript,
        onStatusChanged: (status, message, progress) {
          receivedStatus = status;
          receivedMessage = message;
        },
      );

      expect(ok, true);
      expect(receivedStatus, ScriptStatus.jump);
      expect(receivedMessage, '5');
    });

    test('点击文字 JS 逻辑生成：完全匹配与多个筛选边界验证', () {
      final params = {
        '点击文本': '确定',
        '完全匹配': true,
        '多个筛选': -1, // 倒数第1个
      };

      final js = executor.buildClickScriptLogic(params);

      // 校验生成的 JS 中包含完全匹配标志
      expect(js.contains('const exactMatch = true;'), true);
      // 校验包含负数反向索引计算
      expect(js.contains('const selectionIndex = -1;'), true);
      expect(js.contains('Math.max(0, matchedLinks.length + selectionIndex)'), true);
      // 校验叶子节点剪枝算法
      expect(js.contains('leafMatched'), true);
    });
  });
}

// 模拟 WebViewController
dynamic fakeController() => null;
