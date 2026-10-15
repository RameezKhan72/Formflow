import 'package:flutter_test/flutter_test.dart';
import 'package:formflow/domain/exercise.dart';
import 'package:formflow/domain/rep_counter.dart';

const squat = Thresholds(start: 150, complete: 162, depth: 105, hysteresis: 6);

List<RepEvent> run(RepCounter c, List<double> values, {double fps = 15}) {
  final out = <RepEvent>[];
  for (var i = 0; i < values.length; i++) {
    final e = c.update(values[i], i / fps);
    if (e != null) out.add(e);
  }
  return out;
}

List<double> rep(double top, double bottom, {int frames = 30}) {
  final half = frames ~/ 2;
  return [
    for (var i = 0; i <= half; i++) top + (bottom - top) * i / half,
    for (var i = 1; i <= half; i++) bottom + (top - bottom) * i / half,
  ];
}

void main() {
  group('RepCounter four-phase state machine (FR-FA-03)', () {
    test('counts one deep rep', () {
      final c = RepCounter(direction: Direction.down, thresholds: squat);
      final ev = run(c, [175, ...rep(175, 80)]);
      expect(ev, hasLength(1));
      expect(ev.single.depthReached, isTrue);
      expect(ev.single.peak, closeTo(80, 0.5));
    });

    test('counts three reps in a row', () {
      final c = RepCounter(direction: Direction.down, thresholds: squat);
      final ev = run(c, [175, ...rep(175, 90), ...rep(175, 90), ...rep(175, 90)]);
      expect(ev, hasLength(3));
    });

    test('shallow rep is an attempt without depth', () {
      final c = RepCounter(direction: Direction.down, thresholds: squat);
      final ev = run(c, [175, ...rep(175, 125)]);
      expect(ev, hasLength(1));
      expect(ev.single.depthReached, isFalse);
    });

    test('small wobble is ignored as noise', () {
      final c = RepCounter(direction: Direction.down, thresholds: squat);
      final ev = run(c, [175, ...rep(175, 145)]);
      expect(ev, isEmpty);
    });

    test('does not count before reaching the start position (idle)', () {
      final c = RepCounter(direction: Direction.down, thresholds: squat);
      // starts in the bottom position and only stands up
      final ev = run(c, [90, 100, 120, 140, 165]);
      expect(ev, isEmpty);
      expect(c.phase, Phase.ready);
    });

    test('too-fast movement (< 0.6 s) is not counted', () {
      final c = RepCounter(direction: Direction.down, thresholds: squat);
      final ev = run(c, [175, 140, 100, 140, 175], fps: 15); // ~0.2 s
      expect(ev, isEmpty);
    });

    test('jitter around the bottom does not double count (hysteresis)', () {
      final c = RepCounter(direction: Direction.down, thresholds: squat);
      final values = <double>[175, ...rep(175, 95).take(16)];
      // jitter +-4 degrees at the bottom
      for (var i = 0; i < 20; i++) {
        values.add(95 + (i.isEven ? 4 : -4));
      }
      values.addAll(rep(95, 175).take(16));
      values.addAll([175, 175]);
      final ev = run(c, values);
      expect(ev, hasLength(1));
    });

    test('works for "up" exercises (lateral raise)', () {
      final c = RepCounter(
          direction: Direction.up, thresholds: const Thresholds(start: 30, complete: 22, depth: 80, hysteresis: 5));
      final ev = run(c, [15, ...rep(15, 92), ...rep(15, 60)]);
      expect(ev, hasLength(2));
      expect(ev[0].depthReached, isTrue);
      expect(ev[0].peak, closeTo(92, 0.5));
      expect(ev[1].depthReached, isFalse);
    });

    test('progress is 0 at the top and 1 at depth', () {
      final c = RepCounter(direction: Direction.down, thresholds: squat);
      expect(c.progress(150), closeTo(0, 1e-9));
      expect(c.progress(105), closeTo(1, 1e-9));
    });
  });
}
