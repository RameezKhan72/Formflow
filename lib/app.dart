import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/theme.dart';
import 'features/onboarding/auth_screen.dart';
import 'features/onboarding/onboarding_screen.dart';
import 'features/onboarding/setup_screen.dart';
import 'features/shell/home_shell.dart';
import 'state/app_state.dart';
import 'widgets/common.dart';

class FormFlowApp extends StatelessWidget {
  final bool showSplash;
  const FormFlowApp({super.key, this.showSplash = true});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'FormFlow',
      debugShowCheckedModeBanner: false,
      theme: FF.theme(),
      darkTheme: FF.theme(),
      themeMode: ThemeMode.dark,
      home: RootGate(showSplash: showSplash),
    );
  }
}

/// Splash -> onboarding -> sign in -> setup -> tabs (FR-AU-01).
class RootGate extends ConsumerStatefulWidget {
  final bool showSplash;
  const RootGate({super.key, this.showSplash = true});

  @override
  ConsumerState<RootGate> createState() => _RootGateState();
}

class _RootGateState extends ConsumerState<RootGate> {
  late bool _splash = widget.showSplash;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    if (_splash) {
      _timer = Timer(const Duration(milliseconds: 2200), () {
        if (mounted) setState(() => _splash = false);
      });
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final app = ref.watch(appProvider);
    final d = app.data;
    Widget child;
    if (_splash) {
      child = const SplashScreen(key: ValueKey('splash'));
    } else if (!d.onboarded) {
      child = const OnboardingScreen(key: ValueKey('onboarding'));
    } else if (!d.signedIn) {
      child = const AuthScreen(key: ValueKey('auth'));
    } else if (d.benchmarkMs == null) {
      child = const SetupScreen(key: ValueKey('setup'));
    } else {
      child = const HomeShell(key: ValueKey('home'));
    }
    return AnimatedSwitcher(duration: const Duration(milliseconds: 300), child: child);
  }
}

/// Animated launch screen (doc item 2): a moving gym-themed background
/// (drifting equipment icons, glowing energy orbs and a heartbeat line)
/// behind the FormFlow logo.
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(seconds: 6))..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(fit: StackFit.expand, children: [
        GymBackground(animation: _c),
        Center(
          child: TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: 1),
            duration: const Duration(milliseconds: 1100),
            curve: Curves.easeOutBack,
            builder: (context, v, child) => Opacity(
              opacity: v.clamp(0.0, 1.0).toDouble(),
              child: Transform.scale(scale: 0.7 + 0.3 * v, child: child),
            ),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(34),
                  boxShadow: [BoxShadow(color: FF.accent.withValues(alpha: 0.55), blurRadius: 40, spreadRadius: 2)],
                ),
                child: const AppLogoMark(size: 120),
              ),
              const SizedBox(height: 22),
              const FormFlowLogo(size: 38),
              const SizedBox(height: 8),
              const Text('Your AI form coach', style: TextStyle(color: FF.muted, fontSize: 15)),
              const SizedBox(height: 28),
              SizedBox(
                width: 140,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: const LinearProgressIndicator(minHeight: 4, color: FF.accent, backgroundColor: FF.surface2),
                ),
              ),
            ]),
          ),
        ),
      ]),
    );
  }
}

/// Gym-themed animated background, also used behind onboarding.
class GymBackground extends StatelessWidget {
  final Animation<double> animation;
  const GymBackground({super.key, required this.animation});

  static const _icons = [
    Icons.fitness_center,
    Icons.sports_gymnastics,
    Icons.directions_run,
    Icons.monitor_heart_outlined,
    Icons.self_improvement,
    Icons.sports_martial_arts,
    Icons.timer_outlined,
    Icons.local_fire_department_outlined,
  ];

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: animation,
      builder: (context, _) {
        final t = animation.value;
        return LayoutBuilder(builder: (context, c) {
          final w = c.maxWidth, h = c.maxHeight;
          return Stack(fit: StackFit.expand, children: [
            CustomPaint(painter: _EnergyPainter(t)),
            for (var i = 0; i < 14; i++)
              Positioned(
                left: ((i * 0.37 + 0.08 * math.sin(t * 2 * math.pi + i)) % 1.0) * (w - 40),
                top: (((i * 0.61) - t * (0.6 + (i % 3) * 0.2)) % 1.0) * (h + 60) - 30,
                child: Transform.rotate(
                  angle: math.sin(t * 2 * math.pi + i) * 0.5,
                  child: Icon(
                    _icons[i % _icons.length],
                    size: 22.0 + (i % 4) * 9,
                    color: Colors.white.withValues(alpha: 0.05 + (i % 3) * 0.025),
                  ),
                ),
              ),
          ]);
        });
      },
    );
  }
}

class _EnergyPainter extends CustomPainter {
  final double t;
  _EnergyPainter(this.t);

  @override
  void paint(Canvas canvas, Size size) {
    final r = Offset.zero & size;
    canvas.drawRect(
      r,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF0B0F24), Color(0xFF141A44), Color(0xFF0A0D1F)],
        ).createShader(r),
    );
    final a = t * 2 * math.pi;
    void orb(double cx, double cy, double rad, Color c) {
      final o = Offset(cx * size.width, cy * size.height);
      canvas.drawCircle(
        o,
        rad * size.width,
        Paint()
          ..shader = RadialGradient(colors: [c.withValues(alpha: 0.35), c.withValues(alpha: 0)])
              .createShader(Rect.fromCircle(center: o, radius: rad * size.width)),
      );
    }

    orb(0.2 + 0.08 * math.sin(a), 0.25 + 0.05 * math.cos(a), 0.7, const Color(0xFF7C5CFF));
    orb(0.85 + 0.06 * math.cos(a * 1.3), 0.7 + 0.06 * math.sin(a), 0.65, const Color(0xFF288CFF));
    orb(0.5, 1.05 + 0.04 * math.sin(a * 2), 0.6, const Color(0xFFFF6B4A));
    // heartbeat line sweeping across
    final y = size.height * 0.78;
    final path = Path()..moveTo(0, y);
    const beats = [0.0, 0.0, 0.0, -0.4, 0.9, -1.0, 0.2, 0.0, 0.0];
    final period = size.width / 2;
    for (double x = 0; x <= size.width; x += 4) {
      final ph = ((x / period) - t * 2) % 1.0;
      final i = (ph * (beats.length - 1)).floor().clamp(0, beats.length - 2).toInt();
      final f = ph * (beats.length - 1) - i;
      final v = beats[i] + (beats[i + 1] - beats[i]) * f;
      path.lineTo(x, y - v * 26);
    }
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = FF.accent.withValues(alpha: 0.35),
    );
  }

  @override
  bool shouldRepaint(covariant _EnergyPainter old) => old.t != t;
}
