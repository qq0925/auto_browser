import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/browser_provider.dart';
import '../providers/script_provider.dart';

/// 侧边栏收起时的极简悬浮运行胶囊
/// 仅在可见时才挂载内部的呼吸动画控制器，隐藏状态零 Ticker 耗帧
class FloatingCapsule extends StatelessWidget {
  const FloatingCapsule({super.key});

  @override
  Widget build(BuildContext context) {
    final isPanelExpanded =
        context.select<BrowserProvider, bool>((b) => b.isScriptPanelExpanded);
    final isExecutingOrPaused = context.select<ScriptProvider, bool>(
        (s) => s.isExecuting || s.isPaused);

    if (!isExecutingOrPaused || isPanelExpanded) {
      return const SizedBox.shrink();
    }
    return const _ActiveFloatingCapsule();
  }
}

class _ActiveFloatingCapsule extends StatefulWidget {
  const _ActiveFloatingCapsule();

  @override
  State<_ActiveFloatingCapsule> createState() => _ActiveFloatingCapsuleState();
}

class _ActiveFloatingCapsuleState extends State<_ActiveFloatingCapsule>
    with SingleTickerProviderStateMixin {
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;
  bool _isAnimating = false;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );
    _pulseAnimation = Tween<double>(begin: 0.85, end: 1.0).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
  }

  void _syncAnimation(bool shouldAnimate) {
    if (shouldAnimate == _isAnimating) return;
    _isAnimating = shouldAnimate;
    if (shouldAnimate) {
      _pulseController.repeat(reverse: true);
    } else {
      _pulseController.stop();
      _pulseController.value = 1.0;
    }
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final browser = context.watch<BrowserProvider>();
    final scriptProvider = context.watch<ScriptProvider>();
    final isPaused = scriptProvider.isPaused;
    _syncAnimation(!isPaused);

    final currentTab = browser.currentTab;
    final totalScripts = currentTab?.scripts.length ?? 0;
    final currentIndex = scriptProvider.currentScriptIndex;
    final loopText = currentTab?.completedLoopProgressText ??
        scriptProvider.completedLoopProgressText;

    String stepName = '自动化执行中';
    if (currentTab != null &&
        currentIndex >= 0 &&
        currentIndex < totalScripts) {
      final s = currentTab.scripts[currentIndex];
      final customName = s.params['脚本名称'] as String?;
      stepName =
          (customName != null && customName.isNotEmpty) ? customName : s.type;
    }

    return Positioned(
      top: 60,
      right: 12,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(30),
          onTap: () {
            // 点击胶囊展开脚本侧边栏
            browser.toggleScriptPanel();
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            constraints: const BoxConstraints(maxWidth: 240),
            decoration: BoxDecoration(
              color: const Color(0xEE1E232A),
              borderRadius: BorderRadius.circular(30),
              border: Border.all(
                color: isPaused
                    ? Colors.amber.withValues(alpha: 0.5)
                    : Colors.blueAccent.withValues(alpha: 0.5),
                width: 1.2,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.35),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                // 状态呼吸动画图标
                ScaleTransition(
                  scale: isPaused
                      ? const AlwaysStoppedAnimation(1.0)
                      : _pulseAnimation,
                  child: Icon(
                    isPaused ? Icons.pause_circle_filled : Icons.play_circle_fill,
                    color: isPaused ? Colors.amber : Colors.greenAccent,
                    size: 18,
                  ),
                ),
                const SizedBox(width: 8),

                // 文字状态
                Flexible(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        '${currentTab?.executionMode ?? scriptProvider.executionMode} · 步骤 ${currentIndex + 1}/$totalScripts · 循环 $loopText',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        stepName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.7),
                          fontSize: 10,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 6),

                // 快捷控制：暂停/恢复
                InkWell(
                  borderRadius: BorderRadius.circular(16),
                  onTap: () {
                    if (isPaused) {
                      scriptProvider.resumeExecution();
                    } else {
                      scriptProvider.pauseExecution();
                    }
                  },
                  child: Padding(
                    padding: const EdgeInsets.all(4.0),
                    child: Icon(
                      isPaused ? Icons.play_arrow : Icons.pause,
                      color: Colors.white70,
                      size: 16,
                    ),
                  ),
                ),

                // 快捷控制：停止
                InkWell(
                  borderRadius: BorderRadius.circular(16),
                  onTap: () {
                    scriptProvider.stopExecution();
                  },
                  child: const Padding(
                    padding: EdgeInsets.all(4.0),
                    child: Icon(
                      Icons.stop,
                      color: Colors.redAccent,
                      size: 16,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
