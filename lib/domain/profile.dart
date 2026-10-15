enum Sex { male, female }

enum Goal { buildMuscle, cutting, normal, bulking }

extension GoalX on Goal {
  String get label {
    switch (this) {
      case Goal.buildMuscle:
        return 'Build muscle';
      case Goal.cutting:
        return 'Cutting';
      case Goal.normal:
        return 'Normal';
      case Goal.bulking:
        return 'Bulking';
    }
  }

  /// Nutrition maths treats "Build muscle" like a lean bulk.
  Goal get nutritionGoal => this == Goal.buildMuscle ? Goal.bulking : this;
}

class UserProfile {
  final String name;
  final String email;
  final Sex sex;
  final int age;
  final double heightCm;
  final double weightKg;
  final Goal goal;
  final int weeklyTarget;
  final int slotMinutes; // minutes after midnight for the workout
  final double activityFactor;
  final bool useLb;
  final bool guest;

  const UserProfile({
    this.name = 'Athlete',
    this.email = '',
    this.sex = Sex.male,
    this.age = 21,
    this.heightCm = 175,
    this.weightKg = 70,
    this.goal = Goal.buildMuscle,
    this.weeklyTarget = 5,
    this.slotMinutes = 18 * 60,
    this.activityFactor = 1.55,
    this.useLb = false,
    this.guest = true,
  });

  UserProfile copyWith({
    String? name,
    String? email,
    Sex? sex,
    int? age,
    double? heightCm,
    double? weightKg,
    Goal? goal,
    int? weeklyTarget,
    int? slotMinutes,
    double? activityFactor,
    bool? useLb,
    bool? guest,
  }) =>
      UserProfile(
        name: name ?? this.name,
        email: email ?? this.email,
        sex: sex ?? this.sex,
        age: age ?? this.age,
        heightCm: heightCm ?? this.heightCm,
        weightKg: weightKg ?? this.weightKg,
        goal: goal ?? this.goal,
        weeklyTarget: weeklyTarget ?? this.weeklyTarget,
        slotMinutes: slotMinutes ?? this.slotMinutes,
        activityFactor: activityFactor ?? this.activityFactor,
        useLb: useLb ?? this.useLb,
        guest: guest ?? this.guest,
      );

  String get weightLabel =>
      useLb ? '${(weightKg * 2.20462).toStringAsFixed(1)} lb' : '${weightKg.toStringAsFixed(1)} kg';

  Map<String, dynamic> toJson() => {
        'name': name,
        'email': email,
        'sex': sex.name,
        'age': age,
        'heightCm': heightCm,
        'weightKg': weightKg,
        'goal': goal.name,
        'weeklyTarget': weeklyTarget,
        'slotMinutes': slotMinutes,
        'activityFactor': activityFactor,
        'useLb': useLb,
        'guest': guest,
      };

  /// Defaults are used only for missing values (FR-PR-02).
  factory UserProfile.fromJson(Map<String, dynamic> j) {
    const d = UserProfile();
    return UserProfile(
      name: (j['name'] as String?) ?? d.name,
      email: (j['email'] as String?) ?? d.email,
      sex: j['sex'] == 'female' ? Sex.female : Sex.male,
      age: (j['age'] as num?)?.toInt() ?? d.age,
      heightCm: (j['heightCm'] as num?)?.toDouble() ?? d.heightCm,
      weightKg: (j['weightKg'] as num?)?.toDouble() ?? d.weightKg,
      goal: Goal.values.firstWhere((g) => g.name == j['goal'], orElse: () => d.goal),
      weeklyTarget: (j['weeklyTarget'] as num?)?.toInt() ?? d.weeklyTarget,
      slotMinutes: (j['slotMinutes'] as num?)?.toInt() ?? d.slotMinutes,
      activityFactor: (j['activityFactor'] as num?)?.toDouble() ?? d.activityFactor,
      useLb: (j['useLb'] as bool?) ?? false,
      guest: (j['guest'] as bool?) ?? true,
    );
  }
}

/// Input validation (FR-AU-03, NFR-SC-04). Returns an error message or null.
class Validators {
  static final _email = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]{2,}$');

  static String? name(String? v) {
    final s = v?.trim() ?? '';
    if (s.isEmpty) return 'Please enter your name';
    if (s.length > 40) return 'Name is too long';
    return null;
  }

  static String? email(String? v) {
    final s = v?.trim() ?? '';
    if (s.isEmpty) return 'Please enter your email';
    if (!_email.hasMatch(s)) return 'That email address doesn\'t look right';
    return null;
  }

  static String? password(String? v) {
    if ((v ?? '').length < 6) return 'Password must be at least 6 characters';
    return null;
  }

  static String? age(int? v) {
    if (v == null) return 'Please enter your age';
    if (v < 18) return 'FormFlow is for adults aged 18 and over';
    if (v > 100) return 'Please enter a valid age';
    return null;
  }

  static String? range(double? v, double min, double max, String label) {
    if (v == null) return 'Please enter your $label';
    if (v < min || v > max) return 'Please enter a $label between ${min.round()} and ${max.round()}';
    return null;
  }
}
