import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/browser_provider.dart';
import '../providers/script_provider.dart';

/// 侧边栏收起时的极简悬浮运行胶囊
class FloatingCapsule extends StatefulWidget {
  const FloatingCapsule({super.key});

  @override
  State<FloatingCapsule> createState() => _FloatingCapsuleState();
}

class _FloatingCapsuleState extends State<FloatingCapsule>
    with SingleTickerProviderStateMixin {
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);

    _pulseAnimation = Tween<double>(begin: 0.85, end: 1.0).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Consumer2<BrowserProvider, ScriptProvider>(
      builder: (context, browser, scriptProvider, child) {
        // 仅在“脚本正在运行”且“右侧面板收起”时显示
        if (!scriptProvider.isExecuting || browser.isScriptPanelExpanded) {
          return const SizedBox.shrink();
        }

        final currentTab = browser.currentTab;
        final totalScripts = currentTab?.scripts.length ?? 0;
        final currentIndex = scriptProvider.currentScriptIndex;
        final remainingLoops = scriptProvider.remainingLoopCount;
        final isPaused = scriptProvider.isPaused;

        String stepName = '自动化执行中';
        if (currentTab != null &&
            currentIndex >= 0 &&
            currentIndex < totalScripts) {
          final s = currentTab.scripts[currentIndex];
          final customName = s.params['脚本名称'] as String?;
          stepName = (customName != null && customName.isNotEmpty)
              ? customName
              : s.type;
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
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
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
                            '步骤 ${currentIndex + 1}/$totalScripts · 循环 $remainingLoops',
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
      },
    );
  }
}
