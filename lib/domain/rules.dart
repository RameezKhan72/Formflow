import 'exercise.dart';
import 'landmarks.dart';
import 'measurements.dart';

/// Resolves cue IDs to spoken text with left / right / neutral variants
/// (FR-VF-02). Template syntax: "Push your {side} knee out|Push your knees out"
/// - the part after "|" is the neutral variant.
class CueBook {
  final Map<String, String> templates;
  const CueBook(this.templates);

  String text(String cueId, {BodySide? side}) {
    final t = templates[cueId];
    if (t == null) return cueId.replaceAll('_', ' ');
    final parts = t.split('|');
    if (side == null) {
      if (parts.length > 1) return parts[1];
      return parts[0].replaceAll('{side} ', '').replaceAll('{side}', '');
    }
    return parts[0].replaceAll('{side}', side.word);
  }

  /// Audio clip path for a cue (PRD 7.1): assets/audio/en/squat_knees_out_left.ogg
  static String clipPath(String cueId, {BodySide? side, String lang = 'en'}) =>
      'assets/audio/$lang/$cueId${side == null ? '' : '_${side.word}'}.ogg';
}

/// Severity-weighted rep score (FR-FA-06).
class Scoring {
  static int weight(Severity s) {
    switch (s) {
      case Severity.minor:
        return 10;
      case Severity.moderate:
        return 20;
      case Severity.major:
        return 35;
    }
  }

  static int repScore(Iterable<Severity> issues) {
    var score = 100;
    for (final s in issues) {
      score -= weight(s);
    }
    return score < 0 ? 0 : score;
  }

  /// FR-PG-02 colour bands.
  static String band(double score) => score >= 80 ? 'good' : (score >= 50 ? 'fair' : 'poor');
}

/// An issue reported by a rule.
class Issue {
  final RuleDef rule;
  final BodySide? side;
  const Issue(this.rule, this.side);

  String get key => side == null ? rule.id : '${rule.id}:${side!.word}';
  String get cue => rule.cue;
  Severity get severity => rule.severity;

  /// Landmarks to highlight in red.
  List<LandmarkId> highlight(BodySide fallback) {
    final out = <LandmarkId>[];
    for (final j in rule.joints) {
      final joint = jointFromName(j);
      if (side != null) {
        out.add(landmarkFor(joint, side!));
      } else {
        out.add(landmarkFor(joint, fallback));
      }
    }
    return out;
  }
}

/// Evaluates rules frame by frame with persistence counters (FR-FA-04) and
/// view awareness (FR-FA-10).
class RuleEngine {
  final List<RuleDef> rules;
  final Map<String, int> _counters = {};
  RuleEngine(this.rules);

  void reset() => _counters.clear();

  static bool phaseMatches(String rulePhase, Phase phase, {bool timed = false}) {
    if (timed) return rulePhase != 'rep_end';
    switch (rulePhase) {
      case 'any':
        return true;
      case 'moving':
        return phase == Phase.lowering || phase == Phase.bottom || phase == Phase.rising;
      case 'lowering':
        return phase == Phase.lowering;
      case 'bottom':
        return phase == Phase.bottom || phase == Phase.lowering;
      case 'rising':
        return phase == Phase.rising;
      default:
        return false;
    }
  }

  static bool conditionsHold(Map<String, Condition> when, Map<String, double> m) {
    if (when.isEmpty) return false;
    for (final e in when.entries) {
      final v = m[e.key];
      if (v == null) return false;
      final c = e.value;
      if (c.equals != null) {
        if ((v > 0.5) != c.equals) return false;
      } else if (!c.test(v)) {
        return false;
      }
    }
    return true;
  }

  /// Rules that are skipped because the camera view is wrong.
  List<RuleDef> skippedForView(CameraView view) =>
      rules.where((r) => r.view != null && r.view != view).toList();

  /// Returns the issues that have persisted long enough this frame.
  List<Issue> evaluate(BodyPose pose, Phase phase, CameraView view, BodySide metricSide, {bool timed = false}) {
    final active = <Issue>[];
    for (final r in rules) {
      if (r.isRepEnd) continue;
      if (r.view != null && r.view != view) continue;
      if (!phaseMatches(r.phase, phase, timed: timed)) {
        _counters.remove(r.id);
        _counters.remove('${r.id}:left');
        _counters.remove('${r.id}:right');
        continue;
      }
      if (r.bilateral && view == CameraView.front) {
        // Compute both sides and name the side (IMP-02).
        for (final s in BodySide.values) {
          final m = Measurements.all(pose, s);
          _tick(r, s, conditionsHold(r.when, m), active);
        }
      } else {
        final m = Measurements.all(pose, metricSide);
        _tick(r, null, conditionsHold(r.when, m), active);
      }
    }
    return active;
  }

  void _tick(RuleDef r, BodySide? side, bool violated, List<Issue> out) {
    final key = side == null ? r.id : '${r.id}:${side.word}';
    if (violated) {
      final n = (_counters[key] ?? 0) + 1;
      _counters[key] = n;
      if (n >= r.persistFrames) out.add(Issue(r, side));
    } else {
      _counters.remove(key);
    }
  }

  /// Rules checked once a movement is complete (e.g. depth not reached).
  List<Issue> evaluateRepEnd(Map<String, double> context) {
    final out = <Issue>[];
    for (final r in rules) {
      if (!r.isRepEnd) continue;
      if (conditionsHold(r.when, context)) out.add(Issue(r, null));
    }
    return out;
  }
}
