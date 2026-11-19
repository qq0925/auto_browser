import 'dart:convert';
import 'dart:io';
import 'package:flutter/services.dart' show rootBundle;
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

/// 起始页（双屏：welcome.html + welcome_2.html）拉取、缓存、兜底与双屏容器管理器
class WelcomeManager {
  /// 第一屏远程地址、本地缓存文件名与内置兜底资产路径
  static const String remoteUrl = 'http://test.txsj.ink/welcome.html';
  static const String _localFilename = 'welcome.html';
  static const String _assetPath = 'assets/welcome.html';

  /// 第二屏远程地址、本地缓存文件名与内置兜底资产路径
  static const String remoteUrl2 = 'http://test.txsj.ink/welcome_2.html';
  static const String _localFilename2 = 'welcome_2.html';
  static const String _assetPath2 = 'assets/welcome_2.html';

  /// 短时内存缓存，避免冷启动 / onWebViewCreated / onUpdateVisitedHistory 同一秒重复发起多次 HTTP 请求
  static String? _cachedDualHtml;
  static DateTime? _cachedAt;
  static String? _lastPage1Html;
  static String? _lastPage2Html;
  static const Duration _memoryCacheTtl = Duration(seconds: 3);

  /// 统一判断某个 URL 是否属于起始页（含空白页、welcome.html 与 welcome_2.html）
  static bool isWelcomeUrl(String? url) {
    if (url == null || url.isEmpty) return true;
    return url == 'about:blank' ||
        url == 'file:///welcome.html' ||
        url == 'file:///welcome_2.html' ||
        url.endsWith('welcome.html') ||
        url.endsWith('welcome_2.html');
  }

  /// 清空内存短时缓存（供测试或强制刷新使用）
  static void clearMemoryCache() {
    _cachedDualHtml = null;
    _cachedAt = null;
    _lastPage1Html = null;
    _lastPage2Html = null;
  }

  /// 拉取单屏最新远程内容，成功写入本地缓存并返回，失败返回 null
  static Future<String?> _fetchSingleRemote(
    String url,
    String localFilename, {
    required Duration timeout,
  }) async {
    try {
      final response = await http.get(Uri.parse(url)).timeout(timeout);
      if (response.statusCode == 200 && response.bodyBytes.isNotEmpty) {
        final content = utf8.decode(response.bodyBytes);
        await _saveToLocal(localFilename, content);
        return content;
      }
    } catch (_) {}
    return null;
  }

  /// 读取单屏本地缓存或内置兜底资产
  static Future<String> _readSingleLocalOrAsset(
    String localFilename,
    String assetPath,
  ) async {
    try {
      final documentsDir = await getApplicationDocumentsDirectory();
      final localFile = File(path.join(documentsDir.path, localFilename));
      if (await localFile.exists()) {
        final cached = await localFile.readAsString();
        if (cached.isNotEmpty) {
          return cached;
        }
      }
    } catch (_) {}

    return await rootBundle.loadString(assetPath);
  }

  /// 单屏内容获取（沿用原有三级降级：1. 服务器在线拉取 -> 2. 本地缓存 -> 3. 内置资产兜底）
  static Future<String> _getSinglePageContent(
    String url,
    String localFilename,
    String assetPath, {
    required Duration remoteTimeout,
  }) async {
    final remoteContent = await _fetchSingleRemote(
      url,
      localFilename,
      timeout: remoteTimeout,
    );
    if (remoteContent != null && remoteContent.isNotEmpty) {
      return remoteContent;
    }
    return _readSingleLocalOrAsset(localFilename, assetPath);
  }

  /// 尝试从服务器并发拉取第一屏与第二屏最新原始 HTML，并返回是否相对上次内容发生了实质变化
  /// 用于切回前台时判断是否需要静默重载，避免内容未变化时无故刷新并打回第一屏
  static Future<({String page1, String page2, bool changed})?>
      fetchLatestRemotePages({
    Duration timeout = const Duration(seconds: 3),
  }) async {
    final results = await Future.wait<String?>([
      _fetchSingleRemote(remoteUrl, _localFilename, timeout: timeout),
      _fetchSingleRemote(remoteUrl2, _localFilename2, timeout: timeout),
    ]);

    final remote1 = results[0];
    final remote2 = results[1];
    if (remote1 == null && remote2 == null) {
      return null;
    }

    final page1 = remote1 ??
        await _readSingleLocalOrAsset(_localFilename, _assetPath);
    final page2 = remote2 ??
        await _readSingleLocalOrAsset(_localFilename2, _assetPath2);

    final changed = _lastPage1Html != page1 || _lastPage2Html != page2;
    _lastPage1Html = page1;
    _lastPage2Html = page2;
    _cachedDualHtml = buildDualScreenHtml(page1, page2, initialPage: 0);
    _cachedAt = DateTime.now();

    return (page1: page1, page2: page2, changed: changed);
  }

  /// 尝试从服务器并发拉取第一屏与第二屏最新内容
  /// 若至少有一屏拉取成功，则另一屏以本地缓存/兜底补齐并组装双屏 HTML 返回；两屏均失败则返回 null
  static Future<String?> fetchLatestRemoteContent({
    Duration timeout = const Duration(seconds: 3),
    int initialPage = 0,
  }) async {
    final fetched = await fetchLatestRemotePages(timeout: timeout);
    if (fetched == null) {
      return null;
    }
    return buildDualScreenHtml(
      fetched.page1,
      fetched.page2,
      initialPage: initialPage,
    );
  }

  /// 获取双屏起始页完整 HTML 内容
  /// 每屏均遵循优先级：1. 服务器最新页面（默认超时 2.5s） -> 2. 本地缓存文件 -> 3. 内置兜底资产
  static Future<String> getWelcomeContent({
    Duration remoteTimeout = const Duration(milliseconds: 2500),
    bool forceRefresh = false,
    int initialPage = 0,
  }) async {
    if (!forceRefresh &&
        initialPage == 0 &&
        _cachedDualHtml != null &&
        _cachedAt != null &&
        DateTime.now().difference(_cachedAt!) < _memoryCacheTtl) {
      return _cachedDualHtml!;
    }

    // 并发获取两屏内容，不额外增加等待耗时
    final pages = await Future.wait<String>([
      _getSinglePageContent(
        remoteUrl,
        _localFilename,
        _assetPath,
        remoteTimeout: remoteTimeout,
      ),
      _getSinglePageContent(
        remoteUrl2,
        _localFilename2,
        _assetPath2,
        remoteTimeout: remoteTimeout,
      ),
    ]);

    _lastPage1Html = pages[0];
    _lastPage2Html = pages[1];
    final dualHtml = buildDualScreenHtml(
      pages[0],
      pages[1],
      initialPage: initialPage,
    );
    if (initialPage == 0) {
      _cachedDualHtml = dualHtml;
      _cachedAt = DateTime.now();
    }
    return dualHtml;
  }

  /// 辅助方法：异步将单屏内容持久化到本地文档目录
  static Future<void> _saveToLocal(String filename, String content) async {
    try {
      final documentsDir = await getApplicationDocumentsDirectory();
      final localFile = File(path.join(documentsDir.path, filename));
      await localFile.writeAsString(content, encoding: utf8);
    } catch (_) {}
  }

  /// 后台静默更新 welcome.html 与 welcome_2.html 本地缓存（无 UI 干扰）
  static Future<void> updateWelcomeInBackground() async {
    await Future.wait([
      _fetchSingleRemote(
        remoteUrl,
        _localFilename,
        timeout: const Duration(seconds: 5),
      ),
      _fetchSingleRemote(
        remoteUrl2,
        _localFilename2,
        timeout: const Duration(seconds: 5),
      ),
    ]);
  }

  /// 将字符串编码为可安全内联到 <script> 标签中的 JSON 字符串（防止 </script> 提前闭合脚本）
  static String _encodeJsString(String raw) {
    return jsonEncode(raw)
        .replaceAll('</', r'<\/')
        .replaceAll('\u2028', r'\u2028')
        .replaceAll('\u2029', r'\u2029');
  }

  /// 为单屏 HTML 注入顶层跳转基标与手势/交互桥接脚本，确保在双屏 iframe 中与原单页行为完全一致
  static String _prepareSlideHtml(String rawHtml, int slideIndex) {
    String html = rawHtml;

    // 1. 注入 <base target="_top">，让所有未显式指定 target 的 <a>/<form> 直接在主 WebView 打开
    final hasBaseTag =
        RegExp(r'<base\b', caseSensitive: false).hasMatch(html);
    if (!hasBaseTag) {
      final headMatch =
          RegExp(r'<head\b[^>]*>', caseSensitive: false).firstMatch(html);
      if (headMatch != null) {
        html = html.replaceRange(
          headMatch.end,
          headMatch.end,
          '<base target="_top">',
        );
      } else {
        html = '<base target="_top">$html';
      }
    }

    // 2. 注入轻量桥接脚本：顶层导航转发、flutter_inappwebview 转发、跟手左右横滑手势
    final bridgeScript = _slideBridgeScriptTemplate
        .replaceAll('__AUOK_SLIDE_INDEX__', '$slideIndex');

    final bodyCloseMatch =
        RegExp(r'</body>', caseSensitive: false).firstMatch(html);
    if (bodyCloseMatch != null) {
      html = html.replaceRange(
        bodyCloseMatch.start,
        bodyCloseMatch.start,
        bridgeScript,
      );
    } else {
      html = '$html$bridgeScript';
    }
    return html;
  }

  /// 将第一屏（welcome.html）与第二屏（welcome_2.html）组装为支持左右滑动切换的双屏起始页 HTML
  static String buildDualScreenHtml(
    String page1Html,
    String page2Html, {
    int initialPage = 0,
  }) {
    final safeInitial = initialPage == 1 ? 1 : 0;
    final prepared1 = _prepareSlideHtml(page1Html, 0);
    final prepared2 = _prepareSlideHtml(page2Html, 1);

    return _dualScreenShellTemplate
        .replaceAll('__AUOK_PAGE1_JSON__', _encodeJsString(prepared1))
        .replaceAll('__AUOK_PAGE2_JSON__', _encodeJsString(prepared2))
        .replaceAll('__AUOK_INITIAL_PAGE__', '$safeInitial');
  }

  /// 注入到每个子屏 iframe 内的轻量桥接脚本
  static const String _slideBridgeScriptTemplate = r'''
<script>
(function() {
  var SLIDE_INDEX = __AUOK_SLIDE_INDEX__;

  // 透传 flutter_inappwebview 供起始页脚本（若有）正常调用
  try {
    if (!window.flutter_inappwebview && window.top && window.top.flutter_inappwebview) {
      window.flutter_inappwebview = window.top.flutter_inappwebview;
    }
  } catch (_) {}

  // 记录用户主动交互时间，协助主 WebView 精准区分主动跳转与内嵌子框架
  function markInteract() {
    try {
      if (window.top) window.top.__auokLastInteract = Date.now();
    } catch (_) {}
  }
  document.addEventListener('pointerdown', markInteract, true);
  document.addEventListener('touchstart', markInteract, true);
  document.addEventListener('mousedown', markInteract, true);
  document.addEventListener('click', markInteract, true);

  // 确保显式声明 target="_blank" 或 target="_self" 的链接与表单也在主 WebView 顶层打开
  document.addEventListener('click', function(e) {
    try {
      var a = e.target && e.target.closest ? e.target.closest('a[href]') : null;
      if (!a) return;
      var href = (a.getAttribute('href') || '').trim();
      if (!href || href.charAt(0) === '#' || /^javascript:/i.test(href)) return;
      var t = (a.getAttribute('target') || '').toLowerCase();
      if (!t || t === '_blank' || t === '_self') {
        a.setAttribute('target', '_top');
      }
    } catch (_) {}
  }, true);

  document.addEventListener('submit', function(e) {
    try {
      var form = e.target;
      if (!form || form.tagName !== 'FORM') return;
      var t = (form.getAttribute('target') || '').toLowerCase();
      if (!t || t === '_blank' || t === '_self') {
        form.setAttribute('target', '_top');
      }
    } catch (_) {}
  }, true);

  // 将 window.open 平滑转为顶层窗口导航
  try {
    window.open = function(url) {
      if (url && typeof url === 'string') {
        var trimmed = url.trim();
        if (trimmed && trimmed !== 'about:blank' && !/^javascript:/i.test(trimmed)) {
          try {
            window.top.location.href = new URL(trimmed, window.location.href).href;
          } catch (_) {
            window.top.location.href = trimmed;
          }
        }
      }
      return window.top;
    };
  } catch (_) {}

  // 判断触摸目标是否位于支持横向滚动的局部容器内，避免误抢轮播/横向表格的手势
  function isInsideHorizontalScroller(el, dx) {
    var cur = el;
    while (cur && cur !== document.body && cur !== document.documentElement) {
      try {
        var style = window.getComputedStyle(cur);
        var ox = style.overflowX;
        if ((ox === 'auto' || ox === 'scroll') && cur.scrollWidth > cur.clientWidth + 2) {
          if (dx < 0 && cur.scrollLeft + cur.clientWidth < cur.scrollWidth - 2) return true;
          if (dx > 0 && cur.scrollLeft > 2) return true;
        }
      } catch (_) {}
      cur = cur.parentElement;
    }
    return false;
  }

  // 移动端单指跟手左右横滑切换起始页双屏
  var startX = 0, startY = 0, startTime = 0, lastDx = 0, lockState = 0; // 0:未判定 1:横向切屏 2:纵向滚动
  var touchTarget = null;

  document.addEventListener('touchstart', function(e) {
    if (!e.touches || e.touches.length !== 1) {
      lockState = 2;
      return;
    }
    var t = e.touches[0];
    startX = t.clientX;
    startY = t.clientY;
    startTime = Date.now();
    lastDx = 0;
    lockState = 0;
    touchTarget = e.target;
  }, { passive: true });

  document.addEventListener('touchmove', function(e) {
    if (lockState === 2 || !e.touches || e.touches.length !== 1) return;
    var t = e.touches[0];
    var dx = t.clientX - startX;
    var dy = t.clientY - startY;

    if (lockState === 0) {
      if (Math.abs(dx) < 10 && Math.abs(dy) < 10) return;
      if (Math.abs(dx) > Math.abs(dy) * 1.15 && !isInsideHorizontalScroller(touchTarget, dx)) {
        lockState = 1;
      } else {
        lockState = 2;
        return;
      }
    }

    if (lockState === 1) {
      lastDx = dx;
      if (e.cancelable) e.preventDefault();
      try {
        if (window.parent && window.parent.__auokPagerDrag) {
          window.parent.__auokPagerDrag(SLIDE_INDEX, dx);
        }
      } catch (_) {}
    }
  }, { passive: false });

  function finishTouch() {
    if (lockState === 1) {
      var dt = Math.max(1, Date.now() - startTime);
      var vx = lastDx / dt;
      try {
        if (window.parent && window.parent.__auokPagerEnd) {
          window.parent.__auokPagerEnd(SLIDE_INDEX, lastDx, vx);
        }
      } catch (_) {}
    }
    lockState = 0;
    lastDx = 0;
    touchTarget = null;
  }

  document.addEventListener('touchend', finishTouch, { passive: true });
  document.addEventListener('touchcancel', finishTouch, { passive: true });

  // 桌面端触控板横向双指滑动切屏
  var lastWheelSwitch = 0;
  document.addEventListener('wheel', function(e) {
    try {
      if (Math.abs(e.deltaX) > Math.abs(e.deltaY) * 1.35 && Math.abs(e.deltaX) > 28) {
        var now = Date.now();
        if (now - lastWheelSwitch < 480) return;
        if (isInsideHorizontalScroller(e.target, -e.deltaX)) return;
        if (e.deltaX > 0 && SLIDE_INDEX === 0) {
          lastWheelSwitch = now;
          window.parent && window.parent.__auokGoToWelcomePage && window.parent.__auokGoToWelcomePage(1);
        } else if (e.deltaX < 0 && SLIDE_INDEX === 1) {
          lastWheelSwitch = now;
          window.parent && window.parent.__auokGoToWelcomePage && window.parent.__auokGoToWelcomePage(0);
        }
      }
    } catch (_) {}
  }, { passive: true });

  // 桌面端键盘左右方向键切屏（输入框聚焦时不拦截）
  document.addEventListener('keydown', function(e) {
    try {
      var tag = (e.target && e.target.tagName || '').toUpperCase();
      if (tag === 'INPUT' || tag === 'TEXTAREA' || tag === 'SELECT' || (e.target && e.target.isContentEditable)) {
        return;
      }
      if (e.key === 'ArrowRight' && SLIDE_INDEX === 0) {
        window.parent && window.parent.__auokGoToWelcomePage && window.parent.__auokGoToWelcomePage(1);
      } else if (e.key === 'ArrowLeft' && SLIDE_INDEX === 1) {
        window.parent && window.parent.__auokGoToWelcomePage && window.parent.__auokGoToWelcomePage(0);
      }
    } catch (_) {}
  });
})();
</script>
''';

  /// 双屏起始页外壳 HTML 模板
  static const String _dualScreenShellTemplate = r'''<!DOCTYPE html>
<html>
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no">
  <title>欢迎使用</title>
  <style>
    html, body {
      margin: 0;
      padding: 0;
      width: 100%;
      height: 100%;
      overflow: hidden;
      background: #ffffff;
      -webkit-tap-highlight-color: transparent;
    }
    html.auok-dark, html.auok-dark body {
      background: #121212;
    }
    .auok-viewport {
      position: relative;
      width: 100%;
      height: 100%;
      overflow: hidden;
    }
    .auok-track {
      display: flex;
      width: 200%;
      height: 100%;
      will-change: transform;
      transform: translate3d(0, 0, 0);
    }
    .auok-track.animating {
      transition: transform 0.28s cubic-bezier(0.22, 1, 0.36, 1);
    }
    .auok-slide {
      flex: 0 0 50%;
      width: 50%;
      height: 100%;
      position: relative;
      overflow: hidden;
    }
    .auok-frame {
      width: 100%;
      height: 100%;
      border: 0;
      display: block;
      background: transparent;
    }
    .auok-dots {
      position: fixed;
      left: 50%;
      bottom: 14px;
      transform: translateX(-50%);
      z-index: 9999;
      display: flex;
      align-items: center;
      gap: 8px;
      padding: 6px 12px;
      border-radius: 999px;
      background: rgba(0, 0, 0, 0.16);
      backdrop-filter: blur(6px);
      -webkit-backdrop-filter: blur(6px);
      user-select: none;
    }
    html.auok-dark .auok-dots {
      background: rgba(255, 255, 255, 0.16);
    }
    .auok-dot {
      width: 7px;
      height: 7px;
      border-radius: 999px;
      border: 0;
      padding: 0;
      margin: 0;
      cursor: pointer;
      background: rgba(255, 255, 255, 0.55);
      transition: width 0.22s ease, background-color 0.22s ease;
      outline: none;
    }
    .auok-dot.active {
      width: 18px;
      background: #ffffff;
    }
  </style>
</head>
<body>
  <div class="auok-viewport">
    <div id="auok-track" class="auok-track">
      <div class="auok-slide">
        <iframe id="auok-frame-0" name="auok_welcome_1" class="auok-frame" frameborder="0"></iframe>
      </div>
      <div class="auok-slide">
        <iframe id="auok-frame-1" name="auok_welcome_2" class="auok-frame" frameborder="0"></iframe>
      </div>
    </div>
    <div class="auok-dots" role="tablist" aria-label="起始页切换">
      <button id="auok-dot-0" class="auok-dot" type="button" aria-label="起始页第一屏"></button>
      <button id="auok-dot-1" class="auok-dot" type="button" aria-label="起始页第二屏"></button>
    </div>
  </div>
  <script>
  (function() {
    var page1Html = __AUOK_PAGE1_JSON__;
    var page2Html = __AUOK_PAGE2_JSON__;
    var currentPage = __AUOK_INITIAL_PAGE__;

    var track = document.getElementById('auok-track');
    var frame0 = document.getElementById('auok-frame-0');
    var frame1 = document.getElementById('auok-frame-1');
    var dot0 = document.getElementById('auok-dot-0');
    var dot1 = document.getElementById('auok-dot-1');

    window.__auokLastInteract = 0;
    window.__auokHasRecentUserGesture = function() {
      return (Date.now() - (window.__auokLastInteract || 0)) < 2500;
    };

    function getViewportWidth() {
      return Math.max(1, window.innerWidth || document.documentElement.clientWidth || 360);
    }

    function updateDots() {
      if (dot0) dot0.classList.toggle('active', currentPage === 0);
      if (dot1) dot1.classList.toggle('active', currentPage === 1);
    }

    function applyOffset(px, animate) {
      if (!track) return;
      if (animate) {
        track.classList.add('animating');
      } else {
        track.classList.remove('animating');
      }
      track.style.transform = 'translate3d(' + px + 'px, 0, 0)';
    }

    function goToPage(index, animate) {
      currentPage = index === 1 ? 1 : 0;
      var w = getViewportWidth();
      applyOffset(-currentPage * w, animate !== false);
      updateDots();
    }

    window.__auokGoToWelcomePage = function(index) {
      goToPage(index, true);
    };

    window.__auokGetCurrentPage = function() {
      return currentPage;
    };

    window.__auokPagerDrag = function(slideIndex, dx) {
      var w = getViewportWidth();
      var base = -slideIndex * w;
      var adjustedDx = dx;
      // 边界橡皮筋阻尼手感
      if ((slideIndex === 0 && dx > 0) || (slideIndex === 1 && dx < 0)) {
        adjustedDx = dx * 0.22;
      } else if (Math.abs(dx) > w) {
        adjustedDx = dx > 0 ? w : -w;
      }
      applyOffset(base + adjustedDx, false);
    };

    window.__auokPagerEnd = function(slideIndex, dx, vx) {
      var w = getViewportWidth();
      var threshold = w * 0.18;
      var target = slideIndex;
      if (slideIndex === 0 && (dx < -threshold || vx < -0.35)) {
        target = 1;
      } else if (slideIndex === 1 && (dx > threshold || vx > 0.35)) {
        target = 0;
      }
      goToPage(target, true);
    };

    if (dot0) dot0.addEventListener('click', function() { goToPage(0, true); });
    if (dot1) dot1.addEventListener('click', function() { goToPage(1, true); });

    window.addEventListener('resize', function() {
      goToPage(currentPage, false);
    });

    // 同步夜间模式与字体缩放样式到两个子屏 iframe
    function syncStyleToFrame(frame, styleId) {
      try {
        var doc = frame && frame.contentDocument;
        if (!doc) return;
        var hostStyle = document.getElementById(styleId);
        var existing = doc.getElementById(styleId);
        if (hostStyle) {
          if (!existing) {
            existing = doc.createElement('style');
            existing.id = styleId;
            (doc.head || doc.documentElement).appendChild(existing);
          }
          if (existing.textContent !== hostStyle.textContent) {
            existing.textContent = hostStyle.textContent;
          }
        } else if (existing) {
          existing.remove();
        }
      } catch (_) {}
    }

    function syncAllHostStyles() {
      var hasDark = !!document.getElementById('auok-night-mode');
      document.documentElement.classList.toggle('auok-dark', hasDark);
      syncStyleToFrame(frame0, 'auok-night-mode');
      syncStyleToFrame(frame1, 'auok-night-mode');
      syncStyleToFrame(frame0, 'auok-font-size-adjust');
      syncStyleToFrame(frame1, 'auok-font-size-adjust');
    }

    if (frame0) frame0.addEventListener('load', syncAllHostStyles);
    if (frame1) frame1.addEventListener('load', syncAllHostStyles);

    try {
      var observer = new MutationObserver(syncAllHostStyles);
      observer.observe(document.documentElement, { childList: true, subtree: true });
    } catch (_) {}

    // 注入两屏 HTML 并定位到初始屏
    goToPage(currentPage, false);
    if (frame0) frame0.srcdoc = page1Html;
    if (frame1) frame1.srcdoc = page2Html;
    setTimeout(syncAllHostStyles, 60);
  })();
  </script>
</body>
</html>''';
}
