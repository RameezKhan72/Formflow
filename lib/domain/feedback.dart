import 'exercise.dart';
import 'landmarks.dart';
import 'rules.dart';

enum FeedbackKind { speak, tone, haptic }

enum RepSpeech { every, everyFifth, off }

class FeedbackAction {
  final FeedbackKind kind;
  final String? cueId;
  final String? text;
  final BodySide? side;
  const FeedbackAction(this.kind, {this.cueId, this.text, this.side});

  @override
  String toString() => 'FeedbackAction($kind, $cueId, $text)';
}

/// Applies cue priority, cooldowns and the correction loop (FR-VF-03,
/// FR-VF-04, FR-VF-05, FR-VF-06). Time is injected so it is unit-testable.
class FeedbackManager {
  final CueBook cues;
  final double globalGap; // seconds between any two spoken corrections
  final double sameCueGap; // seconds between the same cue
  final int maxSpokenPerCuePerSet;
  RepSpeech repSpeech;
  bool voiceEnabled;

  double _lastSpokenAt = -1e9;
  final Map<String, double> _lastCueAt = {};
  final Map<String, int> _spokenCount = {};

  /// Cues awaiting re-check on the next rep (correction loop).
  final Set<String> _pendingRecheck = {};

  FeedbackManager({
    required this.cues,
    this.globalGap = 3.0,
    this.sameCueGap = 4.0,
    this.maxSpokenPerCuePerSet = 2,
    this.repSpeech = RepSpeech.everyFifth,
    this.voiceEnabled = true,
  });

  Set<String> get pendingRecheck => Set.unmodifiable(_pendingRecheck);

  void resetSet() {
    _spokenCount.clear();
    _pendingRecheck.clear();
    _lastCueAt.clear();
  }

  static int priority(CueCategory c) {
    switch (c) {
      case CueCategory.safety:
        return 3;
      case CueCategory.form:
        return 2;
      case CueCategory.depth:
        return 1;
    }
  }

  bool _canSpeak(String cueId, double t) {
    if (!voiceEnabled) return false;
    if (t - _lastSpokenAt < globalGap) return false;
    final last = _lastCueAt[cueId];
    if (last != null && t - last < sameCueGap) return false;
    return true;
  }

  List<FeedbackAction> _correction(Issue issue, double t) {
    final cue = issue.cue;
    final count = _spokenCount[cue] ?? 0;
    if (count >= maxSpokenPerCuePerSet) {
      // After the repeats are used up: visual and haptic only.
      return const [FeedbackAction(FeedbackKind.haptic)];
    }
    if (!_canSpeak(cue, t)) return const [];
    _spokenCount[cue] = count + 1;
    _lastSpokenAt = t;
    _lastCueAt[cue] = t;
    _pendingRecheck.add(cue);
    return [
      FeedbackAction(FeedbackKind.speak, cueId: cue, text: cues.text(cue, side: issue.side), side: issue.side),
      const FeedbackAction(FeedbackKind.haptic),
    ];
  }

  Issue? _top(Iterable<Issue> issues) {
    Issue? best;
    for (final i in issues) {
      if (best == null ||
          priority(i.rule.category) > priority(best.rule.category) ||
          (priority(i.rule.category) == priority(best.rule.category) &&
              i.severity.index > best.severity.index)) {
        best = i;
      }
    }
    return best;
  }

  /// Mid-rep: only posture (safety / form) issues may be spoken (FR-VF-05).
  List<FeedbackAction> onFrame(List<Issue> active, double t) {
    final posture = active.where((i) => i.rule.category != CueCategory.depth);
    final top = _top(posture);
    if (top == null) return const [];
    return _correction(top, t);
  }

  /// At rep end: confirmations for fixed errors, depth cues, rep tone.
  List<FeedbackAction> onRepEnd({
    required List<Issue> repIssues,
    required bool clean,
    required int cleanCount,
    required double t,
  }) {
    final out = <FeedbackAction>[];
    final cuesThisRep = repIssues.map((i) => i.cue).toSet();

    // Correction loop: re-check errors that were spoken on the previous rep.
    var confirmed = false;
    for (final cue in _pendingRecheck.toList()) {
      if (!cuesThisRep.contains(cue)) {
        _pendingRecheck.remove(cue);
        confirmed = true;
      }
    }
    if (clean) out.add(const FeedbackAction(FeedbackKind.tone));

    final top = _top(repIssues);
    if (top != null) {
      out.addAll(_correction(top, t));
    } else if (confirmed && voiceEnabled && t - _lastSpokenAt >= 1.0) {
      _lastSpokenAt = t;
      out.add(FeedbackAction(FeedbackKind.speak, cueId: 'good_form', text: cues.text('good_form')));
    } else if (clean && voiceEnabled && _shouldSpeakCount(cleanCount) && t - _lastSpokenAt >= 1.0) {
      _lastSpokenAt = t;
      out.add(FeedbackAction(FeedbackKind.speak, cueId: 'count', text: '$cleanCount'));
    }
    return out;
  }

  bool _shouldSpeakCount(int n) {
    switch (repSpeech) {
      case RepSpeech.every:
        return true;
      case RepSpeech.everyFifth:
        return n % 5 == 0;
      case RepSpeech.off:
        return false;
    }
  }
}
