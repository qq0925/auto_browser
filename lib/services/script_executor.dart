import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter/foundation.dart' show debugPrint;
import '../models/script.dart';
import 'dart:convert';
import 'dart:async';
import 'dart:math';

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

      // Execute "Before" Script
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
          return true; // Return true to indicate successful execution of the "stop" command itself
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
          // Delay is handled by the common logic at the beginning of the loop
          return true;

        default:
          result = true;
          break;
      }

      // Execute "After" Script
      if (script.params['执行每个脚本后执行'] != null) {
        final afterScriptMap = script.params['执行每个脚本后执行'];
        if (afterScriptMap is Map<String, dynamic>) {
          final afterScript = Script.fromUserMap(afterScriptMap);
          await execute(controller, afterScript, executionDelay: executionDelay,
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

    final result = await controller.evaluateJavascript(source: '''
      (function() {
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
              input.value = value;
              input.dispatchEvent(new Event('input', { bubbles: true }));
              input.dispatchEvent(new Event('change', { bubbles: true }));
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
              submitBtn.click();
              return true;
            } else if (targetForm) {
              // If no button found but form found, try submit()
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
      
      // Target text to click
      const clickText = "${params['点击文本'] ?? ''}".trim();
      if (!clickText) return false;

      // Get all links/buttons/clickable elements
      // We prioritize 'a' tags but also check buttons and inputs
      const allElements = Array.from(document.querySelectorAll('a, button, input[type="submit"], input[type="button"], div[role="button"], span[role="button"]'));
      
      // Filter by text content
      let matchedLinks = allElements.filter(el => {
        const text = el.innerText || el.textContent || el.value || '';
        const exactMatch = ${params['完全匹配'] ?? false};
        if (exactMatch) {
          return text.trim() === clickText;
        } else {
          return text.includes(clickText);
        }
      });

      // Filter by position constraints if specified
      const afterText = "${params['在此之后'] ?? ''}".trim();
      const beforeText = "${params['在此之前'] ?? ''}".trim();
      
      if (afterText || beforeText) {
        matchedLinks = matchedLinks.filter(link => {
          const linkHTML = link.outerHTML;
          const bodyHTML = document.body.innerHTML;
          // Use a more robust way to find position if possible, but innerHTML index is a reasonable fallback for now
          // Note: This is simple string matching on HTML, which can be brittle if HTML structure changes dynamically
          // A better approach would be traversing the DOM tree, but that's complex to implement in a single injected script.
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
            // Find the last occurrence of beforeText that is BEFORE the link? 
            // Or just any occurrence? Usually "Before X" means the link appears before X.
            // So we need to find an X that is > linkPosition.
            const beforePosition = bodyHTML.indexOf(beforeText, linkPosition);
             if (beforePosition === -1) {
               // Try searching from beginning if not found after
               // But strictly "Before Search" usually implies the search text is further down the page
               return false;
             }
          }
          
          return true;
        });
      }
      
      if (matchedLinks.length === 0) return false;

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
      
      const targetElement = matchedLinks[targetIndex];
      if (targetElement) {
        targetElement.click();
        return true;
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
}
