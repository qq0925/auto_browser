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

class ScriptExecutor {
  // Execute a script on the given controller
  // Execute a script on the given controller
  Future<bool> execute(InAppWebViewController controller, Script script,
      {int executionDelay = 1000,
      Function(ScriptStatus status, String? message, double? progress)?
          onStatusChanged,
      Future<void> Function()? waitForPageLoad,
      List<Script>? scripts}) async {
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

        case "控制脚本开关":
          if (scripts != null) {
            final indicesStr = script.params['脚本序号'] as String?;
            final action = script.params['开关动作'] as String?; // '禁用', '启用', '反相'

            if (indicesStr != null && action != null) {
              final indices = indicesStr
                  .split(' ')
                  .map((e) => int.tryParse(e))
                  .where((e) => e != null)
                  .cast<int>()
                  .toList();

              for (var index in indices) {
                // User input is 1-based, convert to 0-based
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
          result = await _executeLogicScriptAppearText(
              controller, script, onStatusChanged);
          break;

        case "逻辑脚本-时间对比":
          result = await _executeLogicScriptTimeComparison(
              controller, script, onStatusChanged);
          break;

        case "逻辑脚本-数值对比":
          result = await _executeLogicScriptValueComparison(
              controller, script, onStatusChanged);
          break;

        case "新建窗口并执行脚本":
          result = await _executeNewWindowScript(script, onStatusChanged);
          break;

        case "跳转脚本":
          result = await _executeJumpScript(script, onStatusChanged);
          break;

        case "数值对比-点击文字":
          result = await _executeValueComparisonClickText(
              controller, script, onStatusChanged);
          break;

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

    if (params['间隔时间后执行脚本'] != null) {
      final scriptPath = params['间隔时间后执行脚本'] as String;
      if (scriptPath.isNotEmpty) {
        onStatusChanged?.call(ScriptStatus.callSubroutine, scriptPath, null);
      }
    }

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
    final jsContent = script.params['js内容'] ?? script.params['代码'] ?? '';
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

      // Get all reasonable elements
      const allElements = Array.from(document.querySelectorAll('*')).filter(el => {
        const tag = el.tagName.toLowerCase();
        return !['html', 'head', 'style', 'script', 'meta', 'link', 'noscript', 'title', 'body'].includes(tag);
      });
      
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
      
      // Keep only the deepest elements to avoid clicking large container wrappers
      matchedLinks = matchedLinks.filter(el => {
          return !matchedLinks.some(otherEl => otherEl !== el && el.contains(otherEl));
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
    var url = script.params['网址'] as String? ?? '';
    if (url.isNotEmpty &&
        !url.startsWith('http://') &&
        !url.startsWith('https://') &&
        !url.startsWith('about:')) {
      url = 'http://$url';
    }
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

    // If no specific image src, click first clickable image
    final result = await controller.evaluateJavascript(source: '''
      (function() {
        try {
          // 1. Find all images
          let images = Array.from(document.querySelectorAll('img'));
          
          // 2. Filter by keyword/src if provided
          if ('$imageSrc') {
            const keyword = '$imageSrc'.toLowerCase();
            images = images.filter(img => {
              const src = (img.src || '').toLowerCase();
              const alt = (img.alt || '').toLowerCase();
              const title = (img.title || '').toLowerCase();
              return src.includes(keyword) || alt.includes(keyword) || title.includes(keyword);
            });
          }
          
          // 3. Filter by position (After/Before)
          const afterText = "$afterText".trim();
          const beforeText = "$beforeText".trim();
          
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
            targetImg.click();
            // Also try clicking parent if image itself isn't clickable but parent is anchor
            if (!targetImg.onclick && targetImg.parentElement && targetImg.parentElement.tagName === 'A') {
              targetImg.parentElement.click();
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

    // Check if text exists with constraints
    final result = await controller.evaluateJavascript(source: '''
      (function() {
        try {
          const targetText = "$appearText".trim();
          if (!targetText) return false;
          
          const bodyHTML = document.body.innerHTML;
          const bodyText = document.body.innerText || document.body.textContent;
          
          // Simple check if no constraints
          if (!"$afterText" && !"$beforeText") {
            return bodyText.includes(targetText);
          }
          
          // Constraint check
          const afterText = "$afterText".trim();
          const beforeText = "$beforeText".trim();
          
          // We need to find the target text position
          // This is a simplified check using indexOf on HTML/Text
          // For more complex DOM traversal, we'd need a TreeWalker
          
          let searchStartIndex = 0;
          let searchEndIndex = bodyHTML.length;
          
          if (afterText) {
            const afterIndex = bodyHTML.indexOf(afterText);
            if (afterIndex !== -1) {
              searchStartIndex = afterIndex + afterText.length;
            } else {
              // After text not found, so condition fails
              return false;
            }
          }
          
          if (beforeText) {
            const beforeIndex = bodyHTML.indexOf(beforeText, searchStartIndex);
            if (beforeIndex !== -1) {
              searchEndIndex = beforeIndex;
            } else {
              // Before text not found after start index
              return false;
            }
          }
          
          if (searchStartIndex >= searchEndIndex) return false;
          
          const searchArea = bodyHTML.substring(searchStartIndex, searchEndIndex);
          // Remove tags to check text content? Or check HTML?
          // "Appear Text" usually implies visible text.
          // Let's try to strip tags or just check includes for now.
          // Stripping tags is safer for "Text" check.
          const tempDiv = document.createElement('div');
          tempDiv.innerHTML = searchArea;
          const searchAreaText = tempDiv.innerText || tempDiv.textContent;
          
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

    final result = await controller.evaluateJavascript(source: '''
      (function() {
        try {
          const bodyHTML = document.body.innerHTML;
          const afterText = "$afterText".trim();
          const beforeText = "$beforeText".trim();
          
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
      var url = script.params['网址'] as String? ?? 'about:blank';
      if (url != 'about:blank' &&
          !url.startsWith('http://') &&
          !url.startsWith('https://')) {
        url = 'http://$url';
      }
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
            // Trigger execution on the new tab
            // We need to wait a bit for the tab to be ready?
            // startExecution takes controller, which is set in onWebViewCreated.
            // So we might need to wait for controller to be available.
            // But startExecution is usually called from UI.
            // Here we are calling it programmatically.

            // We can't easily wait for controller here without blocking.
            // But we can set a flag or try to execute after a short delay.
            Future.delayed(const Duration(seconds: 1), () {
              if (newTab.controller != null) {
                scriptProvider.startExecution(
                    newTab.controller!, browserProvider.tabs.length - 1);
              } else {
                // Retry once more
                Future.delayed(const Duration(seconds: 2), () {
                  if (newTab.controller != null) {
                    scriptProvider.startExecution(
                        newTab.controller!, browserProvider.tabs.length - 1);
                  }
                });
              }
            });
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
    final targetIndexStr = script.params['跳转的脚本序号'] as String? ?? '';
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

    // JavaScript logic to find elements, extract value, compare, and click
    final jsCode = '''
      (function() {
        function getElementByXpath(path) {
          return document.evaluate(path, document, null, XPathResult.FIRST_ORDERED_NODE_TYPE, null).singleNodeValue;
        }

        function getAllElementsByXpath(path) {
          var result = document.evaluate(path, document, null, XPathResult.ORDERED_NODE_SNAPSHOT_TYPE, null);
          var nodes = [];
          for (var i = 0; i < result.snapshotLength; i++) {
            nodes.push(result.snapshotItem(i));
          }
          return nodes;
        }

        var allElements = Array.from(document.querySelectorAll('*')).filter(el => {
          const tag = el.tagName.toLowerCase();
          return !['html', 'head', 'style', 'script', 'meta', 'link', 'noscript', 'title', 'body'].includes(tag);
        });

        var elements = allElements.filter(el => {
          const text = el.innerText || el.textContent || el.value || '';
          return text.includes("$clickText");
        });

        // Keep only the deepest elements
        elements = elements.filter(el => {
          return !elements.some(otherEl => otherEl !== el && el.contains(otherEl));
        });

        // Filter by 'afterSearch' and 'beforeSearch' if provided
        if ("$afterSearch" !== "") {
           var afterNode = getElementByXpath("//*[contains(text(), '" + "$afterSearch" + "')]");
           if (afterNode) {
             elements = elements.filter(el => {
               return (el.compareDocumentPosition(afterNode) & Node.DOCUMENT_POSITION_PRECEDING);
             });
           }
        }

        if ("$beforeSearch" !== "") {
           var beforeNode = getElementByXpath("//*[contains(text(), '" + "$beforeSearch" + "')]");
           if (beforeNode) {
             elements = elements.filter(el => {
               return (el.compareDocumentPosition(beforeNode) & Node.DOCUMENT_POSITION_FOLLOWING);
             });
           }
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
        var text = targetElement.innerText || targetElement.textContent;
        var match = text.match(/-?\\d+(\\.\\d+)?/);
        if (!match) return "no_number_found";
        
        var value = parseFloat(match[0]);
        var target = $targetValue;
        var method = "$compareMethod";
        var result = false;

        switch (method) {
          case '>': result = value > target; break;
          case '<': result = value < target; break;
          case '=': result = value == target; break;
          case '>=': result = value >= target; break;
          case '<=': result = value <= target; break;
        }

        if (result) {
          targetElement.click();
          return "clicked";
        } else {
          return "condition_not_met: " + value;
        }
      })();
    ''';

    final result = await controller.evaluateJavascript(source: jsCode);

    if (result == 'clicked') {
      onStatusChanged?.call(ScriptStatus.success, '已点击', null);
      return true;
    } else if (result == 'not_found') {
      onStatusChanged?.call(ScriptStatus.failure, '未找到元素', null);
      return false;
    } else if (result == 'index_out_of_bounds') {
      onStatusChanged?.call(ScriptStatus.failure, '索引超出范围', null);
      return false;
    } else if (result == 'no_number_found') {
      onStatusChanged?.call(ScriptStatus.failure, '未在元素中找到数值', null);
      return false;
    } else if (result.toString().startsWith('condition_not_met')) {
      onStatusChanged?.call(ScriptStatus.success, '条件不满足，未点击 ($result)', null);
      return true; // Execution successful, just condition not met
    } else {
      onStatusChanged?.call(ScriptStatus.failure, '未知错误: $result', null);
      return false;
    }
  }
}
