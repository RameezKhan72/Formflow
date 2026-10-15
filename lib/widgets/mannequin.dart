import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../core/theme.dart';
import '../domain/demo_motion.dart';
import '../domain/exercise.dart';
import '../domain/geometry.dart';

/// Draws the 2D mannequin (asset A3) with worked muscles glowing in
/// proportion to movement depth (FR-DM-03) and props (FR-DM-04).
class MannequinPainter extends CustomPainter {
  final MannequinPose pose;
  final Map<String, double> muscles;
  final double glow; // 0..1
  final List<String> props;
  final bool floor;
  final bool pulse;
  final double pulseT;

  MannequinPainter({
    required this.pose,
    required this.muscles,
    required this.glow,
    this.props = const [],
    this.floor = true,
    this.pulse = false,
    this.pulseT = 0,
  });

  static const _body = Color(0xFFD9DDEF);
  static const _bodyFar = Color(0xFF8189B3);

  double _w(List<String> ids) => ids.fold(0.0, (a, m) => a + (muscles[m] ?? 0));

  @override
  void paint(Canvas canvas, Size size) {
    final s = math.min(size.width, size.height);
    final ox = (size.width - s) / 2, oy = (size.height - s) / 2;
    Offset o(Vec2 v) => Offset(ox + v.x * s, oy + v.y * s);
    final k = pose.scale;
    final j = pose.j;
    final floorY = oy + MannequinDims.floorY * s;

    if (floor && !props.contains('bar')) {
      if (pulse) {
        final r = s * (0.18 + 0.03 * math.sin(pulseT * 2 * math.pi));
        final cx = o(j['ankle']!).dx;
        canvas.drawOval(
          Rect.fromCenter(center: Offset(cx, floorY + 2), width: r * 2, height: r * 0.45),
          Paint()
            ..color = FF.accent.withValues(alpha: 0.28)
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
        );
      }
      canvas.drawLine(Offset(ox + s * 0.04, floorY), Offset(ox + s * 0.96, floorY),
          Paint()
            ..color = const Color(0xFF3A4170)
            ..strokeWidth = 2);
    }

    _props(canvas, s, o, j);

    final intensity = 0.35 + 0.65 * glow;
    void seg(String a, String b, double width, Color c, double muscleW) {
      final pa = j[a], pb = j[b];
      if (pa == null || pb == null) return;
      final p = Paint()
        ..color = c
        ..strokeWidth = width * s * k
        ..strokeCap = StrokeCap.round;
      canvas.drawLine(o(pa), o(pb), p);
      if (muscleW > 0.01) {
        final g = Paint()
          ..color = FF.muscle.withValues(alpha: (muscleW * 2.4).clamp(0.0, 0.95) * intensity)
          ..strokeWidth = width * s * k * 0.78
          ..strokeCap = StrokeCap.round;
        canvas.drawLine(o(pa), o(pb), g);
      }
    }

    final legW = _w(['quads', 'hamstrings']) + _w(['glutes']) * 0.5;
    final shinW = _w(['calves']);
    final upperW = _w(['biceps', 'triceps']) + _w(['shoulders']) * 0.4;
    final foreW = _w(['forearms']);
    final torsoW = _w(['chest', 'abs', 'obliques', 'lats', 'traps', 'lower_back']);
    final far = pose.front ? _body : _bodyFar;

    // far limbs first
    seg(pose.front ? 'hip2' : 'hip', 'knee2', 0.058, far, legW);
    seg('knee2', 'ankle2', 0.046, far, shinW);
    seg('heel2', 'toe2', 0.026, far, 0);
    seg(pose.front ? 'shoulder2' : 'shoulder', 'elbow2', 0.04, far, upperW);
    seg('elbow2', 'wrist2', 0.034, far, foreW);

    // torso, neck, head
    if (pose.front) {
      final shL = o(j['shoulder']!), shR = o(j['shoulder2']!);
      final hipL = o(j['hip']!), hipR = o(j['hip2']!);
      final torso = Path()
        ..moveTo(shL.dx + 0.02 * s, shL.dy - 0.01 * s)
        ..lineTo(shR.dx - 0.02 * s, shR.dy - 0.01 * s)
        ..lineTo(hipR.dx - 0.025 * s, hipR.dy + 0.02 * s)
        ..lineTo(hipL.dx + 0.025 * s, hipL.dy + 0.02 * s)
        ..close();
      canvas.drawPath(torso, Paint()..color = _body);
      if (torsoW > 0.01) {
        canvas.drawPath(torso, Paint()..color = FF.muscle.withValues(alpha: (torsoW * 2).clamp(0.0, 0.9) * intensity));
      }
    } else {
      seg('hip', 'shoulder', 0.1, _body, torsoW);
    }
    seg('shoulder', 'neck', 0.045, _body, 0);
    final head = j['head']!;
    canvas.drawCircle(o(head), MannequinDims.headR * s * k, Paint()..color = _body);

    // near limbs
    seg('hip', 'knee', 0.066, _body, legW);
    seg('knee', 'ankle', 0.05, _body, shinW);
    seg('heel', 'toe', 0.03, _body, 0);
    seg('shoulder', 'elbow', 0.046, _body, upperW);
    seg('elbow', 'wrist', 0.038, _body, foreW);

    // joint accents: deltoid and glute glow
    final sh = _w(['shoulders']);
    if (sh > 0.05) {
      canvas.drawCircle(o(j['shoulder']!), 0.035 * s * k,
          Paint()..color = FF.muscle.withValues(alpha: (sh * 1.6).clamp(0.0, 0.9) * intensity));
    }
    final gl = _w(['glutes']);
    if (gl > 0.05 && !pose.front) {
      canvas.drawCircle(o(j['hip']!), 0.04 * s * k,
          Paint()..color = FF.muscle.withValues(alpha: (gl * 1.6).clamp(0.0, 0.9) * intensity));
    }
    _handProps(canvas, s, o, j);
  }

  void _props(Canvas canvas, double s, Offset Function(Vec2) o, Map<String, Vec2> j) {
    final prop = Paint()..color = const Color(0xFF5A6299);
    if (props.contains('wall')) {
      final x = o(j['hip']!).dx - 0.06 * s;
      canvas.drawRect(Rect.fromLTRB(x - 0.05 * s, s * 0.08, x, o(const Vec2(0, MannequinDims.floorY)).dy), prop);
    }
    if (props.contains('bench')) {
      final w = o(j['wrist']!);
      canvas.drawRRect(
          RRect.fromRectAndRadius(Rect.fromLTRB(w.dx - 0.3 * s, w.dy + 0.012 * s, w.dx + 0.03 * s, w.dy + 0.05 * s),
              Radius.circular(0.01 * s)),
          prop);
      final floorY = o(const Vec2(0, MannequinDims.floorY)).dy;
      canvas.drawRect(Rect.fromLTRB(w.dx - 0.26 * s, w.dy + 0.05 * s, w.dx - 0.23 * s, floorY), prop);
      canvas.drawRect(Rect.fromLTRB(w.dx - 0.05 * s, w.dy + 0.05 * s, w.dx - 0.02 * s, floorY), prop);
    }
    if (props.contains('bar')) {
      final w = o(j['wrist']!);
      canvas.drawLine(Offset(w.dx - 0.35 * s, w.dy), Offset(w.dx + 0.35 * s, w.dy),
          Paint()
            ..color = const Color(0xFF9AA2D6)
            ..strokeWidth = 0.018 * s
            ..strokeCap = StrokeCap.round);
    }
  }

  void _handProps(Canvas canvas, double s, Offset Function(Vec2) o, Map<String, Vec2> j) {
    final k = pose.scale;
    if (props.contains('dumbbells')) {
      for (final key in ['wrist', 'wrist2']) {
        final w = j[key];
        if (w == null) continue;
        final c = o(w);
        final p = Paint()..color = const Color(0xFF3C4373);
        canvas.drawRRect(
            RRect.fromRectAndRadius(Rect.fromCenter(center: c, width: 0.075 * s * k, height: 0.03 * s * k),
                Radius.circular(0.008 * s)),
            p);
        for (final dx in [-0.035, 0.035]) {
          canvas.drawRRect(
              RRect.fromRectAndRadius(
                  Rect.fromCenter(center: c.translate(dx * s * k, 0), width: 0.02 * s * k, height: 0.055 * s * k),
                  Radius.circular(0.006 * s)),
              Paint()..color = const Color(0xFF6C74AE));
        }
      }
    }
    if (props.contains('barbell')) {
      final c = o(j['wrist']!);
      canvas.drawCircle(c, 0.07 * s * k, Paint()..color = const Color(0xFF3C4373));
      canvas.drawCircle(c, 0.07 * s * k, Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.008 * s
        ..color = const Color(0xFF6C74AE));
      canvas.drawCircle(c, 0.012 * s * k, Paint()..color = const Color(0xFF9AA2D6));
    }
  }

  @override
  bool shouldRepaint(covariant MannequinPainter old) =>
      old.pose != pose || old.glow != glow || old.pulseT != pulseT;
}

/// Exercise thumbnail (asset A4): a pre-rendered frame of the 3D
/// demonstration (`assets/thumbs/<id>.webp`). Falls back to the 2D mannequin
/// if the image is missing. Premium exercises the user has not unlocked
/// show a small lock badge when [locked] is set.
class ExerciseThumb extends StatelessWidget {
  final ExerciseDef def;
  final double size;
  final bool locked;
  const ExerciseThumb({super.key, required this.def, this.size = 64, this.locked = false});

  @override
  Widget build(BuildContext context) {
    final px = (size * (MediaQuery.maybeDevicePixelRatioOf(context) ?? 2.0).clamp(1.0, 3.0)).round();
    return SizedBox(
      width: size,
      height: size,
      child: Stack(children: [
        Positioned.fill(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(size * 0.18),
            child: DecoratedBox(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Color(0xFF1C2350), Color(0xFF0D1029)],
                ),
              ),
              child: Image.asset(
                'assets/thumbs/${def.id}.webp',
                cacheWidth: px,
                fit: BoxFit.cover,
                semanticLabel: def.name,
                errorBuilder: (context, error, stack) => ExerciseThumb2D(def: def, size: size),
              ),
            ),
          ),
        ),
        if (locked)
          Positioned(
            right: 3,
            top: 3,
            child: Container(
              padding: const EdgeInsets.all(3),
              decoration: const BoxDecoration(color: Color(0xCC000000), shape: BoxShape.circle),
              child: Icon(Icons.lock, size: size < 60 ? 11 : 14, color: const Color(0xFFFFC94D)),
            ),
          ),
      ]),
    );
  }
}

/// 2D mannequin thumbnail (fallback and Lite profile).
class ExerciseThumb2D extends StatelessWidget {
  final ExerciseDef def;
  final double size;
  const ExerciseThumb2D({super.key, required this.def, this.size = 64});

  @override
  Widget build(BuildContext context) {
    final u = def.isTimed ? 0.0 : 1.0;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF242B57), Color(0xFF151A36)],
        ),
        borderRadius: BorderRadius.circular(12),
      ),
      child: RepaintBoundary(
        child: CustomPaint(
          painter: MannequinPainter(
            pose: MannequinRig.solve(def.keyframes, u),
            muscles: def.normalisedMuscles,
            glow: 1,
            props: def.keyframes.props,
          ),
        ),
      ),
    );
  }
}

/// Looping demonstration (FR-DM-02). Shows two static poses with a manual
/// toggle when animations are reduced or on the Lite profile (FR-DM-07).
class ExerciseDemo extends StatefulWidget {
  final ExerciseDef def;
  final bool animate;
  final bool mistake;
  const ExerciseDemo({super.key, required this.def, this.animate = true, this.mistake = false});

  @override
  State<ExerciseDemo> createState() => _ExerciseDemoState();
}

class _ExerciseDemoState extends State<ExerciseDemo> with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  double _t = 0;
  bool _showEnd = false;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker((d) => setState(() => _t = d.inMicroseconds / 1e6));
  }

  void _sync() {
    final reduce = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final run = widget.animate && !reduce;
    if (run && !_ticker.isActive) _ticker.start();
    if (!run && _ticker.isActive) _ticker.stop();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _sync();
  }

  @override
  void didUpdateWidget(covariant ExerciseDemo old) {
    super.didUpdateWidget(old);
    _sync();
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reduce = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final animated = widget.animate && !reduce;
    final motion = DemoMotion(widget.def, mistake: widget.mistake);
    final u = animated ? motion.u(_t) : (_showEnd ? 1.0 : 0.0);
    final pose = MannequinRig.solve(widget.def.keyframes, u);
    final painter = RepaintBoundary(
      child: CustomPaint(
        size: Size.infinite,
        painter: MannequinPainter(
          pose: pose,
          muscles: widget.def.normalisedMuscles,
          glow: widget.def.isTimed ? 0.8 : u,
          props: widget.def.keyframes.props,
          pulse: animated,
          pulseT: _t / 1.6,
        ),
      ),
    );
    if (animated) return Semantics(label: '${widget.def.name} demonstration', child: painter);
    return Stack(children: [
      Positioned.fill(child: painter),
      Positioned(
        right: 8,
        bottom: 8,
        child: OutlinedButton.icon(
          onPressed: () => setState(() => _showEnd = !_showEnd),
          icon: const Icon(Icons.swap_horiz, size: 18),
          label: Text(_showEnd ? 'End pose' : 'Start pose'),
        ),
      ),
    ]);
  }
}
