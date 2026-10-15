import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../core/theme.dart';

/// Difficulty bars 1..5 (seen on every exercise row).
class LevelBars extends StatelessWidget {
  final int level;
  const LevelBars(this.level, {super.key});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Level $level of 5',
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: List.generate(
          5,
          (i) => Container(
            width: 9,
            height: 12,
            margin: const EdgeInsets.only(right: 2),
            decoration: BoxDecoration(
              color: i < level ? FF.accent : FF.outline,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        ),
      ),
    );
  }
}

class StatusBadge extends StatelessWidget {
  final bool validated;
  const StatusBadge({super.key, required this.validated});

  @override
  Widget build(BuildContext context) {
    final c = validated ? FF.good : FF.warn;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: c.withValues(alpha: 0.5)),
      ),
      child: Text(validated ? 'Validated' : 'Beta',
          style: TextStyle(color: c, fontSize: 10, fontWeight: FontWeight.w700)),
    );
  }
}

class SectionCard extends StatelessWidget {
  final String? title;
  final IconData? icon;
  final Widget? trailing;
  final Widget child;
  final EdgeInsets padding;
  const SectionCard({super.key, this.title, this.icon, this.trailing, required this.child, this.padding = const EdgeInsets.all(16)});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: padding,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (title != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Row(children: [
                  if (icon != null) ...[Icon(icon, size: 22, color: FF.text), const SizedBox(width: 8)],
                  Expanded(
                      child: Text(title!, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700))),
                  if (trailing != null) trailing!,
                ]),
              ),
            child,
          ],
        ),
      ),
    );
  }
}

/// AI Coach strip: one-line status that expands into insights (FR-CO-01).
class CoachStrip extends StatefulWidget {
  final List<String> insights;
  const CoachStrip({super.key, required this.insights});

  @override
  State<CoachStrip> createState() => _CoachStripState();
}

class _CoachStripState extends State<CoachStrip> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final items = widget.insights.isEmpty ? ['Complete a workout to get coaching insights'] : widget.insights;
    return Material(
      color: FF.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(FF.radius),
        side: const BorderSide(color: FF.accent, width: 1.2),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(FF.radius),
        onTap: () => setState(() => _open = !_open),
        child: AnimatedSize(
          duration: const Duration(milliseconds: 220),
          alignment: Alignment.topCenter,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  const Icon(Icons.auto_awesome, color: FF.accent, size: 18),
                  const SizedBox(width: 6),
                  const Text('COACH',
                      style: TextStyle(color: FF.accent, fontWeight: FontWeight.w800, fontSize: 12, letterSpacing: 1)),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(items.first,
                        maxLines: _open ? 3 : 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w600)),
                  ),
                  Icon(_open ? Icons.expand_less : Icons.expand_more, color: FF.muted),
                ]),
                if (_open)
                  ...items.skip(1).map((t) => Padding(
                        padding: const EdgeInsets.only(top: 10, left: 24),
                        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          const Text('•  ', style: TextStyle(color: FF.accent)),
                          Expanded(child: Text(t, style: const TextStyle(color: FF.muted))),
                        ]),
                      )),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Animated circular progress ring.
class ProgressRing extends StatelessWidget {
  final double value; // 0..1
  final double size;
  final double stroke;
  final Color color;
  final Widget? child;
  const ProgressRing({super.key, required this.value, this.size = 64, this.stroke = 7, this.color = FF.accent, this.child});

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: value.clamp(0, 1).toDouble()),
      duration: const Duration(milliseconds: 600),
      curve: Curves.easeOutCubic,
      builder: (context, v, _) => SizedBox(
        width: size,
        height: size,
        child: CustomPaint(
          painter: _RingPainter(v, stroke, color),
          child: Center(child: child),
        ),
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  final double v;
  final double stroke;
  final Color color;
  _RingPainter(this.v, this.stroke, this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final r = Rect.fromLTWH(stroke / 2, stroke / 2, size.width - stroke, size.height - stroke);
    canvas.drawArc(r, 0, 2 * math.pi, false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = stroke
          ..color = FF.outline);
    canvas.drawArc(r, -math.pi / 2, 2 * math.pi * v, false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = stroke
          ..strokeCap = StrokeCap.round
          ..color = color);
  }

  @override
  bool shouldRepaint(covariant _RingPainter old) => old.v != v || old.color != color;
}

/// Form score bar chart with green / amber / red bands and icons (FR-PG-02).
class FormScoreChart extends StatelessWidget {
  final List<({String label, double score})> points;
  const FormScoreChart({super.key, required this.points});

  @override
  Widget build(BuildContext context) {
    if (points.isEmpty) {
      return const SizedBox(height: 120, child: Center(child: Text('No workouts yet', style: TextStyle(color: FF.muted))));
    }
    return SizedBox(
      height: 150,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: points.map((p) {
          final c = FF.scoreColor(p.score);
          return Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 3),
              child: Column(mainAxisAlignment: MainAxisAlignment.end, children: [
                Icon(FF.scoreIcon(p.score), size: 12, color: c),
                const SizedBox(height: 2),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(p.score.round().toString(),
                      maxLines: 1, softWrap: false, style: TextStyle(fontSize: 10, color: c, fontFeatures: FF.tabular)),
                ),
                const SizedBox(height: 3),
                TweenAnimationBuilder<double>(
                  tween: Tween(begin: 0, end: p.score / 100),
                  duration: const Duration(milliseconds: 500),
                  builder: (context, v, _) => Container(
                    height: 80 * v + 2,
                    decoration: BoxDecoration(color: c, borderRadius: BorderRadius.circular(4)),
                  ),
                ),
                const SizedBox(height: 4),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(p.label, maxLines: 1, softWrap: false, style: const TextStyle(fontSize: 10, color: FF.muted)),
                ),
              ]),
            ),
          );
        }).toList(),
      ),
    );
  }
}

/// Logo text "FormFlow" with the accent on "Flow".
class FormFlowLogo extends StatelessWidget {
  final double size;
  const FormFlowLogo({super.key, this.size = 28});

  @override
  Widget build(BuildContext context) {
    return RichText(
      text: TextSpan(style: TextStyle(fontSize: size, fontWeight: FontWeight.w800, letterSpacing: -0.5), children: const [
        TextSpan(text: 'Form', style: TextStyle(color: FF.text)),
        TextSpan(text: 'Flow', style: TextStyle(color: FF.accent)),
      ]),
    );
  }
}

class EmptyIllustration extends StatelessWidget {
  final String text;
  const EmptyIllustration({super.key, required this.text});

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      SizedBox(height: 110, width: 200, child: CustomPaint(painter: _GymPainter())),
      const SizedBox(height: 8),
      Text(text, textAlign: TextAlign.center, style: const TextStyle(color: FF.muted)),
    ]);
  }
}

/// Original, simple illustration for empty states (asset A6).
class _GymPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    final floor = Path()
      ..moveTo(w * 0.5, h * 0.35)
      ..lineTo(w * 0.95, h * 0.62)
      ..lineTo(w * 0.5, h * 0.95)
      ..lineTo(w * 0.05, h * 0.62)
      ..close();
    canvas.drawPath(floor, Paint()..color = FF.accentSoft);
    final p = Paint()
      ..color = FF.accent
      ..strokeWidth = 5
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(Offset(w * 0.3, h * 0.6), Offset(w * 0.52, h * 0.72), p);
    for (final c in [Offset(w * 0.29, h * 0.595), Offset(w * 0.53, h * 0.725)]) {
      canvas.drawCircle(c, 9, Paint()..color = FF.muted);
    }
    final bench = Paint()..color = const Color(0xFF5A6299);
    canvas.drawRRect(
        RRect.fromRectAndRadius(Rect.fromLTWH(w * 0.55, h * 0.48, w * 0.22, h * 0.07), const Radius.circular(4)), bench);
    canvas.drawCircle(Offset(w * 0.72, h * 0.3), 10, Paint()..color = FF.good.withValues(alpha: 0.8));
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// Gold "PRO" tag on premium exercises (an open lock once unlocked).
class PremiumTag extends StatelessWidget {
  final bool unlocked;
  const PremiumTag({super.key, this.unlocked = false});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        gradient: const LinearGradient(colors: [Color(0xFFFFD36E), Color(0xFFFFA63D)]),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(unlocked ? Icons.lock_open : Icons.workspace_premium, size: 11, color: const Color(0xFF3A2400)),
        const SizedBox(width: 2),
        const Text('PRO', style: TextStyle(color: Color(0xFF3A2400), fontSize: 10, fontWeight: FontWeight.w900)),
      ]),
    );
  }
}

/// Call to action for free users on the library and home screens.
class PremiumBanner extends StatelessWidget {
  final int lockedCount;
  final VoidCallback onTap;
  const PremiumBanner({super.key, required this.lockedCount, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      key: const Key('premium_banner'),
      borderRadius: BorderRadius.circular(FF.radius),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Ink(
          decoration: const BoxDecoration(
            gradient: LinearGradient(colors: [Color(0xFF6D5BFF), Color(0xFF3D8BFF)]),
          ),
          padding: const EdgeInsets.all(14),
          child: Row(children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.18), shape: BoxShape.circle),
              child: const Icon(Icons.workspace_premium, color: Color(0xFFFFD36E), size: 28),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('FormFlow Premium', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16, color: Colors.white)),
                const SizedBox(height: 2),
                Text('Unlock $lockedCount pro exercises, no ads',
                    style: TextStyle(color: Colors.white.withValues(alpha: 0.85), fontSize: 13)),
              ]),
            ),
            const Icon(Icons.chevron_right, color: Colors.white),
          ]),
        ),
      ),
    );
  }
}

/// App logo mark (assets/branding/logo.png) with a drawn fallback.
class AppLogoMark extends StatelessWidget {
  final double size;
  const AppLogoMark({super.key, this.size = 96});

  @override
  Widget build(BuildContext context) {
    return Image.asset(
      'assets/branding/logo.png',
      width: size,
      height: size,
      filterQuality: FilterQuality.medium,
      errorBuilder: (context, error, stack) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(size * 0.24),
          gradient: const LinearGradient(colors: [FF.accent, Color(0xFF3D8BFF)]),
        ),
        child: Icon(Icons.bolt, size: size * 0.6, color: Colors.white),
      ),
    );
  }
}
