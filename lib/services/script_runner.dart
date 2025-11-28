import 'dart:async';
import 'package:flutter/foundation.dart';

import '../models/script.dart';
import '../models/browser_tab.dart';
import 'script_executor.dart';

class ScriptRunner extends ChangeNotifier {
  final BrowserTab tab;
  final ScriptExecutor _executor = ScriptExecutor();

  bool _isPaused = false;
  bool _stopRequested = false;

  bool get isPaused => _isPaused;

  ScriptRunner(this.tab);

  Future<void> start(Future<void> Function()? waitForPageLoadCallback) async {
    if (tab.scripts.isEmpty || tab.isExecutingScript) return;

    tab.isExecutingScript = true;
    _isPaused = false;
    _stopRequested = false;
    tab.currentScriptIndex = 0;
    tab.remainingLoopCount = tab.originalLoopCount;
    tab.successCount = 0;
    tab.failureCount = 0;

    // Reset script statuses
    for (var script in tab.scripts) {
      script.status = ScriptStatus.idle;
      script.statusMessage = null;
      script.progress = null;
    }
    notifyListeners();

    try {
      while (tab.remainingLoopCount > 0 && !_stopRequested) {
        for (var i = 0; i < tab.scripts.length; i++) {
          if (_stopRequested) break;

          // Handle pause
          while (_isPaused && !_stopRequested) {
            await Future.delayed(const Duration(milliseconds: 100));
          }

          if (_stopRequested) break;

          tab.currentScriptIndex = i;
          notifyListeners();

          final script = tab.scripts[i];
          if (script.isEnabled) {
            await _executor.execute(
              tab.controller,
              script,
              executionDelay: tab.executionDelay,
              onStatusChanged: (status, message, progress) {
                script.status = status;
                script.statusMessage = message;
                script.progress = progress;

                if (status == ScriptStatus.success) {
                  tab.successCount++;
                } else if (status == ScriptStatus.failure) {
                  tab.failureCount++;
                }
                notifyListeners();
              },
              waitForPageLoad: waitForPageLoadCallback,
            );
          }
        }

        if (!_stopRequested) {
          tab.remainingLoopCount--;
          notifyListeners();
        }
      }
    } catch (e) {
      debugPrint('Script execution error: $e');
    } finally {
      tab.isExecutingScript = false;
      tab.currentScriptIndex = 0;
      _stopRequested = false;
      _isPaused = false;
      notifyListeners();
    }
  }

  void stop() {
    _stopRequested = true;
    _isPaused = false; // Break out of pause loop
    notifyListeners();
  }

  void pause() {
    _isPaused = true;
    notifyListeners();
  }

  void resume() {
    _isPaused = false;
    notifyListeners();
  }
}
