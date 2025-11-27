import 'package:webview_flutter/webview_flutter.dart';
import '../models/script.dart';
import 'dart:convert';
import 'dart:async';

class ScriptExecutor {
  // Execute a script on the given controller
  Future<bool> execute(WebViewController controller, Script script,
      {int executionDelay = 1000}) async {
    if (!script.isEnabled) return false;

    final repeatCount = script.params['重复次数'] ?? 1;
    bool success = true;

    for (var i = 0; i < repeatCount; i++) {
      bool result = false;
      switch (script.type) {
        case "点击文字":
          result = await _executeClickScript(controller, script);
          break;
        case "输入框提交":
          result = await _executeFormSubmit(controller, script);
          break;
      }

      if (!result) {
        success = false;
        break;
      }

      // If not the last repetition, wait for the delay
      if (i < repeatCount - 1) {
        await Future.delayed(Duration(milliseconds: executionDelay));
      }
    }

    return success;
  }

  Future<bool> _executeClickScript(
      WebViewController controller, Script script) async {
    final params = script.getClickParams();
    final clickText = params['点击文字'] ?? '';
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
          const text = "${params['点击文字']}";
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
          
          const clickTexts = "${params['点击文字']}".split(';').filter(t => t.trim());
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
          const clickTexts = "${params['点击文字']}".split(';').filter(t => t.trim());
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
