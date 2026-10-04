import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:provider/provider.dart';
import 'dart:io';
import 'dart:convert';
import 'dart:async';
import 'dart:math';
import '../models/script.dart';
import '../providers/browser_provider.dart';
import '../providers/script_provider.dart';
import 'cookie_service.dart';

class ScriptExecutor {
  // Execute a script on the given controller
  Future<bool> execute(InAppWebViewController? controller, Script script,
      {int executionDelay = 1000,
      Function(ScriptStatus status, String? message, double? progress)?
          onStatusChanged,
      Future<void> Function()? waitForPageLoad,
      List<Script>? scripts,
      Map<String, String>? variables}) async {
    if (!script.isEnabled) return false;

    // 动态解析脚本参数中的变量 (${varName})
    final resolvedScript = _resolveVariables(script, variables);

    // 将变量注入至当前页面的 window._auokVars
    if (controller != null && variables != null && variables.isNotEmpty) {
      try {
        final varsJson = jsonEncode(variables);
        await controller.evaluateJavascript(
            source: 'try { window._auokVars = $varsJson; } catch(e) {}');
      } catch (_) {}
    }

    final repeatCount = resolvedScript.params['重复次数'] ?? 1;
    bool success = true;

    for (var i = 0; i < repeatCount; i++) {
      // 1. 识别导航类动作（进入网址、刷新网页、网页后退、网页前进）
      final isNavAction = resolvedScript.type == '进入网址' ||
          resolvedScript.type == '刷新网页' ||
          resolvedScript.type == '网页后退' ||
          resolvedScript.type == '网页前进';

      // 2. 步骤前智能等待：若用户显式勾选了【等待网页加载】或当前 WebView 确实处于加载中状态（如上一步交互引发了页面跳转）
      if (waitForPageLoad != null) {
        bool needsWaitBefore = resolvedScript.params['等待网页加载'] == true;
        if (!needsWaitBefore && controller != null) {
          try {
            needsWaitBefore = await controller.isLoading();
          } catch (_) {}
        }
        if (needsWaitBefore) {
          onStatusChanged?.call(ScriptStatus.waiting, '等待网页加载完成...', null);
          await waitForPageLoad();
        }
      }

      // 3. 执行单步配置的延迟或全局延迟
      int delay = executionDelay;
      if (script.params.containsKey('执行延迟')) {
        delay = script.params['执行延迟'] as int;
      }

      if (delay > 0) {
        onStatusChanged?.call(ScriptStatus.waiting, '等待延迟 ${delay}ms...', 0.0);
        await Future.delayed(Duration(milliseconds: delay));
        onStatusChanged?.call(ScriptStatus.waiting, '等待延迟 ${delay}ms...', 1.0);
      }

      onStatusChanged?.call(ScriptStatus.running, null, null);

      bool result = false;

      if (repeatCount > 1) {
        onStatusChanged?.call(
            ScriptStatus.running, '正在执行第 ${i + 1}/$repeatCount 次', null);
      }

      // 执行前置脚本
      if (script.params['执行每个脚本前执行'] != null) {
        final beforeScriptMap = script.params['执行每个脚本前执行'];
        if (beforeScriptMap is Map<String, dynamic>) {
          final beforeScript = Script.fromUserMap(beforeScriptMap);
          await execute(controller, beforeScript,
              executionDelay: executionDelay,
              onStatusChanged: (status, msg, prog) {
            if (status == ScriptStatus.running ||
                status == ScriptStatus.waiting) {
              onStatusChanged?.call(status, '前置: ${msg ?? "正在执行..."}', prog);
            } else if (status == ScriptStatus.failure) {
              debugPrint('Before script failed: $msg');
            }
          });
        }
      }

      // 脚本超时时间（默认 30 秒，可在参数中自定义）
      final timeoutSeconds = resolvedScript.params['超时时间'] as int? ?? 30;
      try {
        result = await _executeSingleStep(
          controller,
          resolvedScript,
          onStatusChanged,
          scripts,
          variables: variables,
        ).timeout(Duration(seconds: timeoutSeconds));
      } on TimeoutException {
        onStatusChanged?.call(
            ScriptStatus.failure, '脚本执行超时 ($timeoutSeconds 秒)', null);
        result = false;
      } catch (e) {
        onStatusChanged?.call(ScriptStatus.failure, '脚本执行异常: $e', null);
        result = false;
      }

      // 4. 关键：导航动作执行后置等待！
      // 进入网址、刷新、后退、前进在触发后，必须等待目标新页面真正加载并解析完毕
      // 彻底解决 0ms 延迟下 loadUrl 刚发出下一步就抢跑在旧/空页面的问题！
      if (result && isNavAction && waitForPageLoad != null) {
        onStatusChanged?.call(ScriptStatus.waiting, '等待新网页加载完成...', null);
        await waitForPageLoad();
      }

      // 执行后置脚本
      if (resolvedScript.params['执行每个脚本后执行'] != null) {
        final afterScriptMap = resolvedScript.params['执行每个脚本后执行'];
        if (afterScriptMap is Map<String, dynamic>) {
          final afterScript = Script.fromUserMap(afterScriptMap);
          await execute(controller, afterScript,
              executionDelay: executionDelay,
              variables: variables,
              onStatusChanged: (status, msg, prog) {
            if (status == ScriptStatus.running ||
                status == ScriptStatus.waiting) {
              onStatusChanged?.call(status, '后置: ${msg ?? "正在执行..."}', prog);
            } else if (status == ScriptStatus.failure) {
              debugPrint('After script failed: $msg');
            }
          });
        }
      }

      if (!result) {
        success = false;
        onStatusChanged?.call(ScriptStatus.failure, '执行失败', null);
        break;
      }
    }

    const flowControlTypes = {
      "跳转脚本",
      "脚本替换",
      "执行本地脚本集",
      "脚本停止",
      "脚本暂停",
    };
    if (success && !flowControlTypes.contains(resolvedScript.type)) {
      onStatusChanged?.call(ScriptStatus.success, null, 1.0);
    }

    return success;
  }

  Future<bool> _executeSingleStep(
    InAppWebViewController? controller,
    Script script,
    Function(ScriptStatus status, String? message, double? progress)?
        onStatusChanged,
    List<Script>? scripts, {
    Map<String, String>? variables,
  }) async {
    const nonControllerTypes = {
      "控制脚本开关",
      "跳转脚本",
      "延时脚本",
      "脚本停止",
      "脚本暂停",
      "脚本替换",
      "执行本地脚本集",
      "通知栏提醒",
      "新建窗口并执行脚本",
    };
    if (controller == null && !nonControllerTypes.contains(script.type)) {
      onStatusChanged?.call(ScriptStatus.failure, 'WebView 控制器未就绪', null);
      return false;
    }

    switch (script.type) {
      case "点击文字":
        return await _executeClickScript(controller!, script);
      case "输入框提交":
        return await _executeFormSubmit(controller!, script);
      case "间隔时间":
        return await _executeIntervalScript(
            controller!, script, onStatusChanged);
      case "自定义JS":
        return await _executeCustomJs(controller!, script,
            onStatusChanged: onStatusChanged);
      case "进入网址":
        return await _executeNavigate(controller!, script);
      case "点击图片":
        return await _executeClickImage(controller!, script);
      case "刷新网页":
        await controller!.reload();
        return true;
      case "网页后退":
        final canBack = await controller!.canGoBack();
        if (canBack) await controller.goBack();
        return true;
      case "网页前进":
        final canForward = await controller!.canGoForward();
        if (canForward) await controller.goForward();
        return true;
      case "脚本停止":
        onStatusChanged?.call(ScriptStatus.stopped, '脚本已停止', null);
        return true;
      case "脚本暂停":
        onStatusChanged?.call(ScriptStatus.paused, '脚本已暂停', null);
        return true;
      case "脚本替换":
        if (script.targetScriptPath != null) {
          onStatusChanged?.call(
              ScriptStatus.replaced, script.targetScriptPath, null);
          return true;
        } else {
          onStatusChanged?.call(ScriptStatus.failure, '未指定替换脚本集', null);
          return false;
        }
      case "执行本地脚本集":
        if (script.targetScriptPath != null) {
          onStatusChanged?.call(
              ScriptStatus.callSubroutine, script.targetScriptPath, null);
          return true;
        } else {
          onStatusChanged?.call(ScriptStatus.failure, '未指定脚本集', null);
          return false;
        }
      case "通知栏提醒":
        if (script.params['提醒内容'] != null) {
          onStatusChanged?.call(
              ScriptStatus.notification, script.params['提醒内容'], null);
          return true;
        } else {
          onStatusChanged?.call(ScriptStatus.failure, '未指定提醒内容', null);
          return false;
        }
      case "延时脚本":
        return true;

      case "控制脚本开关":
        if (scripts != null) {
          final indicesStr = script.params['脚本序号']?.toString();
          final action = script.params['开关动作']?.toString();

          if (indicesStr != null && action != null) {
            final indices = indicesStr
                .split(RegExp(r'[\s,，;；]+'))
                .map((e) => int.tryParse(e))
                .where((e) => e != null)
                .cast<int>()
                .toList();

            for (var index in indices) {
              final listIndex = index - 1;
              if (listIndex >= 0 && listIndex < scripts.length) {
                final targetScript = scripts[listIndex];
                switch (action) {
                  case '禁用':
                    targetScript.isEnabled = false;
                    break;
                  case '启用':
                    targetScript.isEnabled = true;
                    break;
                  case '反相':
                    targetScript.isEnabled = !targetScript.isEnabled;
                    break;
                }
              }
            }
            onStatusChanged?.call(ScriptStatus.success,
                '已更新脚本状态: $indicesStr -> $action', null);
            return true;
          }
        }
        onStatusChanged?.call(ScriptStatus.failure, '控制脚本开关参数错误', null);
        return false;

      case "逻辑脚本-出现文字":
        return await _executeLogicScriptAppearText(
            controller!, script, onStatusChanged);

      case "逻辑脚本-时间对比":
        return await _executeLogicScriptTimeComparison(
            controller!, script, onStatusChanged);

      case "逻辑脚本-数值对比":
        return await _executeLogicScriptValueComparison(
            controller!, script, onStatusChanged);

      case "新建窗口并执行脚本":
        return await _executeNewWindowScript(script, onStatusChanged);

      case "跳转脚本":
        return await _executeJumpScript(script, onStatusChanged);

      case "数值对比-点击文字":
        return await _executeValueComparisonClickText(
            controller!, script, onStatusChanged);

      case "滑动页面":
        return await _executeScrollPage(controller!, script, onStatusChanged);

      case "等待文字出现":
        return await _executeWaitForText(controller!, script, onStatusChanged);

      case "提取文字":
        return await _executeExtractText(controller!, script, onStatusChanged,
            variables: variables);

      case "设置Cookie":
        return await _executeSetCookie(controller!, script, onStatusChanged);

      case "清除Cookie":
        return await _executeClearCookie(controller!, script, onStatusChanged);

      default:
        return true;
    }
  }

  Future<bool> _executeSetCookie(
    InAppWebViewController controller,
    Script script,
    Function(ScriptStatus status, String? message, double? progress)?
        onStatusChanged,
  ) async {
    try {
      final url = await controller.getUrl();
      final urlString = url?.toString() ?? '';
      if (urlString.isEmpty) {
        onStatusChanged?.call(ScriptStatus.failure, '无法获取当前页面网址', null);
        return false;
      }

      final profileName = script.params['账号存档名称'] as String?;
      final cookieName = script.params['Cookie名称'] as String?;
      final cookieValue = script.params['Cookie值'] as String?;
      final autoReload = script.params['设置后刷新页面'] as bool? ?? true;

      if (profileName != null && profileName.isNotEmpty) {
        // 通过账号存档切换
        final success = await CookieService.applyProfile(
          profileName: profileName,
          urlString: urlString,
        );
        if (!success) {
          onStatusChanged?.call(
              ScriptStatus.failure, '未找到或无法应用账号存档: $profileName', null);
          return false;
        }
        onStatusChanged?.call(
            ScriptStatus.success, '已应用账号存档: $profileName', null);
      } else if (cookieName != null && cookieName.isNotEmpty) {
        // 设置单个 Cookie
        await CookieService.setCookie(
          urlString: urlString,
          name: cookieName,
          value: cookieValue ?? '',
        );
        onStatusChanged?.call(
            ScriptStatus.success, '已设置 Cookie: $cookieName', null);
      } else {
        onStatusChanged?.call(
            ScriptStatus.failure, '未指定账号存档名称或 Cookie 名称', null);
        return false;
      }

      if (autoReload) {
        await controller.reload();
      }
      return true;
    } catch (e) {
      onStatusChanged?.call(ScriptStatus.failure, '设置 Cookie 异常: $e', null);
      return false;
    }
  }

  Future<bool> _executeClearCookie(
    InAppWebViewController controller,
    Script script,
    Function(ScriptStatus status, String? message, double? progress)?
        onStatusChanged,
  ) async {
    try {
      final isClearAll = script.params['清除全部站点'] as bool? ?? false;
      final autoReload = script.params['清除后刷新页面'] as bool? ?? true;

      if (isClearAll) {
        await CookieService.clearAllCookies();
        onStatusChanged?.call(ScriptStatus.success, '已清除全部站点 Cookie', null);
      } else {
        final url = await controller.getUrl();
        final urlString = url?.toString() ?? '';
        if (urlString.isNotEmpty) {
          await CookieService.clearCookiesForUrl(urlString);
          onStatusChanged?.call(
              ScriptStatus.success, '已清除当前站点 Cookie', null);
        }
      }

      if (autoReload) {
        await controller.reload();
      }
      return true;
    } catch (e) {
      onStatusChanged?.call(ScriptStatus.failure, '清除 Cookie 异常: $e', null);
      return false;
    }
  }

  Future<bool> _executeIntervalScript(
      InAppWebViewController controller,
      Script script,
      Function(ScriptStatus status, String? message, double? progress)?
          onStatusChanged) async {
    final params = script.params;
    final h = params['时间间隔-小时'] ?? 0;
    final m = params['时间间隔-分钟'] ?? 0;
    final s = params['时间间隔-秒'] ?? 0;

    int totalSeconds = h * 3600 + m * 60 + s;
    if (totalSeconds <= 0) return true;

    for (var i = totalSeconds; i > 0; i--) {
      double progress = 1.0 - (i / totalSeconds);
      onStatusChanged?.call(ScriptStatus.waiting, '等待延迟 ${i}s', progress);
      await Future.delayed(const Duration(seconds: 1));
    }
    onStatusChanged?.call(ScriptStatus.waiting, '等待延迟 0s', 1.0);

    if (params['间隔时间后执行脚本'] != null) {
      final scriptPath = params['间隔时间后执行脚本'] as String;
      if (scriptPath.isNotEmpty) {
        onStatusChanged?.call(ScriptStatus.callSubroutine, scriptPath, null);
      }
    }

    return true;
  }

  /// 解析动作级超时时间（优先读取脚本参数中的【超时时间】，未配置时默认 5000 毫秒）
  Duration _getStepTimeout(Script script, {int defaultMs = 5000}) {
    if (script.params.containsKey('超时时间')) {
      final t = script.params['超时时间'];
      if (t is int && t > 0) {
        // 用户配置若 <= 120 视为秒；若 > 120 视为毫秒
        return Duration(milliseconds: t <= 120 ? t * 1000 : t);
      }
    }
    return Duration(milliseconds: defaultMs);
  }

  /// 智能自适应微轮询（Action Auto-Wait）：
  /// - 前 3 次使用极速 25ms 间隔探测（已就绪元素 0ms 瞬间命中，极速无感响应）；
  /// - 4~10 次使用 50ms 平滑探测；
  /// - 随后按 100ms 平稳微轮询，兼顾极速响应与现代框架（Vue/React）异步渲染容错。
  Future<bool> _pollUntilSuccess(
    Future<bool> Function() action, {
    Duration timeout = const Duration(milliseconds: 5000),
  }) async {
    final stopwatch = Stopwatch()..start();
    int attempts = 0;
    while (stopwatch.elapsed < timeout) {
      try {
        final success = await action();
        if (success) return true;
      } catch (_) {}
      final stepDelay = attempts < 3 ? 25 : (attempts < 10 ? 50 : 100);
      await Future.delayed(Duration(milliseconds: stepDelay));
      attempts++;
    }
    return false;
  }

  /// 视觉高亮脉冲光圈动画 JS 注入脚本（用于点击、表单输入前的科技感视觉反馈）
  static const String _highlightJs = '''
    function _auokHighlight(el) {
      if (!el || typeof el.getBoundingClientRect !== 'function') return;
      try {
        const rect = el.getBoundingClientRect();
        if (rect.width === 0 && rect.height === 0) return;
        const ring = document.createElement('div');
        ring.className = '_auok_tap_indicator';
        ring.style.cssText = 'position:fixed;left:' + rect.left + 'px;top:' + rect.top + 'px;width:' + rect.width + 'px;height:' + rect.height + 'px;border-radius:8px;box-shadow:0 0 0 3px #3b82f6, 0 0 16px rgba(59,130,246,0.6);background:rgba(59,130,246,0.25);pointer-events:none;z-index:2147483647;transition:all 0.28s ease-out;';
        document.documentElement.appendChild(ring);
        setTimeout(function() {
          ring.style.transform = 'scale(1.12)';
          ring.style.opacity = '0';
          setTimeout(function() { if (ring.parentNode) ring.parentNode.removeChild(ring); }, 300);
        }, 220);
      } catch(e) {}
    }

    // 现代框架（Vue 3 / React 18 / Uni-app / Angular）全仿真交互事件链
    function _auokSimulateClick(el) {
      if (!el) return;
      try {
        const opts = { bubbles: true, cancelable: true, view: window, composed: true };
        if (typeof el.focus === 'function') el.focus();
        try { el.dispatchEvent(new PointerEvent('pointerdown', opts)); } catch(_) {}
        try { el.dispatchEvent(new MouseEvent('mousedown', opts)); } catch(_) {}
        try { el.dispatchEvent(new PointerEvent('pointerup', opts)); } catch(_) {}
        try { el.dispatchEvent(new MouseEvent('mouseup', opts)); } catch(_) {}
        el.click();
      } catch(e) {
        try { el.click(); } catch(_) {}
      }
    }
  ''';

  /// 白鹭引擎 (Egret) 与 Canvas 游戏舞台智能探测 JS 脚本
  /// 支持穿透 HTML5 Canvas 画布及同源 iframe，通过 Stage 舞台树遍历可交互节点，
  /// 并支持引擎级 touchTap 事件祖先链冒泡分发与 Canvas 屏幕物理触控合成双通道触发
  static const String _egretCanvasProbeJs = r'''
    function _auokFindEgretStage(rootObj, depth) {
      if (!rootObj || depth > 3) return null;
      try {
        if (rootObj.$hitTest || rootObj.hitTest) return rootObj;
        if (rootObj.stage && (rootObj.stage.$hitTest || rootObj.stage.hitTest)) return rootObj.stage;
        for (const k in rootObj) {
          try {
            if (k.startsWith('$') || k.indexOf('egret') !== -1 || k === 'player' || k === 'stage') {
              const res = _auokFindEgretStage(rootObj[k], depth + 1);
              if (res) return res;
            }
          } catch(_) {}
        }
      } catch(_) {}
      return null;
    }

    function _auokGetEgretContext() {
      try {
        function checkDoc(doc, win) {
          if (!doc) return null;
          const canvases = Array.from(doc.querySelectorAll('canvas'));
          for (const c of canvases) {
            let stage = _auokFindEgretStage(c, 0);
            if (stage) return { stage: stage, canvas: c, window: win };
          }
          const players = Array.from(doc.querySelectorAll('.egret-player, [data-entry-class]'));
          for (const p of players) {
            let stage = _auokFindEgretStage(p, 0);
            if (stage) {
              const c = p.querySelector('canvas') || canvases[0];
              if (c) return { stage: stage, canvas: c, window: win };
            }
          }
          if (win) {
            let stage = null;
            if (win.stage) stage = _auokFindEgretStage(win.stage, 0);
            if (!stage && win.egret) {
              if (win.egret.MainContext && win.egret.MainContext.instance && win.egret.MainContext.instance.stage) {
                stage = win.egret.MainContext.instance.stage;
              } else if (win.egret.lifecycle && win.egret.lifecycle.stage) {
                stage = win.egret.lifecycle.stage;
              } else {
                stage = _auokFindEgretStage(win.egret, 0);
              }
            }
            if (!stage && win.player) stage = _auokFindEgretStage(win.player, 0);
            if (stage && canvases.length > 0) {
              return { stage: stage, canvas: canvases[0], window: win };
            }
          }
          return null;
        }

        let ctx = checkDoc(document, typeof window !== 'undefined' ? window : null);
        if (ctx) return ctx;

        const iframes = Array.from(document.querySelectorAll('iframe'));
        for (const iframe of iframes) {
          try {
            const idoc = iframe.contentDocument || (iframe.contentWindow && iframe.contentWindow.document);
            const iwin = iframe.contentWindow;
            if (idoc) {
              ctx = checkDoc(idoc, iwin);
              if (ctx) return ctx;
            }
          } catch(_) {}
        }
      } catch(e) {
        console.warn('[Auok] Get Egret context error:', e);
      }
      return null;
    }

    function _auokScanEgretNodes(stage) {
      if (!stage) return [];
      const items = [];

      function traverse(node) {
        if (!node || node.visible === false) return;

        let rawText = node.text || (node.labelDisplay && node.labelDisplay.text) || node.label || node.title || node.prompt;
        if (typeof rawText === 'string') {
          const cleanText = rawText.trim();
          if (cleanText !== '') {
            let isClickable = Boolean(
              node.touchEnabled ||
              (node.$EventDispatcher && node.$EventDispatcher.$events && node.$EventDispatcher.$events['touchTap']) ||
              (typeof node.hasEventListener === 'function' && node.hasEventListener('touchTap'))
            );

            let p = node.parent;
            let climb = 0;
            while (p && climb < 4) {
              if (p.touchEnabled ||
                  (p.$EventDispatcher && p.$EventDispatcher.$events && p.$EventDispatcher.$events['touchTap']) ||
                  (typeof p.hasEventListener === 'function' && p.hasEventListener('touchTap'))) {
                isClickable = true;
                break;
              }
              p = p.parent;
              climb++;
            }

            let gx = Math.round(node.x || 0);
            let gy = Math.round(node.y || 0);
            if (typeof node.localToGlobal === 'function') {
              try {
                const pt = node.localToGlobal(0, 0);
                if (pt && typeof pt.x === 'number') {
                  gx = Math.round(pt.x);
                  gy = Math.round(pt.y);
                }
              } catch(_) {}
            }

            items.push({
              text: cleanText,
              rawText: rawText,
              target: node,
              globalX: gx,
              globalY: gy,
              width: node.width || (p && p.width) || 60,
              height: node.height || (p && p.height) || 30,
              isClickable: isClickable
            });
          }
        }

        if (node.$children && node.$children.length > 0) {
          for (let i = 0; i < node.$children.length; i++) traverse(node.$children[i]);
        } else if (node.numChildren && node.getChildAt) {
          for (let i = 0; i < node.numChildren; i++) traverse(node.getChildAt(i));
        }
      }

      traverse(stage);
      return items;
    }

    function _auokScrollNodeIntoView(node, stage) {
      if (!node) return false;
      try {
        let curr = node.parent;
        let scrolled = false;
        while (curr && curr !== stage) {
          // 检查 eui.Scroller 容器
          if (curr.viewport && typeof curr.viewport.scrollV !== 'undefined') {
            const vp = curr.viewport;
            const vpH = vp.height || 300;
            const maxV = Math.max(0, (vp.contentHeight || 9999) - vpH);
            const targetV = Math.max(0, Math.min(maxV, node.y - vpH / 2));
            vp.scrollV = targetV;
            if (typeof curr.stopAnimation === 'function') curr.stopAnimation();
            scrolled = true;
            break;
          }
          // 检查 egret.ScrollView 容器
          if (typeof curr.scrollTop !== 'undefined' && typeof curr.setScrollTop === 'function') {
            curr.setScrollTop(Math.max(0, node.y - 100));
            scrolled = true;
            break;
          }
          curr = curr.parent;
        }
        return scrolled;
      } catch(_) {
        return false;
      }
    }

    function _auokSimulateCanvasSwipe(canvas, direction, distance, durationMs) {
      return new Promise(function(resolve) {
        if (!canvas) return resolve(false);
        try {
          const rect = canvas.getBoundingClientRect();
          const startX = rect.left + rect.width / 2;
          const dist = distance || Math.round(rect.height * 0.65);
          let startY = 0;
          let endY = 0;

          // 真实触屏手势：向下看更多内容（即页面向下滚），手势是从下往上推（Swipe Up）
          if (direction === '向下' || direction === 'down') {
            startY = rect.top + Math.min(rect.height * 0.78, rect.height - 30);
            endY = Math.max(rect.top + 30, startY - dist);
          } else if (direction === '向上' || direction === 'up') {
            startY = rect.top + Math.max(rect.height * 0.22, 30);
            endY = Math.min(rect.bottom - 30, startY + dist);
          } else if (direction === '到底') {
            startY = rect.top + rect.height * 0.85;
            endY = rect.top + 30;
          } else if (direction === '到顶') {
            startY = rect.top + 30;
            endY = rect.top + rect.height * 0.85;
          } else {
            startY = rect.top + Math.min(rect.height * 0.78, rect.height - 30);
            endY = Math.max(rect.top + 30, startY - dist);
          }

          const steps = 14;
          const stepDuration = Math.max(8, Math.floor((durationMs || 300) / steps));
          const touchId = Date.now();

          function makeTouch(y) {
            return new Touch({
              identifier: touchId,
              target: canvas,
              clientX: startX,
              clientY: y,
              pageX: startX,
              pageY: y
            });
          }

          const startTouch = makeTouch(startY);
          canvas.dispatchEvent(new TouchEvent('touchstart', {
            touches: [startTouch],
            targetTouches: [startTouch],
            changedTouches: [startTouch],
            bubbles: true,
            cancelable: true
          }));
          canvas.dispatchEvent(new PointerEvent('pointerdown', { bubbles: true, clientX: startX, clientY: startY }));

          let currentStep = 0;
          const timer = setInterval(function() {
            currentStep++;
            const p = currentStep / steps;
            const ease = 1 - Math.pow(1 - p, 2);
            const currY = startY + (endY - startY) * ease;

            const moveTouch = makeTouch(currY);
            canvas.dispatchEvent(new TouchEvent('touchmove', {
              touches: [moveTouch],
              targetTouches: [moveTouch],
              changedTouches: [moveTouch],
              bubbles: true,
              cancelable: true
            }));
            canvas.dispatchEvent(new PointerEvent('pointermove', { bubbles: true, clientX: startX, clientY: currY }));

            if (currentStep >= steps) {
              clearInterval(timer);
              const endTouch = makeTouch(endY);
              canvas.dispatchEvent(new TouchEvent('touchend', {
                touches: [],
                targetTouches: [],
                changedTouches: [endTouch],
                bubbles: true,
                cancelable: true
              }));
              canvas.dispatchEvent(new PointerEvent('pointerup', { bubbles: true, clientX: startX, clientY: endY }));
              resolve(true);
            }
          }, stepDuration);
        } catch(err) {
          console.warn('[Auok] Canvas swipe error:', err);
          resolve(false);
        }
      });
    }

    function _auokTriggerEgretClick(ctx, foundItem) {
      if (!ctx || !ctx.canvas || !foundItem || !foundItem.target) return false;
      const canvas = ctx.canvas;
      const stage = ctx.stage;
      const win = ctx.window || window;
      const doc = canvas.ownerDocument || document;
      const targetNode = foundItem.target;

      // 智能检测：若目标位于舞台或可视视口之外，自动将其滚入视野中央
      const isOutOfScreen = (foundItem.globalY < 0 || foundItem.globalY > (stage.stageHeight || 2000));
      if (isOutOfScreen) {
        _auokScrollNodeIntoView(targetNode, stage);
      }

      const rect = canvas.getBoundingClientRect();
      const stageW = (stage && stage.stageWidth) ? stage.stageWidth : (canvas.width || rect.width);
      const stageH = (stage && stage.stageHeight) ? stage.stageHeight : (canvas.height || rect.height);
      const scaleX = rect.width / stageW;
      const scaleY = rect.height / stageH;

      const itemW = foundItem.width || 40;
      const itemH = foundItem.height || 25;
      const clientX = rect.left + (foundItem.globalX + itemW / 2) * scaleX;
      const clientY = rect.top + (foundItem.globalY + itemH / 2) * scaleY;

      try {
        const ring = doc.createElement('div');
        ring.className = '_auok_tap_indicator';
        const ringW = Math.max(32, itemW * scaleX);
        const ringH = Math.max(22, itemH * scaleY);
        const ringLeft = rect.left + foundItem.globalX * scaleX;
        const ringTop = rect.top + foundItem.globalY * scaleY;
        ring.style.cssText = 'position:fixed;left:' + ringLeft + 'px;top:' + ringTop + 'px;width:' + ringW + 'px;height:' + ringH + 'px;border-radius:6px;box-shadow:0 0 0 3px #10b981, 0 0 16px rgba(16,185,129,0.7);background:rgba(16,185,129,0.25);pointer-events:none;z-index:2147483647;transition:all 0.28s ease-out;';
        doc.documentElement.appendChild(ring);
        win.setTimeout(function() {
          ring.style.transform = 'scale(1.15)';
          ring.style.opacity = '0';
          win.setTimeout(function() { if (ring.parentNode) ring.parentNode.removeChild(ring); }, 300);
        }, 220);
      } catch(_) {}

      let success = false;

      // 通道 A：引擎级 touchTap 事件直接派发 + 沿着 parent 链向上逐级冒泡分发
      try {
        let event = null;
        if (typeof win !== 'undefined' && win.egret && win.egret.TouchEvent) {
          event = new win.egret.TouchEvent(win.egret.TouchEvent.TOUCH_TAP, true, true);
        } else {
          event = {
            type: 'touchTap',
            bubbles: true,
            cancelable: true,
            target: targetNode,
            currentTarget: targetNode,
            $isDefaultPrevented: false
          };
        }

        let curr = targetNode;
        while (curr) {
          try {
            if (typeof curr.dispatchEvent === 'function') {
              curr.dispatchEvent(event);
              success = true;
            }
          } catch(_) {}
          if (curr === stage || curr.$stage) break;
          curr = curr.parent;
        }

        try {
          if (stage && typeof stage.$hitTest === 'function') {
            const hitTarget = stage.$hitTest(foundItem.globalX + itemW / 2, foundItem.globalY + itemH / 2);
            if (hitTarget && hitTarget !== targetNode && typeof hitTarget.dispatchEvent === 'function') {
              hitTarget.dispatchEvent(event);
              success = true;
            }
          }
        } catch(_) {}
      } catch (_) {}

      // 通道 B & C：Canvas 屏幕物理触控与指针事件全合成
      try {
        if (typeof Touch !== 'undefined' && typeof TouchEvent !== 'undefined') {
          const touchObj = new Touch({
            identifier: Date.now(),
            target: canvas,
            clientX: clientX,
            clientY: clientY,
            pageX: clientX + (win.pageXOffset || 0),
            pageY: clientY + (win.pageYOffset || 0)
          });
          canvas.dispatchEvent(new TouchEvent('touchstart', {
            touches: [touchObj],
            targetTouches: [touchObj],
            changedTouches: [touchObj],
            bubbles: true,
            cancelable: true
          }));
          win.setTimeout(() => {
            canvas.dispatchEvent(new TouchEvent('touchend', {
              touches: [],
              targetTouches: [],
              changedTouches: [touchObj],
              bubbles: true,
              cancelable: true
            }));
          }, 40);
        }

        const opts = { bubbles: true, cancelable: true, clientX: clientX, clientY: clientY, view: win };
        try { canvas.dispatchEvent(new PointerEvent('pointerdown', opts)); } catch(_) {}
        try { canvas.dispatchEvent(new MouseEvent('mousedown', opts)); } catch(_) {}
        try { canvas.dispatchEvent(new PointerEvent('pointerup', opts)); } catch(_) {}
        try { canvas.dispatchEvent(new MouseEvent('mouseup', opts)); } catch(_) {}
        try { canvas.dispatchEvent(new MouseEvent('click', opts)); } catch(_) {}
        success = true;
      } catch(_) {}

      return success;
    }

    // 挂载全局辅助函数供自定义JS或控制台直接调用
    if (typeof window !== 'undefined') {
      window.scanEgretElements = function() {
        const ctx = _auokGetEgretContext();
        return ctx ? _auokScanEgretNodes(ctx.stage) : [];
      };

      window.swipeVirtual = function(direction, distance) {
        const ctx = _auokGetEgretContext();
        if (ctx && ctx.canvas) {
          return _auokSimulateCanvasSwipe(ctx.canvas, direction || '向下', distance || 450, 320);
        }
        return Promise.resolve(false);
      };
      window.scrollEgret = window.swipeVirtual;

      window.clickVirtual = function(keyword, exact) {
        const ctx = _auokGetEgretContext();
        if (!ctx) {
          console.warn('[Auok] 未探测到白鹭引擎 (Egret) 舞台');
          return false;
        }
        const nodes = _auokScanEgretNodes(ctx.stage);
        if (!nodes || nodes.length === 0) return false;

        function normalize(s) { return (s || '').replace(/\s+/g, ''); }
        const targetClean = normalize(keyword);

        let match = nodes.find(n => {
          const itemClean = normalize(n.text);
          return itemClean === targetClean;
        });

        if (!match && !exact) {
          match = nodes.find(n => {
            const itemClean = normalize(n.text);
            return itemClean.includes(targetClean) || n.text.includes(keyword);
          });
        }

        if (!match) {
          console.warn('[Auok] 白鹭舞台内未找到包含文字的目标:', keyword);
          return false;
        }
        return _auokTriggerEgretClick(ctx, match);
      };
    }
  ''';

  /// 公开白鹭引擎与 Canvas 游戏智能探测 JS 脚本，供 WebView 初始化常驻挂载
  static const String egretCanvasProbeJs = _egretCanvasProbeJs;

  Future<bool> _executeClickScript(
      InAppWebViewController controller, Script script) async {
    final params = script.getClickParams();
    final clickText = params['点击文本'] ?? '';
    if (clickText.isEmpty) return false;

    // Always handle delay if present, regardless of mode
    final delay = params['执行延迟'] ?? 0;
    if (delay > 0) {
      final timeUnit = params['时间单位'] ?? '毫秒';
      final multiplier = TimeUnit.values
          .firstWhere(
            (unit) => unit.label == timeUnit,
            orElse: () => TimeUnit.milliseconds,
          )
          .multiplier;

      await Future.delayed(Duration(milliseconds: delay * multiplier));
    }

    return await _pollUntilSuccess(() async {
      final result = await controller.evaluateJavascript(source: '''
        (function() {
          ${_buildClickScriptLogic(params)}
        })();
      ''');
      return result.toString() == 'true';
    }, timeout: _getStepTimeout(script));
  }

  Future<bool> _executeFormSubmit(
      InAppWebViewController controller, Script script) async {
    final params = script.params;
    if (params.isEmpty) return false;

    // Get formData map and button text
    final formData = params['表单数据'] as Map<String, dynamic>? ?? {};
    final buttonText = params['提交按钮文字'] as String? ?? '提交';
    final multipleSelection = params['多个筛选'] as int? ?? 1;
    final enableRegex = params['启用正则'] as bool? ?? false;

    if (formData.isEmpty) return false;

    // Process Regex if enabled
    Map<String, dynamic> processedFormData = Map.from(formData);
    if (enableRegex) {
      processedFormData.forEach((key, value) {
        if (value is String) {
          processedFormData[key] = _generateStringFromPattern(value);
        }
      });
    }

    final jsonFormData = jsonEncode(processedFormData);
    final jsonButtonText = jsonEncode(buttonText);

    return await _pollUntilSuccess(() async {
      final result = await controller.evaluateJavascript(source: '''
        (function() {
          $_highlightJs
          try {
            const formData = $jsonFormData;
            const buttonText = $jsonButtonText;
            const multipleSelection = $multipleSelection;
            let filledCount = 0;
            
            // Find target form based on multipleSelection
            const forms = document.querySelectorAll('form');
            let targetForm = null;
            
            if (forms.length > 0) {
              if (multipleSelection === 0) {
                // Random
                const randomIndex = Math.floor(Math.random() * forms.length);
                targetForm = forms[randomIndex];
              } else if (multipleSelection > 0) {
                // Index (1-based)
                const index = multipleSelection - 1;
                if (index < forms.length) targetForm = forms[index];
              } else {
                // Reverse Index
                const index = forms.length + multipleSelection;
                if (index >= 0) targetForm = forms[index];
              }
            }
            
            // Helper to find input within scope (form or document)
            function findInput(fieldName, scope) {
              return scope.querySelector("[name='" + fieldName + "']") || 
                     scope.querySelector("#" + fieldName) ||
                     scope.querySelector("[placeholder='" + fieldName + "']");
            }

            const scope = targetForm || document;

            for (const [fieldName, value] of Object.entries(formData)) {
              let input = findInput(fieldName, scope);
              
              if (input && input.type !== 'hidden' && input.type !== 'submit') {
                try { if (typeof input.focus === 'function') input.focus(); } catch(_) {}
                try {
                  const proto = Object.getPrototypeOf(input);
                  const setter = Object.getOwnPropertyDescriptor(proto, 'value')?.set;
                  if (setter) {
                    setter.call(input, value);
                  } else {
                    input.value = value;
                  }
                } catch (_) {
                  input.value = value;
                }
                _auokHighlight(input);
                input.dispatchEvent(new Event('input', { bubbles: true, composed: true }));
                input.dispatchEvent(new Event('change', { bubbles: true, composed: true }));
                try { if (typeof input.blur === 'function') input.blur(); } catch(_) {}
                filledCount++;
              }
            }
            
            if (filledCount > 0) {
              let submitBtn = null;
              // Search button within form first, then globally if not found
              const btnScope = targetForm || document;
              const buttons = Array.from(btnScope.querySelectorAll('button, input[type="submit"]'));
              submitBtn = buttons.find(btn => {
                const text = btn.innerText || btn.textContent || btn.value || '';
                return text.trim() === buttonText;
              });
              
              if (submitBtn) {
                _auokHighlight(submitBtn);
                _auokSimulateClick(submitBtn);
                return true;
              } else if (targetForm) {
                targetForm.submit();
                return true;
              }
            }
            
            return false;
          } catch (e) {
            console.error(e);
            return false;
          }
        })();
      ''');

      return result.toString() == 'true';
    }, timeout: _getStepTimeout(script));
  }

  Future<bool> _executeCustomJs(
      InAppWebViewController controller, Script script,
      {Function(ScriptStatus status, String? message, double? progress)?
          onStatusChanged}) async {
    final jsContent = script.params['js内容'] ?? script.params['代码'] ?? '';
    if (jsContent.isEmpty) return true; // 空脚本视为成功

    final timeout = _getStepTimeout(script);
    String lastErrorMsg = '执行失败';
    String lastSuccessInfo = '执行成功';

    final jsWrapper = '''
      (async function() {
        try {
          $_egretCanvasProbeJs

          // 执行用户自定义 JS，支持同步与 await 异步 Promise
          const __auok_exec_result = await (async function() {
            $jsContent
          })();

          // 若用户显式返回 false，则认定为未达成目标 (如未找到游戏内目标元素)
          if (__auok_exec_result === false) {
            return JSON.stringify({ ok: false, message: '脚本执行结果为 false (如未找到目标虚拟元素)' });
          }
          return JSON.stringify({ ok: true, result: String(__auok_exec_result !== undefined ? __auok_exec_result : '执行成功') });
        } catch (err) {
          console.error('Custom JS execution error:', err);
          return JSON.stringify({ ok: false, error: err ? (err.stack || err.message || String(err)) : '执行异常' });
        }
      })();
    ''';

    // 智能微轮询：在指定超时时间内（默认 5 秒）重试执行，若页面正在异步渲染/组件挂载，自动在元素出现瞬间秒级捕获！
    final success = await _pollUntilSuccess(() async {
      try {
        final result = await controller.evaluateJavascript(source: jsWrapper);
        if (result != null) {
          final decoded = jsonDecode(result.toString());
          if (decoded is Map) {
            if (decoded['ok'] == true) {
              lastSuccessInfo = decoded['result']?.toString() ?? '执行成功';
              return true;
            } else {
              lastErrorMsg = decoded['error']?.toString() ??
                  decoded['message']?.toString() ??
                  '执行失败';
              return false;
            }
          }
        }
        return result.toString() == 'true';
      } catch (e) {
        lastErrorMsg = e.toString();
        return false;
      }
    }, timeout: timeout);

    if (success) {
      onStatusChanged?.call(ScriptStatus.success, 'JS执行完成: $lastSuccessInfo', null);
      return true;
    } else {
      onStatusChanged?.call(ScriptStatus.failure, 'JS执行未成功: $lastErrorMsg', null);
      return false;
    }
  }

  String _buildClickScriptLogic(Map<String, dynamic> params) {
    final triggerTextJson = jsonEncode(params['出现文字'] ?? '');
    final clickTextJson = jsonEncode(params['点击文本'] ?? '');
    final exactMatch = params['完全匹配'] ?? false;
    final afterTextJson = jsonEncode(params['在此之后'] ?? '');
    final beforeTextJson = jsonEncode(params['在此之前'] ?? '');
    final selectionIndex = params['多个筛选'] ?? 1;

    // Unified logic: Always use Expert Mode features with Fuzzy Matching and Egret Canvas fallback
    return '''
      $_highlightJs
      $_egretCanvasProbeJs

      function _tryEgretFallback() {
        const ctx = _auokGetEgretContext();
        if (!ctx) return false;
        const egretNodes = _auokScanEgretNodes(ctx.stage);
        if (!egretNodes || egretNodes.length === 0) return false;

        function normalize(s) {
          return (s || '').replace(/\\s+/g, '');
        }

        // 阶段一：去空格全等匹配
        let matchedEgret = egretNodes.filter(item => {
          const itemClean = normalize(item.text);
          return clickTexts.some(cText => {
            const targetClean = normalize(cText);
            return itemClean === targetClean;
          });
        });

        // 阶段二：若全等未中，自动回退到模糊包含匹配（无论是否勾选完全匹配，确保游戏按钮不因多空格/换行失败）
        if (matchedEgret.length === 0) {
          matchedEgret = egretNodes.filter(item => {
            const itemClean = normalize(item.text);
            return clickTexts.some(cText => {
              const targetClean = normalize(cText);
              return itemClean.includes(targetClean) || item.text.includes(cText);
            });
          });
        }

        if (matchedEgret.length === 0) return false;

        // 优先可交互/带监听器或按钮容器的节点
        const clickables = matchedEgret.filter(item => item.isClickable);
        const candidatePool = clickables.length > 0 ? clickables : matchedEgret;

        const selectionIndex = $selectionIndex;
        let targetIndex = 0;
        if (selectionIndex === 0) {
          targetIndex = Math.floor(Math.random() * candidatePool.length);
        } else if (selectionIndex > 0) {
          targetIndex = Math.min(selectionIndex - 1, candidatePool.length - 1);
        } else {
          targetIndex = Math.max(0, candidatePool.length + selectionIndex);
        }

        const found = candidatePool[targetIndex];
        if (found) {
          return _auokTriggerEgretClick(ctx, found);
        }
        return false;
      }

      // 目标文字判断
      const clickTexts = ($clickTextJson).split(';').map(t => t.trim()).filter(t => t);
      if (clickTexts.length === 0) return false;

      // 出现文字校验（同时检测普通 DOM 文本与 Canvas 白鹭游戏舞台）
      const triggerTexts = ($triggerTextJson).split(';').filter(t => t.trim());
      if (triggerTexts.length > 0) {
        const pageText = document.body.textContent || '';
        let hasText = triggerTexts.some(text => 
          text && pageText.includes(text.trim())
        );
        if (!hasText) {
          const ctx = _auokGetEgretContext();
          if (ctx) {
            const egretNodes = _auokScanEgretNodes(ctx.stage);
            hasText = triggerTexts.some(text =>
              egretNodes.some(n => n.text && n.text.includes(text.trim()))
            );
          }
        }
        if (!hasText) return false;
      }

      // 优先从常见可交互与文本容器节点中检索，避免扫描全量万级无关节点
      const candidateSelectors = 'a, button, input, [role="button"], [onclick], label, span, p, h1, h2, h3, h4, h5, h6, li, td, th, b, strong, em, div';
      const allElements = Array.from(document.querySelectorAll(candidateSelectors));
      
      // Filter by text content
      let matchedLinks = allElements.filter(el => {
        const text = el.innerText || el.textContent || el.value || '';
        const exactMatch = $exactMatch;
        
        return clickTexts.some(cText => {
          if (exactMatch) {
            return text.trim() === cText;
          } else {
            return text.includes(cText);
          }
        });
      });
      
      // 高效剪枝：优先保留最深层匹配节点（避免误点外层大包裹容器）
      if (matchedLinks.length > 1) {
        const leafMatched = [];
        for (let i = 0; i < matchedLinks.length; i++) {
          const el = matchedLinks[i];
          let isContainerOfOther = false;
          for (let j = 0; j < matchedLinks.length; j++) {
            if (i !== j && el.contains(matchedLinks[j])) {
              isContainerOfOther = true;
              break;
            }
          }
          if (!isContainerOfOther) {
            leafMatched.push(el);
          }
        }
        if (leafMatched.length > 0) {
          matchedLinks = leafMatched;
        }
      }

      // Filter by position constraints if specified
      const afterText = ($afterTextJson).trim();
      const beforeText = ($beforeTextJson).trim();
      
      if (afterText || beforeText) {
        matchedLinks = matchedLinks.filter(link => {
          const linkHTML = link.outerHTML;
          const bodyHTML = document.body.innerHTML;
          const linkPosition = bodyHTML.indexOf(linkHTML);
          
          if (linkPosition === -1) return false;
          
          // Check "在此之后" constraint
          if (afterText) {
            const afterPosition = bodyHTML.indexOf(afterText);
            if (afterPosition === -1 || linkPosition <= afterPosition) {
              return false;
            }
          }
          
          // Check "在此之前" constraint
          if (beforeText) {
            const beforePosition = bodyHTML.indexOf(beforeText, linkPosition);
            if (beforePosition === -1) {
              return false;
            }
          }
          
          return true;
        });
      }
      
      // 若常规 DOM 树中未匹配到，自动无感触发 Canvas / 白鹭引擎虚拟穿透探针
      if (matchedLinks.length === 0) {
        return _tryEgretFallback();
      }

      // Apply selection index
      const selectionIndex = $selectionIndex;
      let targetIndex = 0;
      
      if (selectionIndex === 0) {
        // Random selection
        targetIndex = Math.floor(Math.random() * matchedLinks.length);
      } else if (selectionIndex > 0) {
        // Positive index (1-based)
        targetIndex = Math.min(selectionIndex - 1, matchedLinks.length - 1);
      } else {
        // Negative index (-1 means last)
        targetIndex = Math.max(0, matchedLinks.length + selectionIndex);
      }
      
      const targetElement = matchedLinks[targetIndex];
      if (targetElement) {
        _auokHighlight(targetElement);
        _auokSimulateClick(targetElement);
        // 若自身不是链接但父级或祖父级为 <a> 则联动触发
        const anchor = targetElement.closest('a');
        if (anchor && anchor !== targetElement) {
          _auokSimulateClick(anchor);
        }
        return true;
      }
      
      return false;
    ''';
  }

  String _normalizeUrl(String input) {
    var url = input.trim();
    if (url.isEmpty) return '';
    final lower = url.toLowerCase();
    if (lower.startsWith('http://') ||
        lower.startsWith('https://') ||
        lower.startsWith('file://') ||
        lower.startsWith('about:') ||
        lower.startsWith('javascript:') ||
        lower.startsWith('data:') ||
        lower.startsWith('blob:')) {
      return url;
    }
    return 'http://$url';
  }

  Future<bool> _executeNavigate(
      InAppWebViewController controller, Script script) async {
    final rawUrl = script.params['网址'] as String? ?? '';
    final url = _normalizeUrl(rawUrl);
    if (url.isEmpty) return false;

    try {
      await controller.loadUrl(urlRequest: URLRequest(url: WebUri(url)));
      return true;
    } catch (e) {
      debugPrint('Navigate error: $e');
      return false;
    }
  }

  Future<bool> _executeClickImage(
      InAppWebViewController controller, Script script) async {
    final imageSrc = script.params['图片地址'] as String? ?? '';
    final multipleSelection = script.params['多个筛选'] as int? ?? 1;
    final afterText = script.params['在此之后'] as String? ?? '';
    final beforeText = script.params['在此之前'] as String? ?? '';

    final imageSrcJson = jsonEncode(imageSrc);
    final afterTextJson = jsonEncode(afterText);
    final beforeTextJson = jsonEncode(beforeText);

    return await _pollUntilSuccess(() async {
      final result = await controller.evaluateJavascript(source: '''
        (function() {
          $_highlightJs
          try {
            // 1. Find all images
            let images = Array.from(document.querySelectorAll('img'));
            
            // 2. Filter by keyword/src if provided
            const imageKeyword = ($imageSrcJson).toLowerCase();
            if (imageKeyword) {
              images = images.filter(img => {
                const src = (img.src || '').toLowerCase();
                const alt = (img.alt || '').toLowerCase();
                const title = (img.title || '').toLowerCase();
                return src.includes(imageKeyword) || alt.includes(imageKeyword) || title.includes(imageKeyword);
              });
            }
            
            // 3. Filter by position (After/Before)
            const afterText = ($afterTextJson).trim();
            const beforeText = ($beforeTextJson).trim();
            
            if (afterText || beforeText) {
              const bodyHTML = document.body.innerHTML;
              
              images = images.filter(img => {
                const imgHTML = img.outerHTML;
                const imgPosition = bodyHTML.indexOf(imgHTML);
                
                if (imgPosition === -1) return false;
                
                if (afterText) {
                  const afterPosition = bodyHTML.indexOf(afterText);
                  if (afterPosition === -1 || imgPosition <= afterPosition) return false;
                }
                
                if (beforeText) {
                  const beforePosition = bodyHTML.indexOf(beforeText, imgPosition);
                  if (beforePosition === -1) return false;
                }
                
                return true;
              });
            }

            if (images.length === 0) return false;

            // 4. Apply Multiple Selection Logic
            const selectionIndex = $multipleSelection;
            let targetImg = null;

            if (selectionIndex === 0) {
              // Random
              const randomIndex = Math.floor(Math.random() * images.length);
              targetImg = images[randomIndex];
            } else if (selectionIndex > 0) {
              // Positive Index (1-based)
              const index = selectionIndex - 1;
              if (index < images.length) targetImg = images[index];
            } else {
              // Negative Index (-1 means last)
              const index = images.length + selectionIndex;
              if (index >= 0) targetImg = images[index];
            }
            
            if (targetImg) {
              _auokHighlight(targetImg);
              _auokSimulateClick(targetImg);
              // 若自身不是链接但父级为 <a> 则联动仿真触发
              const anchor = targetImg.closest('a');
              if (anchor && anchor !== targetImg) {
                _auokSimulateClick(anchor);
              }
              return true;
            }
            
            return false;
          } catch (e) {
            console.error(e);
            return false;
          }
        })();
      ''');

      return result.toString() == 'true';
    }, timeout: _getStepTimeout(script));
  }

  Future<bool> _executeLogicScriptAppearText(
      InAppWebViewController controller,
      Script script,
      Function(ScriptStatus status, String? message, double? progress)?
          onStatusChanged) async {
    final appearText = script.params['出现文字'] as String? ?? '';
    final afterText = script.params['在此之后'] as String? ?? '';
    final beforeText = script.params['在此之前'] as String? ?? '';
    final trueScriptPath = script.params['出现时执行'] as String?;
    final falseScriptPath = script.params['未出现时执行'] as String?;

    if (appearText.isEmpty) return false;

    final appearTextJson = jsonEncode(appearText);
    final afterTextJson = jsonEncode(afterText);
    final beforeTextJson = jsonEncode(beforeText);

    // Check if text exists with constraints
    final result = await controller.evaluateJavascript(source: '''
      (function() {
        try {
          const targetText = ($appearTextJson).trim();
          if (!targetText) return false;
          
          const bodyHTML = document.body.innerHTML;
          const bodyText = document.body.innerText || document.body.textContent || '';
          
          const afterText = ($afterTextJson).trim();
          const beforeText = ($beforeTextJson).trim();

          // Simple check if no constraints
          if (!afterText && !beforeText) {
            return bodyText.includes(targetText);
          }
          
          let searchStartIndex = 0;
          let searchEndIndex = bodyHTML.length;
          
          if (afterText) {
            const afterIndex = bodyHTML.indexOf(afterText);
            if (afterIndex !== -1) {
              searchStartIndex = afterIndex + afterText.length;
            } else {
              return false;
            }
          }
          
          if (beforeText) {
            const beforeIndex = bodyHTML.indexOf(beforeText, searchStartIndex);
            if (beforeIndex !== -1) {
              searchEndIndex = beforeIndex;
            } else {
              return false;
            }
          }
          
          if (searchStartIndex >= searchEndIndex) return false;
          
          const searchArea = bodyHTML.substring(searchStartIndex, searchEndIndex);
          const tempDiv = document.createElement('div');
          tempDiv.innerHTML = searchArea;
          const searchAreaText = tempDiv.innerText || tempDiv.textContent || '';
          
          return searchAreaText.includes(targetText);
        } catch (e) {
          console.error(e);
          return false;
        }
      })();
    ''');

    final bool exists = result.toString() == 'true';

    if (exists) {
      if (trueScriptPath != null) {
        onStatusChanged?.call(
            ScriptStatus.callSubroutine, trueScriptPath, null);
      }
    } else {
      if (falseScriptPath != null) {
        onStatusChanged?.call(
            ScriptStatus.callSubroutine, falseScriptPath, null);
      }
    }

    return true; // Logic script itself executed successfully
  }

  Future<bool> _executeLogicScriptTimeComparison(
      InAppWebViewController controller,
      Script script,
      Function(ScriptStatus status, String? message, double? progress)?
          onStatusChanged) async {
    final targetTimeStr = script.params['目标值'] as String? ?? '';
    final trueScriptPath = script.params['出现时执行'] as String?; // After Time
    final falseScriptPath = script.params['未出现时执行'] as String?; // Before Time

    if (targetTimeStr.isEmpty) return false;

    try {
      final now = DateTime.now();
      final parts = targetTimeStr.split(':');
      if (parts.length != 3) return false;

      final targetTime = DateTime(
        now.year,
        now.month,
        now.day,
        int.parse(parts[0]),
        int.parse(parts[1]),
        int.parse(parts[2]),
      );

      if (now.isAfter(targetTime)) {
        if (trueScriptPath != null) {
          onStatusChanged?.call(
              ScriptStatus.callSubroutine, trueScriptPath, null);
        }
      } else {
        if (falseScriptPath != null) {
          onStatusChanged?.call(
              ScriptStatus.callSubroutine, falseScriptPath, null);
        }
      }
      return true;
    } catch (e) {
      debugPrint('Time comparison error: $e');
      return false;
    }
  }

  Future<bool> _executeLogicScriptValueComparison(
      InAppWebViewController controller,
      Script script,
      Function(ScriptStatus status, String? message, double? progress)?
          onStatusChanged) async {
    final targetValueStr = script.params['目标值'] as String? ?? '';
    final compareMethod = script.params['对比方式'] as String? ?? '>';
    final multipleSelection = script.params['多个筛选'] as int? ?? 1;
    final afterText = script.params['在此之后'] as String? ?? '';
    final beforeText = script.params['在此之前'] as String? ?? '';
    final trueScriptPath = script.params['出现时执行'] as String?; // Satisfied
    final falseScriptPath = script.params['未出现时执行'] as String?; // Not Satisfied

    if (targetValueStr.isEmpty) return false;
    final targetValue = double.tryParse(targetValueStr);
    if (targetValue == null) return false;

    final afterTextJson = jsonEncode(afterText);
    final beforeTextJson = jsonEncode(beforeText);

    final result = await controller.evaluateJavascript(source: '''
      (function() {
        try {
          const bodyHTML = document.body.innerHTML;
          const afterText = ($afterTextJson).trim();
          const beforeText = ($beforeTextJson).trim();
          
          let searchStartIndex = 0;
          let searchEndIndex = bodyHTML.length;
          
          if (afterText) {
            const afterIndex = bodyHTML.indexOf(afterText);
            if (afterIndex !== -1) {
              searchStartIndex = afterIndex + afterText.length;
            } else {
              return null; // After text not found
            }
          }
          
          if (beforeText) {
            const beforeIndex = bodyHTML.indexOf(beforeText, searchStartIndex);
            if (beforeIndex !== -1) {
              searchEndIndex = beforeIndex;
            } else {
              return null; // Before text not found
            }
          }
          
          if (searchStartIndex >= searchEndIndex) return null;
          
          const searchArea = bodyHTML.substring(searchStartIndex, searchEndIndex);
          
          // Extract numbers from search area
          // This regex matches integers and floats
          const regex = /[-+]?[0-9]*\\.?[0-9]+/g;
          const matches = searchArea.match(regex);
          
          if (!matches || matches.length === 0) return null;
          
          const numbers = matches.map(Number);
          
          // Apply Multiple Selection Logic
          const selectionIndex = $multipleSelection;
          let selectedValue = null;

          if (selectionIndex === 0) {
            // Random
            const randomIndex = Math.floor(Math.random() * numbers.length);
            selectedValue = numbers[randomIndex];
          } else if (selectionIndex > 0) {
            // Positive Index (1-based)
            const index = selectionIndex - 1;
            if (index < numbers.length) selectedValue = numbers[index];
          } else {
            // Negative Index (-1 means last)
            const index = numbers.length + selectionIndex;
            if (index >= 0) selectedValue = numbers[index];
          }
          
          return selectedValue;
        } catch (e) {
          console.error(e);
          return null;
        }
      })();
    ''');

    if (result == null) return false; // No number found

    final extractedValue = double.tryParse(result.toString());
    if (extractedValue == null) return false;

    bool conditionMet = false;
    switch (compareMethod) {
      case '>':
        conditionMet = extractedValue > targetValue;
        break;
      case '<':
        conditionMet = extractedValue < targetValue;
        break;
      case '=':
        conditionMet = (extractedValue - targetValue).abs() < 0.0001;
        break;
      case '>=':
        conditionMet = extractedValue >= targetValue;
        break;
      case '<=':
        conditionMet = extractedValue <= targetValue;
        break;
    }

    if (conditionMet) {
      if (trueScriptPath != null) {
        onStatusChanged?.call(
            ScriptStatus.callSubroutine, trueScriptPath, null);
      }
    } else {
      if (falseScriptPath != null) {
        onStatusChanged?.call(
            ScriptStatus.callSubroutine, falseScriptPath, null);
      }
    }

    return true;
  }

  Future<bool> _executeNewWindowScript(
      Script script,
      Function(ScriptStatus status, String? message, double? progress)?
          onStatusChanged) async {
    try {
      final windowName = script.params['窗口名称'] as String? ?? '';
      final windowUa = script.params['窗口UA'] as String? ?? 'Mobile';
      final rawUrl = script.params['网址'] as String? ?? 'about:blank';
      final url = _normalizeUrl(rawUrl);
      final scriptPath = script.params['脚本集'] as String?;
      final executeImmediately = script.params['立即执行'] as bool? ?? false;

      // Access BrowserProvider via global context or pass it in?
      // Since ScriptExecutor is a service, it might not have direct access to Provider.
      // However, we can use the navigator key to get the context.
      final context = BrowserProvider.navigatorKey.currentContext;
      if (context == null) {
        onStatusChanged?.call(ScriptStatus.failure, '无法获取上下文', null);
        return false;
      }

      final browserProvider =
          Provider.of<BrowserProvider>(context, listen: false);
      final scriptProvider =
          Provider.of<ScriptProvider>(context, listen: false);

      // Create new tab
      await browserProvider.addTab(
        initialUrl: url,
        customName: windowName,
        customUserAgent: windowUa,
      );

      // If script path is provided, load it into the new tab
      if (scriptPath != null && scriptPath.isNotEmpty) {
        final newTab = browserProvider.tabs.last;
        final file = File(scriptPath);
        if (await file.exists()) {
          final content = await file.readAsString();
          final jsonList = jsonDecode(content) as List;
          final newScripts =
              jsonList.map((e) => Script.fromUserMap(e)).toList();
          newTab.scripts = newScripts;
          newTab.scriptFilePath = scriptPath;

          if (executeImmediately) {
            // 异步轮询等待新标签页 WebView 初始化完毕，最长等待 10 秒
            () async {
              int attempts = 0;
              while (newTab.controller == null && attempts < 50) {
                await Future.delayed(const Duration(milliseconds: 200));
                attempts++;
              }
              if (newTab.controller != null) {
                final targetIndex = browserProvider.tabs.indexOf(newTab);
                if (targetIndex != -1) {
                  scriptProvider.startExecution(
                      newTab.controller!, targetIndex);
                }
              }
            }();
          }
        }
      }

      return true;
    } catch (e) {
      debugPrint('New window script error: $e');
      return false;
    }
  }

  Future<bool> _executeJumpScript(
      Script script,
      Function(ScriptStatus status, String? message, double? progress)?
          onStatusChanged) async {
    final targetIndexStr = script.params['跳转的脚本序号']?.toString() ?? '';
    final targetIndex = int.tryParse(targetIndexStr);

    if (targetIndex != null) {
      onStatusChanged?.call(ScriptStatus.jump, targetIndex.toString(), null);
      return true;
    } else {
      onStatusChanged?.call(ScriptStatus.failure, '无效的跳转序号', null);
      return false;
    }
  }

  String _generateStringFromPattern(String pattern) {
    String result = pattern;
    final random = Random();

    // Replace [0-9]{n}
    result = result.replaceAllMapped(RegExp(r'\[0-9\]\{(\d+)\}'), (match) {
      int count = int.parse(match.group(1)!);
      String generated = '';
      for (int i = 0; i < count; i++) {
        generated += random.nextInt(10).toString();
      }
      return generated;
    });

    // Replace [a-z]{n}
    result = result.replaceAllMapped(RegExp(r'\[a-z\]\{(\d+)\}'), (match) {
      int count = int.parse(match.group(1)!);
      return _getRandomString(count, 'abcdefghijklmnopqrstuvwxyz');
    });

    // Replace [A-Z]{n}
    result = result.replaceAllMapped(RegExp(r'\[A-Z\]\{(\d+)\}'), (match) {
      int count = int.parse(match.group(1)!);
      return _getRandomString(count, 'ABCDEFGHIJKLMNOPQRSTUVWXYZ');
    });

    // Replace [a-zA-Z]{n}
    result = result.replaceAllMapped(RegExp(r'\[a-zA-Z\]\{(\d+)\}'), (match) {
      int count = int.parse(match.group(1)!);
      return _getRandomString(
          count, 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ');
    });

    return result;
  }

  String _getRandomString(int length, String chars) {
    final random = Random();
    return String.fromCharCodes(Iterable.generate(
        length, (_) => chars.codeUnitAt(random.nextInt(chars.length))));
  }

  Future<bool> _executeValueComparisonClickText(
      InAppWebViewController controller,
      Script script,
      Function(ScriptStatus status, String? message, double? progress)?
          onStatusChanged) async {
    final params = script.params;
    final clickText = params['点击文本'] ?? '';
    final targetValueStr = params['目标值'] ?? '';
    final compareMethod = params['对比方式'] ?? '>';
    final multipleSelection = params['多个筛选'] as int? ?? 1;
    final afterSearch = params['在此之后'] ?? '';
    final beforeSearch = params['在此之前'] ?? '';

    if (clickText.isEmpty || targetValueStr.isEmpty) {
      onStatusChanged?.call(ScriptStatus.failure, '缺少必要参数', null);
      return false;
    }

    final targetValue = num.tryParse(targetValueStr);
    if (targetValue == null) {
      onStatusChanged?.call(ScriptStatus.failure, '目标值无效', null);
      return false;
    }

    final clickTextJson = jsonEncode(clickText);
    final afterSearchJson = jsonEncode(afterSearch);
    final beforeSearchJson = jsonEncode(beforeSearch);
    final compareMethodJson = jsonEncode(compareMethod);

    // JavaScript logic to find elements, extract value, compare, and click
    final jsCode = '''
      (function() {
        $_highlightJs
        function getElementByXpath(path) {
          return document.evaluate(path, document, null, XPathResult.FIRST_ORDERED_NODE_TYPE, null).singleNodeValue;
        }

        var clickTexts = ($clickTextJson).split(';').map(t => t.trim()).filter(t => t);
        if (clickTexts.length === 0) return "not_found";

        var allElements = Array.from(document.querySelectorAll('*')).filter(el => {
          const tag = el.tagName.toLowerCase();
          return !['html', 'head', 'style', 'script', 'meta', 'link', 'noscript', 'title', 'body'].includes(tag);
        });

        var elements = allElements.filter(el => {
          const text = el.innerText || el.textContent || el.value || '';
          return clickTexts.some(cText => text.includes(cText));
        });

        // Keep only the deepest elements
        elements = elements.filter(el => {
          return !elements.some(otherEl => otherEl !== el && el.contains(otherEl));
        });

        // Filter by 'afterSearch' and 'beforeSearch' if provided
        var afterSearchText = ($afterSearchJson).trim();
        var beforeSearchText = ($beforeSearchJson).trim();

        if (afterSearchText) {
          elements = elements.filter(el => {
            const allNodes = Array.from(document.querySelectorAll('*'));
            const afterNode = allNodes.find(n => (n.innerText || n.textContent || '').includes(afterSearchText));
            if (!afterNode) return false;
            return (el.compareDocumentPosition(afterNode) & Node.DOCUMENT_POSITION_PRECEDING);
          });
        }

        if (beforeSearchText) {
          elements = elements.filter(el => {
            const allNodes = Array.from(document.querySelectorAll('*'));
            const beforeNode = allNodes.find(n => (n.innerText || n.textContent || '').includes(beforeSearchText));
            if (!beforeNode) return false;
            return (el.compareDocumentPosition(beforeNode) & Node.DOCUMENT_POSITION_FOLLOWING);
          });
        }

        if (elements.length === 0) return "not_found";

        // Select specific element based on 'multipleSelection'
        var targetElement = null;
        var selection = $multipleSelection;
        if (selection === 0) {
           // Random
           targetElement = elements[Math.floor(Math.random() * elements.length)];
        } else if (selection > 0) {
           // 1-based index
           if (selection <= elements.length) {
             targetElement = elements[selection - 1];
           }
        } else {
           // Negative index (from end)
           if (Math.abs(selection) <= elements.length) {
             targetElement = elements[elements.length + selection];
           }
        }

        if (!targetElement) return "index_out_of_bounds";

        // Extract value from text (simple regex to find number)
        var text = targetElement.innerText || targetElement.textContent || '';
        var match = text.match(/-?\\d+(\\.\\d+)?/);
        if (!match) return "no_number_found";
        
        var value = parseFloat(match[0]);
        var target = $targetValue;
        var method = $compareMethodJson;
        var result = false;

        switch (method) {
          case '>': result = value > target; break;
          case '<': result = value < target; break;
          case '=': result = value == target; break;
          case '>=': result = value >= target; break;
          case '<=': result = value <= target; break;
        }

        if (result) {
          _auokHighlight(targetElement);
          _auokSimulateClick(targetElement);
          const anchor = targetElement.closest('a');
          if (anchor && anchor !== targetElement) {
            _auokSimulateClick(anchor);
          }
          return "clicked";
        } else {
          return "condition_not_met: " + value;
        }
      })();
    ''';

    final timeout = _getStepTimeout(script);
    String lastResult = 'not_found';

    final success = await _pollUntilSuccess(() async {
      try {
        final result = await controller.evaluateJavascript(source: jsCode);
        lastResult = result?.toString() ?? 'not_found';
        // 若已成功点击，或数值条件判断不满足（属于正常决策分支），均视为判定成功终态！
        if (lastResult == 'clicked' || lastResult.startsWith('condition_not_met')) {
          return true;
        }
        // 若未找到元素或元素中未找到数值（可能处于页面异步渲染中），继续微轮询探测
        return false;
      } catch (e) {
        lastResult = e.toString();
        return false;
      }
    }, timeout: timeout);

    if (success) {
      if (lastResult == 'clicked') {
        onStatusChanged?.call(ScriptStatus.success, '已点击', null);
      } else {
        onStatusChanged?.call(ScriptStatus.success, '条件不满足，未点击 ($lastResult)', null);
      }
      return true;
    } else {
      if (lastResult == 'not_found') {
        onStatusChanged?.call(ScriptStatus.failure, '未找到元素', null);
      } else if (lastResult == 'index_out_of_bounds') {
        onStatusChanged?.call(ScriptStatus.failure, '索引超出范围', null);
      } else if (lastResult == 'no_number_found') {
        onStatusChanged?.call(ScriptStatus.failure, '未在元素中找到数值', null);
      } else {
        onStatusChanged?.call(ScriptStatus.failure, '未知错误: $lastResult', null);
      }
      return false;
    }
  }

  Future<bool> _executeScrollPage(
      InAppWebViewController controller,
      Script script,
      Function(ScriptStatus status, String? message, double? progress)?
          onStatusChanged) async {
    final params = script.params;
    final direction = params['方向'] as String? ?? '向下';
    final distance = params['距离'] as int? ?? 500;
    final directionJson = jsonEncode(direction);

    // 智能双模滚动：同时兼容常规 DOM 网页与白鹭引擎/Canvas 游戏
    final jsCode = '''
      (async function() {
        $_egretCanvasProbeJs
        let scrolled = false;

        // 1. 若探测到白鹭 Canvas 游戏，执行真实 Canvas 多帧连续触摸手势滑动
        const ctx = _auokGetEgretContext();
        if (ctx && ctx.canvas) {
          try {
            await _auokSimulateCanvasSwipe(ctx.canvas, $directionJson, $distance, 350);
            scrolled = true;
          } catch(_) {}
        }

        // 2. 同时执行常规网页窗口 DOM 级滚动
        try {
          const dir = $directionJson;
          const dist = $distance;
          switch (dir) {
            case '向上':
              window.scrollBy({ top: -dist, behavior: 'smooth' });
              break;
            case '向下':
              window.scrollBy({ top: dist, behavior: 'smooth' });
              break;
            case '到顶':
              window.scrollTo({ top: 0, behavior: 'smooth' });
              break;
            case '到底':
              window.scrollTo({ top: document.body.scrollHeight, behavior: 'smooth' });
              break;
            default:
              window.scrollBy({ top: dist, behavior: 'smooth' });
          }
          scrolled = true;
        } catch(_) {}

        return scrolled;
      })();
    ''';

    try {
      final result = await controller.evaluateJavascript(source: jsCode);
      onStatusChanged?.call(ScriptStatus.success, '已执行滑动: $direction ($distance px)', null);
      return result.toString() == 'true';
    } catch (e) {
      debugPrint('Scroll error: $e');
      onStatusChanged?.call(ScriptStatus.failure, '滑动页面异常: $e', null);
      return false;
    }
  }

  Future<bool> _executeWaitForText(
      InAppWebViewController controller,
      Script script,
      Function(ScriptStatus status, String? message, double? progress)?
          onStatusChanged) async {
    final params = script.params;
    final targetText = params['出现文字'] as String? ?? '';
    final timeoutSeconds = params['超时时间'] as int? ?? 10;

    if (targetText.isEmpty) {
      onStatusChanged?.call(ScriptStatus.failure, '未指定等待文字', null);
      return false;
    }

    final targetTextJson = jsonEncode(targetText);
    final totalMs = timeoutSeconds * 1000;
    final stopwatch = Stopwatch()..start();
    int lastReportSec = -1;

    final jsCode = '''
      (function() {
        $_egretCanvasProbeJs
        try {
          const bodyText = document.body.innerText || document.body.textContent || '';
          if (bodyText.includes($targetTextJson)) return true;
          const ctx = _auokGetEgretContext();
          if (ctx) {
            const egretNodes = _auokScanEgretNodes(ctx.stage);
            if (egretNodes && egretNodes.some(n => n.text && n.text.includes($targetTextJson))) {
              return true;
            }
          }
          return false;
        } catch(e) {
          return false;
        }
      })();
    ''';

    while (stopwatch.elapsedMilliseconds < totalMs) {
      final elapsedSec = stopwatch.elapsedMilliseconds ~/ 1000;
      if (elapsedSec != lastReportSec) {
        lastReportSec = elapsedSec;
        double progress = (stopwatch.elapsedMilliseconds / totalMs).clamp(0.0, 1.0);
        onStatusChanged?.call(ScriptStatus.waiting, '等待文字 "$targetText" ($elapsedSec/${timeoutSeconds}s)...', progress);
      }

      try {
        final result = await controller.evaluateJavascript(source: jsCode);
        if (result.toString() == 'true') {
          onStatusChanged?.call(ScriptStatus.success, '文字已出现', 1.0);
          return true;
        }
      } catch (_) {}

      // 极速微轮询：前 500ms 每 40ms 检测一次，之后每 120ms 检测一次，文字就绪毫秒级秒过
      final delay = stopwatch.elapsedMilliseconds < 500 ? 40 : 120;
      await Future.delayed(Duration(milliseconds: delay));
    }

    onStatusChanged?.call(ScriptStatus.failure, '等待超时，文字未出现', null);
    return false;
  }

  Future<bool> _executeExtractText(
      InAppWebViewController controller,
      Script script,
      Function(ScriptStatus status, String? message, double? progress)?
          onStatusChanged,
      {Map<String, String>? variables}) async {
    final params = script.params;
    final selector = params['CSS选择器'] as String? ?? '';
    final attribute =
        params['属性'] as String? ?? 'text'; // 'text', 'html', or attribute name

    if (selector.isEmpty) {
      onStatusChanged?.call(ScriptStatus.failure, '未指定CSS选择器', null);
      return false;
    }

    final selectorJson = jsonEncode(selector);
    final attributeJson = jsonEncode(attribute);

    final jsCode = '''
      (function() {
        try {
          const el = document.querySelector($selectorJson);
          if (!el) return null;
          
          const attr = $attributeJson;
          if (attr === "text") {
            return el.innerText || el.textContent;
          } else if (attr === "html") {
            return el.innerHTML;
          } else {
            return el.getAttribute(attr);
          }
        } catch(e) {
          return null;
        }
      })();
    ''';

    final timeout = _getStepTimeout(script);
    String? extractedValue;

    // 智能微轮询：支持在异步组件渲染期间持续探测，提取到内容瞬间立即返回
    final success = await _pollUntilSuccess(() async {
      try {
        final result = await controller.evaluateJavascript(source: jsCode);
        if (result != null) {
          extractedValue = result.toString();
          return true;
        }
        return false;
      } catch (_) {
        return false;
      }
    }, timeout: timeout);

    if (success && extractedValue != null) {
      final varName = params['变量名'] as String? ??
          params['保存至变量'] as String? ??
          '';
      if (varName.isNotEmpty && variables != null) {
        variables[varName] = extractedValue!;
        onStatusChanged?.call(
            ScriptStatus.notification, '提取成功: \$$varName = $extractedValue', null);
      } else {
        onStatusChanged?.call(
            ScriptStatus.notification, '提取结果: $extractedValue', null);
      }
      return true;
    } else {
      onStatusChanged?.call(ScriptStatus.failure, '未找到元素或属性为空', null);
      return false;
    }
  }

  /// 递归解析脚本参数中的动态变量引用（将 ${varName} 替换为对应值）
  Script _resolveVariables(Script original, Map<String, String>? vars) {
    if (vars == null || vars.isEmpty) return original;
    final newParams = <String, dynamic>{};
    original.params.forEach((key, value) {
      newParams[key] = _replaceVarInValue(value, vars);
    });
    return Script(
      type: original.type,
      params: newParams,
      isEnabled: original.isEnabled,
      status: original.status,
      statusMessage: original.statusMessage,
      progress: original.progress,
    );
  }

  dynamic _replaceVarInValue(dynamic val, Map<String, String> vars) {
    if (val is String) {
      String str = val;
      vars.forEach((k, v) {
        str = str.replaceAll('\${$k}', v).replaceAll('\$$k', v);
      });
      return str;
    } else if (val is Map) {
      return val.map((k, v) => MapEntry(k, _replaceVarInValue(v, vars)));
    } else if (val is List) {
      return val.map((e) => _replaceVarInValue(e, vars)).toList();
    }
    return val;
  }

  @visibleForTesting
  String buildClickScriptLogic(Map<String, dynamic> params) =>
      _buildClickScriptLogic(params);

  @visibleForTesting
  Script resolveVariables(Script original, Map<String, String>? vars) =>
      _resolveVariables(original, vars);
}
