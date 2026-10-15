import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../core/theme.dart';
import '../domain/landmarks.dart';

/// Draws the skeleton overlay (FR-PE-08). Landmarks are in camera image
/// space; x is mirrored only when drawing a front-camera preview.
class SkeletonPainter extends CustomPainter {
  final BodyPose? pose;
  final Set<LandmarkId> wrong;
  final bool mirror;
  final double pulse; // 0..1
  final bool labels;

  /// Landmarks of the exercise focus. When set, only these joints and the
  /// bones between them are drawn; face, hands and unrelated limbs are
  /// left out so the user sees exactly what is being tracked.
  final Set<LandmarkId>? focus;

  SkeletonPainter({this.pose, this.wrong = const {}, this.mirror = false, this.pulse = 0, this.labels = true, this.focus})
      : super();

  bool _shown(LandmarkId id) => focus == null || focus!.contains(id);

  @override
  void paint(Canvas canvas, Size size) {
    final p = pose;
    if (p == null) return;
    Offset map(Landmark l) {
      var x = l.x / p.aspect;
      if (mirror) x = 1 - x;
      return Offset(x * size.width, l.y * size.height);
    }

    final good = Paint()
      ..color = FF.good
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round;
    final bad = Paint()
      ..color = FF.bad
      ..strokeWidth = 5
      ..strokeCap = StrokeCap.round;
    for (final b in skeletonBones) {
      final a = p[b[0]], c = p[b[1]];
      if (a.confidence < 0.5 || c.confidence < 0.5) continue;
      if (!_shown(b[0]) || !_shown(b[1])) continue;
      final isBad = wrong.contains(b[0]) || wrong.contains(b[1]);
      canvas.drawLine(map(a), map(c), isBad ? bad : good);
    }
    for (final id in LandmarkId.values) {
      final l = p[id];
      if (l.confidence < 0.5 || id.index < 11) continue;
      if (!_shown(id)) continue;
      // fingers are not tracked (doc item 9: ignore inner landmarks)
      if (id.name.contains('Pinky') || (id.name.contains('Index') && !id.name.contains('Foot')) || id.name.contains('Thumb')) {
        continue;
      }
      final o = map(l);
      final isBad = wrong.contains(id);
      canvas.drawCircle(o, isBad ? 6 : 4, Paint()..color = isBad ? FF.bad : Colors.white);
      if (isBad) {
        canvas.drawCircle(
            o,
            12 + 10 * pulse,
            Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = 3
              ..color = FF.bad.withValues(alpha: 1 - pulse));
      }
    }
    if (labels) {
      // Label anatomical sides so L/R match the user's body (PRD 8.4).
      final ls = p[LandmarkId.leftShoulder], rs = p[LandmarkId.rightShoulder];
      final overlap = (ls.x - rs.x).abs() / p.aspect < 0.05 && (ls.y - rs.y).abs() < 0.05;
      for (final e in [(LandmarkId.leftShoulder, 'L'), (LandmarkId.rightShoulder, 'R')]) {
        final l = p[e.$1];
        if (l.confidence < 0.5) continue;
        // side view: label only the visible (more confident) shoulder
        if (overlap && ((e.$2 == 'L') != (ls.confidence >= rs.confidence))) continue;
        final o = map(l);
        final tp = TextPainter(
          text: TextSpan(text: e.$2, style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w800)),
          textDirection: TextDirection.ltr,
        )..layout();
        final dx = math.max(0.0, o.dx - 18);
        canvas.drawCircle(Offset(dx + 4, o.dy - 14), 9, Paint()..color = FF.accent);
        tp.paint(canvas, Offset(dx + 4 - tp.width / 2, o.dy - 14 - tp.height / 2));
      }
    }
  }

  @override
  bool shouldRepaint(covariant SkeletonPainter old) => true;
}
