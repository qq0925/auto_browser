import 'package:webview_flutter/webview_flutter.dart';
import '../models/script.dart';
import 'dart:convert';
import 'dart:async';

class ScriptExecutor {
  // Execute a script on the given controller
  Future<bool> execute(WebViewController controller, Script script,
      {int executionDelay = 1000,
      Function(ScriptStatus status, String? message)? onStatusChanged}) async {
    if (!script.isEnabled) return false;

    onStatusChanged?.call(ScriptStatus.running, null);

    final repeatCount = script.params['重复次数'] ?? 1;
    bool success = true;

    for (var i = 0; i < repeatCount; i++) {
      bool result = false;

      // Update status for repetition if needed
      if (repeatCount > 1) {
        onStatusChanged?.call(
            ScriptStatus.running, '正在执行第 ${i + 1}/$repeatCount 次');
      }

      // 1. Wait for Page Load
      onStatusChanged?.call(ScriptStatus.waiting, '等待网页加载...');
      await _waitForPageLoad(controller);

      // 2. Wait for Execution Delay (Global or Script-specific)
      // Note: Script-specific delay logic was inside _executeClickScript,
      // but user requested "Wait for page load AND delay before execution".
      // So we should probably move the delay here or ensure it's additive.
      // For now, I will add the global delay here if it's passed as executionDelay.
      // Script specific delay is handled inside specific methods or we can unify it.
      // The user said: "执行每个脚本前是不是要等网页加载完成并且自身执行延迟过后（如果自身没有延迟的用全局执行延迟）才执行？"
      // So: Wait Page Load -> Wait Delay (Self or Global) -> Execute.

      int delay = executionDelay;
      if (script.params.containsKey('执行延迟')) {
        // If script has specific delay, use it.
        // Note: params['执行延迟'] might be int.
        delay = script.params['执行延迟'] is int
            ? script.params['执行延迟']
            : executionDelay;
      }

      if (delay > 0) {
        onStatusChanged?.call(ScriptStatus.waiting, '等待延迟 ${delay}ms...');
        await Future.delayed(Duration(milliseconds: delay));
      }

      onStatusChanged?.call(ScriptStatus.running, '正在执行...');

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
        case "点击图片":
          // Simple image click logic
          result = await _executeImageClick(controller);
          break;
        case "网页后退":
          await controller.goBack();
          result = true;
          break;
        case "网页前进":
          await controller.goForward();
          result = true;
          break;
        case "刷新网页":
          await controller.reload();
          result = true;
          break;
        default:
          result = true;
          break;
      }

      if (!result) {
        success = false;
        onStatusChanged?.call(ScriptStatus.failure, '执行失败');
        break;
      }

      // If not the last repetition, wait for the delay (loop delay?)
      // User didn't specify loop delay, but usually loop has delay.
      // The "executionDelay" parameter in execute() is usually the global delay.
      // If we already waited before execution, do we wait after?
      // Usually "Interval" between scripts is handled by the provider loop.
      // This loop is for "Repeat Count" of a SINGLE script.
      if (i < repeatCount - 1) {
        onStatusChanged?.call(ScriptStatus.waiting, '等待下次执行...');
        await Future.delayed(Duration(milliseconds: executionDelay));
      }
    }

    if (success) {
      onStatusChanged?.call(ScriptStatus.success, null);
    }

    return success;
  }

  Future<void> _waitForPageLoad(WebViewController controller) async {
    int maxRetries = 30; // 30 seconds max wait
    for (int i = 0; i < maxRetries; i++) {
      final String readyState = await controller
          .runJavaScriptReturningResult("document.readyState") as String;
      // readyState returns '"complete"' (with quotes) from runJavaScriptReturningResult
      if (readyState.contains('complete')) {
        return;
      }
      await Future.delayed(const Duration(milliseconds: 1000));
    }
  }

  Future<bool> _executeImageClick(WebViewController controller) async {
    // Logic to click the first image or specific image?
    // For now, let's try to click the first image that looks clickable or just any image.
    // Or maybe we recorded specific image details?
    // The current recording only records "点击图片", no details.
    // So we'll try to click the first image.
    final result = await controller.runJavaScriptReturningResult('''
      (function() {
        const images = document.querySelectorAll('img');
        if (images.length > 0) {
          images[0].click();
          return true;
        }
        return false;
      })();
    ''');
    return result.toString() == 'true';
  }

  Future<bool> _executeIntervalScript(
      WebViewController controller,
      Script script,
      Function(ScriptStatus status, String? message)? onStatusChanged) async {
    final params = script.params;
    final h = params['时间间隔-小时'] ?? 0;
    final m = params['时间间隔-分钟'] ?? 0;
    final s = params['时间间隔-秒'] ?? 0;

    int totalSeconds = h * 3600 + m * 60 + s;
    if (totalSeconds <= 0) return true;

    for (var i = totalSeconds; i > 0; i--) {
      onStatusChanged?.call(ScriptStatus.waiting, '等待延迟 ${i}s');
      await Future.delayed(const Duration(seconds: 1));
    }

    return true;
  }

  Future<bool> _executeClickScript(
      WebViewController controller, Script script) async {
    final params = script.getClickParams();
    final clickText = params['点击文本'] ?? '';
    if (clickText.isEmpty) return false;

    // Handle delay for non-simple modes
    if (script.mode != ScriptMode.simple) {
      final delay = params['执行延迟'] ?? 0;
      final timeUnit = params['时间单位'] ?? '毫秒';
      final multiplier = TimeUnit.values
          .firstWhere(
            (unit) => unit.label == timeUnit,
            orElse: () => TimeUnit.milliseconds,
          )
          .multiplier;

      await Future.delayed(Duration(milliseconds: delay * multiplier));
    }

    final result = await controller.runJavaScriptReturningResult('''
      (function() {
        ${_buildClickScriptLogic(script.mode, params)}
      })();
    ''');

    return result.toString() == 'true';
  }

  Future<bool> _executeFormSubmit(
      WebViewController controller, Script script) async {
    final params = script.params;
    if (params.isEmpty) return false;

    final jsonParams = jsonEncode(params);

    final result = await controller.runJavaScriptReturningResult('''
      (function() {
        try {
          const data = $jsonParams;
          const inputs = Array.from(document.querySelectorAll('input:not([type="hidden"]):not([type="submit"]), textarea'))
            .filter(input => {
              const rect = input.getBoundingClientRect();
              return rect.width > 0 && rect.height > 0;
            });
            
          let filledCount = 0;
          
          inputs.forEach((input, index) => {
            const key = '输入框' + (index + 1);
            if (data[key]) {
              input.value = data[key];
              input.dispatchEvent(new Event('input', { bubbles: true }));
              input.dispatchEvent(new Event('change', { bubbles: true }));
              filledCount++;
            }
          });
          
          if (filledCount > 0) {
            const submitBtn = document.querySelector('input[type="submit"], button[type="submit"]');
            if (submitBtn) {
              submitBtn.click();
              return true;
            }
            
            // Try form submit if no button found
            const form = inputs[0].form;
            if (form) {
              form.submit();
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

  String _buildClickScriptLogic(ScriptMode mode, Map<String, dynamic> params) {
    switch (mode) {
      case ScriptMode.simple:
        return '''
          const text = "${params['点击文本']}";
          const links = Array.from(document.querySelectorAll('a')).filter(a => 
            a.textContent.trim() === text.trim()
          );
          if (links.length > 0) {
            links[0].click();
            return true;
          }
          return false;
        ''';

      case ScriptMode.normal:
        return '''
          const triggerTexts = "${params['出现文字'] ?? ''}".split(';').filter(t => t.trim());
          if (triggerTexts.length > 0) {
            const pageText = document.body.textContent;
            const hasText = triggerTexts.some(text => 
              text && pageText.includes(text.trim())
            );
            if (!hasText) return false;
          }
          
          const clickTexts = "${params['点击文本']}".split(';').filter(t => t.trim());
          const isExactMatch = ${params['完全匹配'] ? 'true' : 'false'};
          
          for (const text of clickTexts) {
            const links = Array.from(document.querySelectorAll('a')).filter(a => {
              const linkText = a.textContent.trim();
              return isExactMatch ? linkText === text.trim() : linkText.includes(text.trim());
            });
            
            if (links.length > 0) {
              links[0].click();
              return true;
            }
          }
          return false;
        ''';

      case ScriptMode.expert:
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
              
              return true;
            });
          }
          
          // Filter by click text
          const clickTexts = "${params['点击文本']}".split(';').filter(t => t.trim());
          const isExactMatch = ${params['完全匹配'] ? 'true' : 'false'};
          
          for (const text of clickTexts) {
            const matchedLinks = candidateLinks.filter(a => {
              const linkText = a.textContent.trim();
              return isExactMatch ? linkText === text.trim() : linkText.includes(text.trim());
            });
            
            if (matchedLinks.length > 0) {
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
  }
}
