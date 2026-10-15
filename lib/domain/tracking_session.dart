import 'exercise.dart';
import 'feedback.dart';
import 'landmarks.dart';
import 'measurements.dart';
import 'rep_counter.dart';
import 'rules.dart';

class RepResult {
  final int index;
  final bool clean;
  final int score;
  final bool depthReached;
  final double peak;
  final double tempo;
  final List<String> issues; // cue ids (with :side suffix when known)
  final double time;
  const RepResult({
    required this.index,
    required this.clean,
    required this.score,
    required this.depthReached,
    required this.peak,
    required this.tempo,
    required this.issues,
    required this.time,
  });

  Map<String, dynamic> toJson() => {
        'i': index,
        'clean': clean,
        'score': score,
        'depth': depthReached,
        'peak': double.parse(peak.toStringAsFixed(1)),
        'tempo': double.parse(tempo.toStringAsFixed(2)),
        'issues': issues,
        't': time,
      };

  factory RepResult.fromJson(Map<String, dynamic> j) => RepResult(
        index: (j['i'] as num).toInt(),
        clean: j['clean'] as bool,
        score: (j['score'] as num).toInt(),
        depthReached: (j['depth'] as bool?) ?? true,
        peak: (j['peak'] as num?)?.toDouble() ?? 0,
        tempo: (j['tempo'] as num?)?.toDouble() ?? 0,
        issues: ((j['issues'] as List?) ?? const []).cast<String>(),
        time: (j['t'] as num?)?.toDouble() ?? 0,
      );
}

class FrameResult {
  final Phase phase;
  final double? metric;
  final double progress;
  final CameraView view;
  final List<Issue> activeIssues;
  final RepResult? rep;
  final List<FeedbackAction> actions;
  final bool paused;
  final bool justPaused;
  final bool inHold;
  final double holdSeconds;
  final String? viewHint;
  final BodySide metricSide;
  final List<LandmarkId> highlight;

  const FrameResult({
    required this.phase,
    required this.metric,
    required this.progress,
    required this.view,
    required this.activeIssues,
    required this.rep,
    required this.actions,
    required this.paused,
    required this.justPaused,
    required this.inHold,
    required this.holdSeconds,
    required this.viewHint,
    required this.metricSide,
    required this.highlight,
  });
}

/// The per-frame pipeline of PRD 8.3 steps 3-7: clean, measure, count,
/// check and feedback. Pure Dart; fed by the camera or by replayed /
/// synthetic landmarks.
class TrackingSession {
  final ExerciseDef def;
  final RepCounter counter;
  final RuleEngine engine;
  final FeedbackManager feedback;
  final PoseSmoother? smoother;
  final double noPersonPauseSeconds;

  int attempts = 0;
  int cleanReps = 0;
  double holdSeconds = 0;
  final List<RepResult> reps = [];
  final Map<String, int> issueCounts = {};

  double? _lastSeen;
  double? _lastT;
  bool _paused = false;
  final Map<String, Issue> _repIssues = {};
  bool _hintGiven = false;
  double? _bestPeak;
  late final List<Joint> _focus = jointsFromNames(def.focus);

  TrackingSession(
    this.def, {
    required CueBook cues,
    Thresholds? thresholds,
    this.smoother,
    this.noPersonPauseSeconds = 1.5,
    RepSpeech repSpeech = RepSpeech.everyFifth,
    bool voice = true,
  })  : counter = RepCounter(direction: def.metric.direction, thresholds: thresholds ?? def.thresholds),
        engine = RuleEngine(def.rules),
        feedback = FeedbackManager(cues: cues, repSpeech: repSpeech, voiceEnabled: voice);

  bool get paused => _paused;
  double? get bestPeak => _bestPeak;

  double get averageForm {
    if (reps.isEmpty) return 0;
    return reps.map((r) => r.score).reduce((a, b) => a + b) / reps.length;
  }

  /// Most frequent issue cue (for the "Fix next time" tip).
  String? get topIssue {
    String? best;
    var n = 0;
    issueCounts.forEach((k, v) {
      if (v > n) {
        n = v;
        best = k;
      }
    });
    return best;
  }

  void resetSet() {
    counter.reset();
    engine.reset();
    feedback.resetSet();
    _repIssues.clear();
  }

  FrameResult process(BodyPose? rawPose, double t) {
    final dt = _lastT == null ? 0.0 : (t - _lastT!).clamp(0.0, 0.5);
    _lastT = t;
    final pose = (rawPose != null && smoother != null) ? smoother!.smooth(rawPose, t) : rawPose;
    final metric = pose == null ? null : Measurements.metricValue(pose, def.metric, focus: _focus);
    final actions = <FeedbackAction>[];

    // Person visibility and auto pause (FR-PE-10).
    var justPaused = false;
    if (metric == null) {
      _lastSeen ??= t;
      if (!_paused && t - _lastSeen! >= noPersonPauseSeconds) {
        _paused = true;
        justPaused = true;
        actions.add(FeedbackAction(FeedbackKind.speak,
            cueId: 'step_back', text: feedback.cues.text('step_back')));
      }
      return FrameResult(
        phase: counter.phase,
        metric: null,
        progress: 0,
        view: CameraView.side,
        activeIssues: const [],
        rep: null,
        actions: actions,
        paused: _paused,
        justPaused: justPaused,
        inHold: false,
        holdSeconds: holdSeconds,
        viewHint: null,
        metricSide: BodySide.left,
        highlight: const [],
      );
    }
    _lastSeen = t;
    if (_paused) {
      _paused = false;
      counter.reset();
    }

    final p = pose!;
    final view = Measurements.viewOf(p);
    String? hint;
    final skipped = engine.skippedForView(view);
    if (skipped.isNotEmpty && view == CameraView.side && !_hintGiven) {
      hint = 'Face the camera to check ${skipped.first.id.replaceAll('_', ' ')}';
      _hintGiven = true;
    }

    RepResult? repResult;
    var inHold = false;
    List<Issue> active;

    if (def.isTimed) {
      final m = Measurements.all(p, metric.side);
      inHold = RuleEngine.conditionsHold(def.hold, m);
      active = engine.evaluate(p, Phase.bottom, view, metric.side, timed: true);
      final blocking = active.any((i) => i.severity != Severity.minor);
      if (inHold && !blocking) holdSeconds += dt;
      for (final i in active) {
        _repIssues[i.key] = i;
      }
      actions.addAll(feedback.onFrame(active, t));
    } else {
      final ev = counter.update(metric.value, t);
      active = engine.evaluate(p, counter.phase, view, metric.side);
      for (final i in active) {
        _repIssues[i.key] = i;
      }
      actions.addAll(feedback.onFrame(active, t));
      if (ev != null) {
        repResult = _finishRep(ev, t, actions);
      }
    }

    final highlight = <LandmarkId>[];
    for (final i in active) {
      highlight.addAll(i.highlight(metric.side));
    }

    return FrameResult(
      phase: counter.phase,
      metric: metric.value,
      progress: def.isTimed ? 0 : counter.progress(metric.value),
      view: view,
      activeIssues: active,
      rep: repResult,
      actions: actions,
      paused: false,
      justPaused: false,
      inHold: inHold,
      holdSeconds: holdSeconds,
      viewHint: hint,
      metricSide: metric.side,
      highlight: highlight,
    );
  }

  RepResult _finishRep(RepEvent ev, double t, List<FeedbackAction> actions) {
    final endIssues = engine.evaluateRepEnd({
      'depthReached': ev.depthReached ? 1 : 0,
      'duration': ev.durationSeconds,
      'peak': ev.peak,
    });
    for (final i in endIssues) {
      _repIssues[i.key] = i;
    }
    final issues = _repIssues.values.toList();
    _repIssues.clear();
    final score = Scoring.repScore(issues.map((i) => i.severity));
    final clean = ev.depthReached && !issues.any((i) => i.severity == Severity.major);
    attempts++;
    if (clean) cleanReps++;
    final better = def.metric.direction == Direction.down
        ? (_bestPeak == null || ev.peak < _bestPeak!)
        : (_bestPeak == null || ev.peak > _bestPeak!);
    if (better) _bestPeak = ev.peak;
    final names = issues.map((i) => i.side == null ? i.cue : '${i.cue}:${i.side!.word}').toList();
    for (final n in names) {
      issueCounts[n] = (issueCounts[n] ?? 0) + 1;
    }
    final r = RepResult(
      index: attempts,
      clean: clean,
      score: score,
      depthReached: ev.depthReached,
      peak: ev.peak,
      tempo: ev.durationSeconds,
      issues: names,
      time: t,
    );
    reps.add(r);
    actions.addAll(feedback.onRepEnd(repIssues: issues, clean: clean, cleanCount: cleanReps, t: t));
    return r;
  }

  /// For timed exercises the "form score" is the share of clean hold time.
  void recordTimedResult(double elapsed) {
    if (!def.isTimed) return;
    final score = elapsed <= 0 ? 0 : (holdSeconds / elapsed * 100).clamp(0, 100).round();
    final names = _repIssues.values.map((i) => i.side == null ? i.cue : '${i.cue}:${i.side!.word}').toList();
    for (final n in names) {
      issueCounts[n] = (issueCounts[n] ?? 0) + 1;
    }
    attempts++;
    if (score >= 50) cleanReps++;
    reps.add(RepResult(
      index: attempts,
      clean: score >= 50,
      score: score,
      depthReached: true,
      peak: holdSeconds,
      tempo: elapsed,
      issues: names,
      time: elapsed,
    ));
    _repIssues.clear();
  }
}
