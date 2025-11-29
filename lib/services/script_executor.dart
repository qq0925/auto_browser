import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter/foundation.dart' show debugPrint;
import '../models/script.dart';
import 'dart:convert';
import 'dart:async';

class ScriptExecutor {
  // Execute a script on the given controller
  Future<bool> execute(InAppWebViewController controller, Script script,
      {int executionDelay = 1000,
      Function(ScriptStatus status, String? message, double? progress)?
          onStatusChanged,
      Future<void> Function()? waitForPageLoad}) async {
    if (!script.isEnabled) return false;

    final repeatCount = script.params['重复次数'] ?? 1;
    bool success = true;

    for (var i = 0; i < repeatCount; i++) {
      // 1. Wait for page load
      if (waitForPageLoad != null) {
        onStatusChanged?.call(ScriptStatus.waiting, '等待网页加载...', null);
        await waitForPageLoad();
      }

      // 2. Wait for delay (Script specific or Global)
      // If script has its own delay, use it, otherwise use global executionDelay
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

      // Update status for repetition if needed
      if (repeatCount > 1) {
        onStatusChanged?.call(
            ScriptStatus.running, '正在执行第 ${i + 1}/$repeatCount 次', null);
      }

      // Execute "Before" Script
      if (script.params['执行每个脚本前执行'] != null) {
        final beforeScriptMap = script.params['执行每个脚本前执行'];
        if (beforeScriptMap is Map<String, dynamic>) {
          final beforeScript = Script.fromUserMap(beforeScriptMap);
          // Execute recursively, but maybe without delay/wait to keep it tight?
          // Or just standard execute. Let's use standard execute but maybe 0 delay default?
          // User might want delay in before script too.
          await execute(controller, beforeScript,
              executionDelay:
                  0, // Nested scripts might not inherit global delay by default?
              onStatusChanged: (status, msg, prog) {
            // Optional: bubble up status or ignore?
            // For now, let's just log or ignore to keep main status clean
            if (status == ScriptStatus.failure) {
              debugPrint('Before script failed: $msg');
            }
          });
        }
      }

      switch (script.type) {
        case "点击文字":
          result = await _executeClickScript(controller, script);
          break;
        case "输入框提交":
          result = await _executeFormSubmit(controller, script);
          break;
        case "间隔时间":
          result =
              await _executeIntervalScript(controller, script, onStatusChanged);
          break;
        case "自定义JS":
          result = await _executeCustomJs(controller, script);
          break;
        case "进入网址":
          result = await _executeNavigate(controller, script);
          break;
        case "点击图片":
          result = await _executeClickImage(controller, script);
          break;
        case "刷新网页":
          await controller.reload();
          result = true;
          break;
        case "网页后退":
          result = await controller.canGoBack();
          if (result) await controller.goBack();
          break;
        case "网页前进":
          result = await controller.canGoForward();
          if (result) await controller.goForward();
          break;
        case "脚本停止":
          onStatusChanged?.call(ScriptStatus.stopped, '脚本已停止', null);
          result = true;
          break;
        case "脚本暂停":
          onStatusChanged?.call(ScriptStatus.paused, '脚本已暂停', null);
          result = true;
          break;
        default:
          // For other scripts, assume success for now or implement specific logic
          // Some scripts like '脚本停止' might be handled outside or just return true
          result = true;
          break;
      }

      // Execute "After" Script
      if (script.params['执行每个脚本后执行'] != null) {
        final afterScriptMap = script.params['执行每个脚本后执行'];
        if (afterScriptMap is Map<String, dynamic>) {
          final afterScript = Script.fromUserMap(afterScriptMap);
          await execute(controller, afterScript, executionDelay: 0,
              onStatusChanged: (status, msg, prog) {
            if (status == ScriptStatus.failure) {
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

      // If not the last repetition, we might want a small delay or just continue
      // The requirement says "wait for page load and delay BEFORE execution",
      // so we handled it at the start of the loop.
      // We don't need an extra delay here unless it's specifically for repetition interval.
      // But for now, let's stick to the "Before Execution" rule.
    }

    if (success) {
      onStatusChanged?.call(ScriptStatus.success, null, 1.0);
    }

    return success;
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

    return true;
  }

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

    final result = await controller.evaluateJavascript(source: '''
      (function() {
        ${_buildClickScriptLogic(params)}
      })();
    ''');

    return result.toString() == 'true';
  }

  Future<bool> _executeFormSubmit(
      InAppWebViewController controller, Script script) async {
    final params = script.params;
    if (params.isEmpty) return false;

    // Get formData map and button text
    final formData = params['表单数据'] as Map<String, dynamic>? ?? {};
    final buttonText = params['提交按钮文字'] as String? ?? '提交';

    if (formData.isEmpty) return false;

    final jsonFormData = jsonEncode(formData);
    final jsonButtonText = jsonEncode(buttonText);

    final result = await controller.evaluateJavascript(source: '''
      (function() {
        try {
          const formData = $jsonFormData;
          const buttonText = $jsonButtonText;
          let filledCount = 0;
          
          for (const [fieldName, value] of Object.entries(formData)) {
            let input = document.querySelector("[name='" + fieldName + "']") || 
                       document.querySelector("#" + fieldName);
            
            if (input && input.type !== 'hidden' && input.type !== 'submit') {
              input.value = value;
              input.dispatchEvent(new Event('input', { bubbles: true }));
              input.dispatchEvent(new Event('change', { bubbles: true }));
              filledCount++;
            }
          }
          
          if (filledCount > 0) {
            let submitBtn = null;
            const buttons = Array.from(document.querySelectorAll('button, input[type="submit"]'));
            submitBtn = buttons.find(btn => {
              const text = btn.innerText || btn.textContent || btn.value || '';
              return text.trim() === buttonText;
            });
            
            if (!submitBtn) {
              submitBtn = document.querySelector('input[type="submit"], button[type="submit"]');
            }
            
            if (submitBtn) {
              submitBtn.click();
              return true;
            }
            
            const firstFieldName = Object.keys(formData)[0];
            const firstInput = document.querySelector("[name='" + firstFieldName + "']");
            if (firstInput && firstInput.form) {
              firstInput.form.submit();
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
  }

  Future<bool> _executeCustomJs(
      InAppWebViewController controller, Script script) async {
    final jsContent = script.params['js内容'] ?? '';
    if (jsContent.isEmpty) return true; // Empty script considered success

    try {
      // Wrap in try-catch block to prevent crashing
      final result = await controller.evaluateJavascript(source: '''
        (function() {
          try {
            $jsContent
            return true;
          } catch (e) {
            console.error('Custom JS execution error:', e);
            return false;
          }
        })();
      ''');
      return result.toString() == 'true';
    } catch (e) {
      return false;
    }
  }

  String _buildClickScriptLogic(Map<String, dynamic> params) {
    // Unified logic: Always use Expert Mode features with Fuzzy Matching
    return '''
      const triggerTexts = "${params['出现文字'] ?? ''}".split(';').filter(t => t.trim());
      if (triggerTexts.length > 0) {
        const pageText = document.body.textContent;
        const hasText = triggerTexts.some(text => 
          text && pageText.includes(text.trim())
        );
        if (!hasText) return false;
      }
      
      // Get all links in the document
      const allLinks = Array.from(document.querySelectorAll('a'));
      
      // Filter by position constraints if specified
      const afterText = "${params['在此之后'] ?? ''}".trim();
      const beforeText = "${params['在此之前'] ?? ''}".trim();
      
      let candidateLinks = allLinks;
      
      if (afterText || beforeText) {
        candidateLinks = allLinks.filter(link => {
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
            const beforePosition = bodyHTML.lastIndexOf(beforeText, linkPosition);
            if (beforePosition === -1) {
              // If beforeText not found before this link, check if it exists after
              const beforePositionAfter = bodyHTML.indexOf(beforeText, linkPosition);
              if (beforePositionAfter === -1 || beforePositionAfter <= linkPosition) {
                return false;
              }
            }
          }
          
          // Apply selection index
          const selectionIndex = ${params['多个筛选'] ?? 1};
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
          
          matchedLinks[targetIndex].click();
          return true;
        }
      }
      
      return false;
    ''';
  }

  Future<bool> _executeNavigate(
      InAppWebViewController controller, Script script) async {
    final url = script.params['网址'] as String? ?? '';
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

    // If no specific image src, click first clickable image
    final result = await controller.evaluateJavascript(source: '''
      (function() {
        try {
          let img = null;
          
          if ('$imageSrc') {
            // Find image by src
            img = document.querySelector('img[src*="$imageSrc"]');
          }
          
          if (!img) {
            // Find first clickable image (with link or onclick)
            const images = Array.from(document.querySelectorAll('img'));
            img = images.find(i => i.onclick || i.parentElement.tagName === 'A');
          }
          
          if (!img) {
            // Last resort: click first image
            img = document.querySelector('img');
          }
          
          if (img) {
            img.click();
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
  }
}
