import 'package:auto_browser/utils/welcome_manager.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('WelcomeManager 双屏起始页逻辑测试', () {
    test('远程地址与 isWelcomeUrl 判定正确', () {
      expect(WelcomeManager.remoteUrl, 'http://test.txsj.ink/welcome.html');
      expect(WelcomeManager.remoteUrl2, 'http://test.txsj.ink/welcome_2.html');

      expect(WelcomeManager.isWelcomeUrl(null), isTrue);
      expect(WelcomeManager.isWelcomeUrl(''), isTrue);
      expect(WelcomeManager.isWelcomeUrl('about:blank'), isTrue);
      expect(WelcomeManager.isWelcomeUrl('file:///welcome.html'), isTrue);
      expect(WelcomeManager.isWelcomeUrl('file:///welcome_2.html'), isTrue);
      expect(
        WelcomeManager.isWelcomeUrl('http://test.txsj.ink/welcome.html'),
        isTrue,
      );
      expect(
        WelcomeManager.isWelcomeUrl('http://test.txsj.ink/welcome_2.html'),
        isTrue,
      );
      expect(WelcomeManager.isWelcomeUrl('https://www.baidu.com'), isFalse);
      expect(WelcomeManager.isWelcomeUrl('file:///guide.html'), isFalse);
    });

    test('buildDualScreenHtml 正确组装双屏容器、安全转义 </script> 并注入顶层跳转基标', () {
      const page1 = '''
<!DOCTYPE html>
<html>
<head><title>第一屏</title></head>
<body>
  <a href="https://example.com/1">去第一屏链接</a>
  <script>var msg = "hello 'world' </script>";</script>
</body>
</html>
''';
      const page2 = '''
<!DOCTYPE html>
<html>
<head><title>第二屏</title></head>
<body>
  <div onclick="location.href='https://example.com/2'">第二屏卡片</div>
</body>
</html>
''';

      final html = WelcomeManager.buildDualScreenHtml(page1, page2);

      // 外壳结构与双圆点指示器
      expect(html, contains('id="auok-frame-0"'));
      expect(html, contains('id="auok-frame-1"'));
      expect(html, contains('id="auok-dot-0"'));
      expect(html, contains('id="auok-dot-1"'));
      expect(html, contains('var currentPage = 0;'));

      // 内嵌脚本中的 </script> 必须被安全转义，避免提前闭合外壳 <script>
      expect(html, contains(r'<\/script>'));
      // 仅允许外壳本身存在一次 </body> 后的闭合，不含未转义的 page1 内部闭合
      expect(RegExp(r'</script>').allMatches(html).length, 1);

      // 自动注入 <base target="_top"> 与手势/交互桥接
      expect(html, contains('<base target=\\"_top\\">'));
      expect(html, contains('__auokPagerDrag'));
      expect(html, contains('__auokPagerEnd'));
      expect(html, contains('__auokGetCurrentPage'));
      expect(html, contains('__auokHasRecentUserGesture'));
      expect(html, contains('auok-night-mode'));
      expect(html, contains('auok-font-size-adjust'));
    });

    test('buildDualScreenHtml 支持指定默认定位到第二屏', () {
      final html = WelcomeManager.buildDualScreenHtml(
        '<html><body>P1</body></html>',
        '<html><body>P2</body></html>',
        initialPage: 1,
      );
      expect(html, contains('var currentPage = 1;'));
    });

    test('内置兜底资产 assets/welcome.html 与 assets/welcome_2.html 均可读取', () async {
      final asset1 = await rootBundle.loadString('assets/welcome.html');
      final asset2 = await rootBundle.loadString('assets/welcome_2.html');
      expect(asset1, contains('欢迎使用'));
      expect(asset2, contains('第二屏'));
    });
  });
}
