/// Data-driven exercise definition (FR-EX-02, FR-EX-05, FR-FA-02).
/// Pure Dart: loaded from assets/data/exercises.json.
library;

class MuscleIds {
  static const chest = 'chest';
  static const abs = 'abs';
  static const obliques = 'obliques';
  static const lats = 'lats';
  static const traps = 'traps';
  static const shoulders = 'shoulders';
  static const biceps = 'biceps';
  static const triceps = 'triceps';
  static const forearms = 'forearms';
  static const lowerBack = 'lower_back';
  static const glutes = 'glutes';
  static const quads = 'quads';
  static const hamstrings = 'hamstrings';
  static const calves = 'calves';

  static const all = [
    chest, abs, obliques, lats, traps, shoulders, biceps, triceps,
    forearms, lowerBack, glutes, quads, hamstrings, calves,
  ];

  /// Muscles drawn on the back of the body map.
  static const back = {lats, traps, lowerBack, glutes, hamstrings, triceps};

  static String label(String id) {
    switch (id) {
      case lowerBack:
        return 'Lower back';
      case abs:
        return 'Abs';
      default:
        return id[0].toUpperCase() + id.substring(1);
    }
  }
}

enum ExerciseMode { reps, timed }

enum Direction { down, up }

enum Severity { minor, moderate, major }

enum CueCategory { safety, form, depth }

enum Phase { idle, ready, lowering, bottom, rising }

enum CameraView { side, front }

class Condition {
  final double? gt;
  final double? lt;
  final bool? equals;
  const Condition({this.gt, this.lt, this.equals});

  factory Condition.fromJson(dynamic j) {
    if (j is bool) return Condition(equals: j);
    final m = j as Map<String, dynamic>;
    return Condition(
      gt: (m['gt'] as num?)?.toDouble(),
      lt: (m['lt'] as num?)?.toDouble(),
    );
  }

  bool test(double v) {
    if (gt != null && !(v > gt!)) return false;
    if (lt != null && !(v < lt!)) return false;
    return true;
  }
}

class RuleDef {
  final String id;
  final Map<String, Condition> when;

  /// any | moving | lowering | bottom | rising | rep_end | hold
  final String phase;
  final CameraView? view;
  final Severity severity;
  final CueCategory category;
  final String cue;
  final bool bilateral;
  final int persistFrames;
  final List<String> joints;

  const RuleDef({
    required this.id,
    required this.when,
    this.phase = 'moving',
    this.view,
    this.severity = Severity.moderate,
    this.category = CueCategory.form,
    required this.cue,
    this.bilateral = false,
    this.persistFrames = 4,
    this.joints = const [],
  });

  bool get isRepEnd => phase == 'rep_end';

  factory RuleDef.fromJson(Map<String, dynamic> j) {
    final when = <String, Condition>{};
    (j['when'] as Map<String, dynamic>).forEach((k, v) => when[k] = Condition.fromJson(v));
    return RuleDef(
      id: j['id'] as String,
      when: when,
      phase: (j['phase'] as String?) ?? 'moving',
      view: j['view'] == null ? null : (j['view'] == 'front' ? CameraView.front : CameraView.side),
      severity: Severity.values.byName((j['severity'] as String?) ?? 'moderate'),
      category: CueCategory.values.byName((j['category'] as String?) ?? 'form'),
      cue: j['cue'] as String,
      bilateral: (j['bilateral'] as bool?) ?? false,
      persistFrames: (j['persistFrames'] as num?)?.toInt() ?? 4,
      joints: ((j['joints'] as List?) ?? const []).cast<String>(),
    );
  }
}

class MetricDef {
  final String measure;

  /// auto (most visible side) | min (smaller value of both sides) | max
  final String side;
  final Direction direction;
  const MetricDef({required this.measure, this.side = 'auto', this.direction = Direction.down});

  factory MetricDef.fromJson(Map<String, dynamic> j) => MetricDef(
        measure: j['measure'] as String,
        side: (j['side'] as String?) ?? 'auto',
        direction: j['direction'] == 'up' ? Direction.up : Direction.down,
      );
}

class Thresholds {
  final double start;
  final double complete;
  final double depth;
  final double hysteresis;
  const Thresholds({required this.start, required this.complete, required this.depth, this.hysteresis = 6});

  factory Thresholds.fromJson(Map<String, dynamic> j) => Thresholds(
        start: (j['start'] as num).toDouble(),
        complete: (j['complete'] as num).toDouble(),
        depth: (j['depth'] as num).toDouble(),
        hysteresis: (j['hysteresis'] as num?)?.toDouble() ?? 6,
      );

  Thresholds copyWith({double? start, double? complete, double? depth, double? hysteresis}) => Thresholds(
        start: start ?? this.start,
        complete: complete ?? this.complete,
        depth: depth ?? this.depth,
        hysteresis: hysteresis ?? this.hysteresis,
      );
}

/// Mannequin keyframes for the demonstrator (Section 4, option 1).
class Keyframes {
  final String view; // side | front
  final String anchor; // floor | wrist | toe
  final double anchorX;
  final double anchorY;
  final Map<String, double> start;
  final Map<String, double> end;
  final List<String> props;
  final bool armIk;
  final double period;
  final double scale;

  const Keyframes({
    this.view = 'side',
    this.anchor = 'floor',
    this.anchorX = 0.45,
    this.anchorY = 0.9,
    required this.start,
    required this.end,
    this.props = const [],
    this.armIk = false,
    this.period = 2.4,
    this.scale = 1.0,
  });

  static Map<String, double> _angles(dynamic m) =>
      (m as Map<String, dynamic>).map((k, v) => MapEntry(k, (v as num).toDouble()));

  factory Keyframes.fromJson(Map<String, dynamic> j) => Keyframes(
        view: (j['view'] as String?) ?? 'side',
        anchor: (j['anchor'] as String?) ?? 'floor',
        anchorX: (j['anchorX'] as num?)?.toDouble() ?? 0.45,
        anchorY: (j['anchorY'] as num?)?.toDouble() ?? 0.9,
        // 2D demonstrator / engine keyframes; the 3D renders may use richer
        // 'start'/'end' poses (abduction, supports) described in tool/.
        start: _angles(j['start2d'] ?? j['start']),
        end: _angles(j['end2d'] ?? j['end']),
        props: ((j['props'] as List?) ?? const []).cast<String>(),
        armIk: (j['armIk'] as bool?) ?? false,
        period: (j['period'] as num?)?.toDouble() ?? 2.4,
        scale: (j['scale'] as num?)?.toDouble() ?? 1.0,
      );
}

class ExerciseDef {
  final String id;
  final String name;
  final String group;
  final ExerciseMode mode;
  final int level;
  final List<String> equipment;
  final List<CameraView> views;
  final String status; // beta | validated
  final int sets;
  final int reps;
  final int seconds;
  final MetricDef metric;
  final Thresholds thresholds;
  final Map<String, Condition> hold;
  final List<RuleDef> rules;
  final Map<String, double> muscles;
  final List<String> tips;
  final List<String> mistakes;
  final String cameraTip;
  final Keyframes keyframes;
  final String type; // strength | bodyweight | isometric | cardio

  /// Premium exercises need FormFlow Premium or a rewarded-ad unlock.
  final bool premium;

  /// Joints the pose engine watches for this exercise. Landmarks outside
  /// this set (face, hands, unrelated limbs) are ignored for side choice,
  /// framing and the on-screen skeleton (doc item 9).
  final List<String> focus;

  /// upper | legs | full | floor: decides camera distance and framing.
  final String region;

  const ExerciseDef({
    required this.id,
    required this.name,
    required this.group,
    required this.mode,
    required this.level,
    required this.equipment,
    required this.views,
    required this.status,
    required this.sets,
    required this.reps,
    required this.seconds,
    required this.metric,
    required this.thresholds,
    required this.hold,
    required this.rules,
    required this.muscles,
    required this.tips,
    required this.mistakes,
    required this.cameraTip,
    required this.keyframes,
    required this.type,
    this.premium = false,
    this.focus = const ['shoulder', 'elbow', 'wrist', 'hip', 'knee', 'ankle'],
    this.region = 'full',
  });

  bool get isTimed => mode == ExerciseMode.timed;
  bool get isValidated => status == 'validated';

  /// Muscle weights normalised to sum to 1.
  Map<String, double> get normalisedMuscles {
    final total = muscles.values.fold<double>(0, (a, b) => a + b);
    if (total <= 0) return {};
    return muscles.map((k, v) => MapEntry(k, v / total));
  }

  String get primaryMuscle {
    var best = '';
    var w = -1.0;
    muscles.forEach((k, v) {
      if (v > w) {
        w = v;
        best = k;
      }
    });
    return best;
  }

  String get targetLabel => isTimed ? '$sets sets x ${seconds}s' : '$sets sets x $reps reps';

  /// Upper-body exercises are tracked from about 1 m (head to hips).
  bool get isUpperBody => region == 'upper';

  /// Suggested phone distance in metres for the camera setup.
  double get cameraDistance {
    switch (region) {
      case 'upper':
        return 1.0;
      case 'floor':
        return 1.8;
      default:
        return 1.5;
    }
  }

  /// Common mistakes with how to fix each one ("Mistake|Fix" in the data).
  List<({String mistake, String fix})> get mistakeFixes => mistakes.map((m) {
        final i = m.indexOf('|');
        return i < 0 ? (mistake: m, fix: '') : (mistake: m.substring(0, i), fix: m.substring(i + 1));
      }).toList();

  String get groupLabel => ExerciseCatalog.groupLabel(group);

  factory ExerciseDef.fromJson(Map<String, dynamic> j) {
    final defaults = (j['defaults'] as Map<String, dynamic>?) ?? const {};
    final hold = <String, Condition>{};
    ((j['hold'] as Map<String, dynamic>?) ?? const {}).forEach((k, v) => hold[k] = Condition.fromJson(v));
    return ExerciseDef(
      id: j['id'] as String,
      name: j['name'] as String,
      group: j['group'] as String,
      mode: j['mode'] == 'timed' ? ExerciseMode.timed : ExerciseMode.reps,
      level: (j['level'] as num).toInt(),
      equipment: (j['equipment'] as List).cast<String>(),
      views: (j['views'] as List).map((v) => v == 'front' ? CameraView.front : CameraView.side).toList(),
      status: (j['status'] as String?) ?? 'beta',
      sets: (defaults['sets'] as num?)?.toInt() ?? 3,
      reps: (defaults['reps'] as num?)?.toInt() ?? 10,
      seconds: (defaults['seconds'] as num?)?.toInt() ?? 30,
      metric: MetricDef.fromJson(j['metric'] as Map<String, dynamic>),
      thresholds: Thresholds.fromJson(j['thresholds'] as Map<String, dynamic>),
      hold: hold,
      rules: ((j['rules'] as List?) ?? const []).map((r) => RuleDef.fromJson(r as Map<String, dynamic>)).toList(),
      muscles: (j['muscles'] as Map<String, dynamic>).map((k, v) => MapEntry(k, (v as num).toDouble())),
      tips: ((j['tips'] as List?) ?? const []).cast<String>(),
      mistakes: ((j['mistakes'] as List?) ?? const []).cast<String>(),
      cameraTip: (j['cameraTip'] as String?) ?? 'Place the phone side-on, about 1.5 m away, at hip height.',
      keyframes: Keyframes.fromJson(j['keyframes'] as Map<String, dynamic>),
      type: (j['type'] as String?) ?? 'bodyweight',
      premium: (j['premium'] as bool?) ?? false,
      focus: ((j['focus'] as List?) ?? const ['shoulder', 'elbow', 'wrist', 'hip', 'knee', 'ankle']).cast<String>(),
      region: (j['region'] as String?) ?? 'full',
    );
  }
}

class ExerciseCatalog {
  final List<ExerciseDef> exercises;
  final Map<String, String> cues;
  ExerciseCatalog(this.exercises, this.cues);

  ExerciseDef? byId(String id) {
    for (final e in exercises) {
      if (e.id == id) return e;
    }
    return null;
  }

  factory ExerciseCatalog.fromJson(Map<String, dynamic> j) => ExerciseCatalog(
        (j['exercises'] as List).map((e) => ExerciseDef.fromJson(e as Map<String, dynamic>)).toList(),
        (j['cues'] as Map<String, dynamic>).map((k, v) => MapEntry(k, v as String)),
      );

  List<ExerciseDef> inGroup(String group) => exercises.where((e) => e.group == group).toList();

  int get premiumCount => exercises.where((e) => e.premium).length;

  /// Muscle sections shown in the library (doc item 8).
  static const groups = ['chest', 'back', 'shoulders', 'arms', 'abs', 'legs', 'glutes', 'cardio'];
  static const equipmentTypes = ['bodyweight', 'dumbbells', 'barbell', 'bench', 'pull-up bar', 'wall', 'mat'];
  static const types = ['bodyweight', 'strength', 'isometric', 'cardio'];

  static String groupLabel(String g) {
    switch (g) {
      case 'abs':
        return 'Abs & Core';
      case 'cardio':
        return 'Cardio';
      default:
        return g[0].toUpperCase() + g.substring(1);
    }
  }

  static String typeLabel(String t) {
    switch (t) {
      case 'strength':
        return 'Weights';
      case 'isometric':
        return 'Holds';
      case 'cardio':
        return 'Cardio';
      default:
        return 'Bodyweight';
    }
  }

  static String equipmentLabel(String e) {
    switch (e) {
      case 'pull-up bar':
        return 'Pull-up bar';
      case 'mat':
        return 'Mat';
      default:
        return e[0].toUpperCase() + e.substring(1);
    }
  }
}
