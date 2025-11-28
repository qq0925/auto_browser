import 'dart:async';
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
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _RecordedActionNotification(
                actionStream: provider.lastRecordedActionStream,
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
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
            ],
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

class _RecordedActionNotification extends StatefulWidget {
  final Stream<String> actionStream;

  const _RecordedActionNotification({required this.actionStream});

  @override
  State<_RecordedActionNotification> createState() =>
      _RecordedActionNotificationState();
}

class _RecordedActionNotificationState
    extends State<_RecordedActionNotification>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<Offset> _offsetAnimation;
  String _currentAction = '';
  Timer? _hideTimer;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );

    _offsetAnimation = Tween<Offset>(
      begin: const Offset(-1.0, 0.0),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOut,
    ));

    widget.actionStream.listen((action) {
      if (mounted) {
        setState(() {
          _currentAction = action;
        });
        _controller.forward();
        _hideTimer?.cancel();
        _hideTimer = Timer(const Duration(seconds: 2), () {
          if (mounted) {
            _controller.reverse();
          }
        });
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    _hideTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SlideTransition(
      position: _offsetAnimation,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.blue.withValues(alpha: 0.8),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.check_circle, color: Colors.white, size: 16),
            const SizedBox(width: 8),
            Text(
              '已录制: $_currentAction',
              style: const TextStyle(color: Colors.white, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }
}
