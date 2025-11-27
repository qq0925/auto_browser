import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/script_provider.dart';

class ScriptRecordingOverlay extends StatelessWidget {
  const ScriptRecordingOverlay({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<ScriptProvider>(
      builder: (context, provider, child) {
        if (!provider.isRecording) return const SizedBox.shrink();

        return Positioned(
          left: 16,
          bottom: 80, // Above bottom bar
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.7),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Blinking red dot
                const _BlinkingRedDot(),
                const SizedBox(width: 8),
                const Text(
                  '录制中...',
                  style: TextStyle(color: Colors.white, fontSize: 14),
                ),
                const SizedBox(width: 8),
                GestureDetector(
                  onTap: () {
                    provider.stopRecording();
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('录制已结束')),
                    );
                  },
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: const BoxDecoration(
                      color: Colors.white24,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.close,
                      color: Colors.white,
                      size: 16,
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _BlinkingRedDot extends StatefulWidget {
  const _BlinkingRedDot();

  @override
  State<_BlinkingRedDot> createState() => _BlinkingRedDotState();
}

class _BlinkingRedDotState extends State<_BlinkingRedDot>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 1000),
      vsync: this,
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _controller,
      child: Container(
        width: 10,
        height: 10,
        decoration: const BoxDecoration(
          color: Colors.red,
          shape: BoxShape.circle,
        ),
      ),
    );
  }
}
