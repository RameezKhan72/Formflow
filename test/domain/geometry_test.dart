import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:formflow/domain/geometry.dart';

void main() {
  group('angleAt (FR-FA-01)', () {
    test('right angle is 90 degrees', () {
      expect(angleAt(const Vec2(0, 1), const Vec2(0, 0), const Vec2(1, 0)), closeTo(90, 1e-9));
    });
    test('straight line is 180 degrees', () {
      expect(angleAt(const Vec2(-1, 0), const Vec2(0, 0), const Vec2(1, 0)), closeTo(180, 1e-9));
    });
    test('45 degrees', () {
      expect(angleAt(const Vec2(1, 0), const Vec2(0, 0), const Vec2(1, 1)), closeTo(45, 1e-9));
    });
    test('degenerate input returns null', () {
      expect(angleAt(const Vec2(0, 0), const Vec2(0, 0), const Vec2(1, 0)), isNull);
    });
    test('angle is symmetric in a and c', () {
      const a = Vec2(0.3, 0.7), b = Vec2(0.5, 0.5), c = Vec2(0.9, 0.6);
      expect(angleAt(a, b, c), closeTo(angleAt(c, b, a)!, 1e-12));
    });
  });

  test('angleFromVertical: up is 0, horizontal is 90', () {
    expect(angleFromVertical(const Vec2(0, 1), const Vec2(0, 0)), closeTo(0, 1e-9));
    expect(angleFromVertical(const Vec2(0, 0), const Vec2(1, 0)), closeTo(90, 1e-9));
    expect(angleFromHorizontal(const Vec2(0, 0), const Vec2(1, 1)), closeTo(45, 1e-9));
  });

  test('Vec2.fromDirection uses 0 = up, 90 = right', () {
    final up = Vec2.fromDirection(0);
    final right = Vec2.fromDirection(90);
    expect(up.x, closeTo(0, 1e-9));
    expect(up.y, closeTo(-1, 1e-9));
    expect(right.x, closeTo(1, 1e-9));
    expect(right.y, closeTo(0, 1e-9));
  });

  group('smoothing (FR-PE-06)', () {
    test('EMA converges to a constant', () {
      final f = EmaFilter(alpha: 0.4);
      var v = 0.0;
      for (var i = 0; i < 50; i++) {
        v = f.filter(10);
      }
      expect(v, closeTo(10, 1e-6));
    });

    test('One Euro filter reduces jitter on a still signal', () {
      final f = OneEuroFilter();
      final rnd = math.Random(1);
      double rawVar = 0, outVar = 0;
      for (var i = 0; i < 300; i++) {
        final noise = (rnd.nextDouble() - 0.5) * 0.02;
        final out = f.filter(0.5 + noise, i / 30);
        if (i > 30) {
          rawVar += noise * noise;
          outVar += (out - 0.5) * (out - 0.5);
        }
      }
      expect(outVar, lessThan(rawVar * 0.6));
    });

    test('One Euro filter follows a fast move', () {
      final f = OneEuroFilter();
      double out = 0;
      for (var i = 0; i < 30; i++) {
        out = f.filter(i < 10 ? 0 : 1, i / 30);
      }
      expect(out, greaterThan(0.9));
    });
  });
}
