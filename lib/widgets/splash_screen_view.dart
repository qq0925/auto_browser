import 'package:flutter/material.dart';

/// 具有电影级科技质感与流光呼吸动效的启动动画屏
class SplashScreenView extends StatefulWidget {
  final bool isStarting;

  const SplashScreenView({
    super.key,
    required this.isStarting,
  });

  @override
  State<SplashScreenView> createState() => _SplashScreenViewState();
}

class _SplashScreenViewState extends State<SplashScreenView>
    with TickerProviderStateMixin {
  late final AnimationController _introController;
  late final AnimationController _pulseController;
  late final AnimationController _statusController;

  // 入场动画序列
  late final Animation<double> _logoScale;
  late final Animation<double> _logoOpacity;
  late final Animation<Offset> _titleSlide;
  late final Animation<double> _titleOpacity;
  late final Animation<double> _subtitleOpacity;
  late final Animation<double> _loaderOpacity;

  // 呼吸与悬浮动画
  late final Animation<double> _floatingY;
  late final Animation<double> _haloGlow;
  late final Animation<double> _auroraScale;

  int _statusTextIndex = 0;
  static const List<String> _statusTexts = [
    '正在载入智能自动化引擎...',
    '配置工作空间与环境...',
    '自动化引擎就绪',
  ];

  @override
  void initState() {
    super.initState();

    // 1. 入场过渡控制器 (1100ms)
    _introController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    );

    _logoScale = Tween<double>(begin: 0.72, end: 1.0).animate(
      CurvedAnimation(
        parent: _introController,
        curve: const Interval(0.0, 0.75, curve: Curves.easeOutBack),
      ),
    );

    _logoOpacity = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _introController,
        curve: const Interval(0.0, 0.5, curve: Curves.easeOut),
      ),
    );

    _titleSlide = Tween<Offset>(
      begin: const Offset(0, 0.35),
      end: Offset.zero,
    ).animate(
      CurvedAnimation(
        parent: _introController,
        curve: const Interval(0.3, 0.85, curve: Curves.easeOutCubic),
      ),
    );

    _titleOpacity = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _introController,
        curve: const Interval(0.3, 0.75, curve: Curves.easeOut),
      ),
    );

    _subtitleOpacity = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _introController,
        curve: const Interval(0.5, 0.9, curve: Curves.easeOut),
      ),
    );

    _loaderOpacity = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _introController,
        curve: const Interval(0.68, 1.0, curve: Curves.easeOut),
      ),
    );

    // 2. 持续呼吸、微光晕与浮动控制器 (2400ms，双向往复)
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2400),
    );

    _floatingY = Tween<double>(begin: -4.0, end: 4.0).animate(
      CurvedAnimation(
        parent: _pulseController,
        curve: Curves.easeInOutSine,
      ),
    );

    _haloGlow = Tween<double>(begin: 24.0, end: 46.0).animate(
      CurvedAnimation(
        parent: _pulseController,
        curve: Curves.easeInOut,
      ),
    );

    _auroraScale = Tween<double>(begin: 0.92, end: 1.15).animate(
      CurvedAnimation(
        parent: _pulseController,
        curve: Curves.easeInOutSine,
      ),
    );

    // 3. 状态文字轮播控制器
    _statusController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );

    _introController.forward();
    _pulseController.repeat(reverse: true);
    _startStatusRotation();
  }

  void _startStatusRotation() async {
    while (mounted) {
      await Future.delayed(const Duration(milliseconds: 950));
      if (!mounted) break;
      await _statusController.forward();
      if (!mounted) break;
      setState(() {
        _statusTextIndex = (_statusTextIndex + 1) % _statusTexts.length;
      });
      _statusController.reverse();
    }
  }

  @override
  void dispose() {
    _introController.dispose();
    _pulseController.dispose();
    _statusController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      height: double.infinity,
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(0xFF0F172A), // 深邃星夜暗蓝
            Color(0xFF080D1A),
            Color(0xFF030712), // 极境黑
          ],
        ),
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          // 1. 顶部呼吸流动极光晕
          AnimatedBuilder(
            animation: _auroraScale,
            builder: (context, child) {
              return Positioned(
                top: -120,
                child: Transform.scale(
                  scale: _auroraScale.value,
                  child: Container(
                    width: 360,
                    height: 360,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: RadialGradient(
                        colors: [
                          const Color(0xFF38BDF8).withValues(alpha: 0.16),
                          const Color(0xFF2563EB).withValues(alpha: 0.08),
                          Colors.transparent,
                        ],
                      ),
                    ),
                  ),
                ),
              );
            },
          ),

          // 2. 右下方次极光晕（双色互补光）
          AnimatedBuilder(
            animation: _auroraScale,
            builder: (context, child) {
              return Positioned(
                bottom: -80,
                right: -60,
                child: Transform.scale(
                  scale: 2.0 - _auroraScale.value,
                  child: Container(
                    width: 280,
                    height: 280,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: RadialGradient(
                        colors: [
                          const Color(0xFF6366F1).withValues(alpha: 0.14),
                          const Color(0xFF0EA5E9).withValues(alpha: 0.06),
                          Colors.transparent,
                        ],
                      ),
                    ),
                  ),
                ),
              );
            },
          ),

          // 3. 中心品牌展示区域
          AnimatedBuilder(
            animation: Listenable.merge([_introController, _pulseController]),
            builder: (context, child) {
              return Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Logo 容器 (支持弹动入场 + 上下悬浮 + 动态呼吸光晕)
                  Transform.translate(
                    offset: Offset(0, _floatingY.value),
                    child: Transform.scale(
                      scale: _logoScale.value,
                      child: Opacity(
                        opacity: _logoOpacity.value,
                        child: Container(
                          width: 96,
                          height: 96,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(26),
                            boxShadow: [
                              // 外层动态呼吸霓虹光环
                              BoxShadow(
                                color: const Color(0xFF38BDF8).withValues(alpha: 0.42),
                                blurRadius: _haloGlow.value,
                                spreadRadius: (_haloGlow.value - 24.0) / 4.0,
                                offset: const Offset(0, 4),
                              ),
                              // 底层立体深阴影
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.75),
                                blurRadius: 20,
                                offset: const Offset(0, 10),
                              ),
                            ],
                            border: Border.all(
                              color: Colors.white.withValues(alpha: 0.22),
                              width: 1.5,
                            ),
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(24.5),
                            child: Image.asset(
                              'assets/app_icon.png',
                              fit: BoxFit.cover,
                              errorBuilder: (context, error, stackTrace) =>
                                  Container(
                                color: const Color(0xFF1E293B),
                                child: const Icon(
                                  Icons.rocket_launch_rounded,
                                  size: 46,
                                  color: Color(0xFF38BDF8),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 30),

                  // 品牌主标题 (平滑上浮 + 渐变微光)
                  SlideTransition(
                    position: _titleSlide,
                    child: FadeTransition(
                      opacity: _titleOpacity,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              Text(
                                'Auok',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 30,
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: 3.0,
                                  shadows: [
                                    Shadow(
                                      color: const Color(0xFF38BDF8).withValues(alpha: 0.5),
                                      blurRadius: 18,
                                      offset: const Offset(0, 2),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 8),
                              // 胶囊徽章 (PRO / 极速)
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  gradient: const LinearGradient(
                                    colors: [Color(0xFF2563EB), Color(0xFF0284C7)],
                                  ),
                                  borderRadius: BorderRadius.circular(6),
                                  boxShadow: [
                                    BoxShadow(
                                      color: const Color(0xFF2563EB).withValues(alpha: 0.4),
                                      blurRadius: 8,
                                    ),
                                  ],
                                ),
                                child: const Text(
                                  'PRO',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 9.5,
                                    fontWeight: FontWeight.bold,
                                    letterSpacing: 1.0,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),

                          // 品牌副标
                          FadeTransition(
                            opacity: _subtitleOpacity,
                            child: Text(
                              '智能自动化极速浏览器',
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.65),
                                fontSize: 13,
                                letterSpacing: 2.2,
                                fontWeight: FontWeight.w400,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 42),

                  // 极光能量条与就绪状态指示器
                  FadeTransition(
                    opacity: _loaderOpacity,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // 高科技能量流线加载条
                        Container(
                          width: 120,
                          height: 3.5,
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.08),
                            borderRadius: BorderRadius.circular(3),
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(3),
                            child: const LinearProgressIndicator(
                              backgroundColor: Colors.transparent,
                              valueColor: AlwaysStoppedAnimation<Color>(
                                Color(0xFF38BDF8), // 霓虹天青蓝
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 14),

                        // 动态微动状态轮播文字
                        AnimatedBuilder(
                          animation: _statusController,
                          builder: (context, child) {
                            return Opacity(
                              opacity: 1.0 - _statusController.value,
                              child: Text(
                                _statusTexts[_statusTextIndex],
                                style: TextStyle(
                                  color: Colors.white.withValues(alpha: 0.45),
                                  fontSize: 11,
                                  letterSpacing: 1.0,
                                ),
                              ),
                            );
                          },
                        ),
                      ],
                    ),
                  ),
                ],
              );
            },
          ),

          // 4. 底部极简版号与理念署名
          Positioned(
            bottom: 36,
            child: FadeTransition(
              opacity: _subtitleOpacity,
              child: Text(
                'FAST · AUTOMATED · PRIVACY',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.28),
                  fontSize: 10,
                  letterSpacing: 2.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
