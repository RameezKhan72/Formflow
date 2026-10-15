import 'profile.dart';

class MacroPlan {
  final double bmr;
  final double maintenance;
  final double target;
  final double proteinG;
  final double fatG;
  final double carbsG;
  final double waterL;
  final bool floorApplied;
  final bool deficitBlocked;
  final double bmi;
  const MacroPlan({
    required this.bmr,
    required this.maintenance,
    required this.target,
    required this.proteinG,
    required this.fatG,
    required this.carbsG,
    required this.waterL,
    required this.floorApplied,
    required this.deficitBlocked,
    required this.bmi,
  });
}

class Meal {
  final String name;
  final int minutes; // minutes after midnight
  final String foods;
  final int kcal;
  const Meal(this.name, this.minutes, this.foods, this.kcal);
}

class TrainingStyle {
  final String sets;
  final String reps;
  final String rest;
  const TrainingStyle(this.sets, this.reps, this.rest);
}

class VitaminNeed {
  final String name;
  final String amount;
  final String sources;
  const VitaminNeed(this.name, this.amount, this.sources);
}

/// Nutrition maths (FR-NU-01..07, FR-VT-01). General guidance only.
class Nutrition {
  static final activityFactors = <double, String>{
    1.2: 'Sedentary',
    1.375: 'Lightly active',
    1.55: 'Moderately active',
    1.725: 'Very active',
  };

  static double cuttingPercent = 0.15;
  static double bulkingPercent = 0.10;

  /// Mifflin-St Jeor.
  static double bmr(UserProfile p) =>
      10 * p.weightKg + 6.25 * p.heightCm - 5 * p.age + (p.sex == Sex.male ? 5 : -161);

  static double calorieFloor(Sex s) => s == Sex.male ? 1500 : 1200;

  static MacroPlan plan(UserProfile p) {
    final b = bmr(p);
    final maint = b * p.activityFactor;
    final heightM = p.heightCm / 100;
    final bmi = p.weightKg / (heightM * heightM);
    var goal = p.goal.nutritionGoal;
    var deficitBlocked = false;
    if (goal == Goal.cutting && bmi < 18.5) {
      goal = Goal.normal; // no deficit messaging for a low BMI (FR-NU-04)
      deficitBlocked = true;
    }
    double target;
    switch (goal) {
      case Goal.cutting:
        target = maint * (1 - cuttingPercent);
        break;
      case Goal.bulking:
        target = maint * (1 + bulkingPercent);
        break;
      default:
        target = maint;
    }
    var floorApplied = false;
    final floor = calorieFloor(p.sex);
    if (target < floor) {
      target = floor;
      floorApplied = true;
    }
    final proteinPerKg = goal == Goal.cutting ? 2.2 : (goal == Goal.bulking ? 2.0 : 1.8);
    final fatPerKg = goal == Goal.cutting ? 0.8 : (goal == Goal.bulking ? 1.0 : 0.9);
    final protein = proteinPerKg * p.weightKg;
    final fat = fatPerKg * p.weightKg;
    final carbs = ((target - protein * 4 - fat * 9) / 4).clamp(0, double.infinity).toDouble();
    return MacroPlan(
      bmr: b,
      maintenance: maint,
      target: target,
      proteinG: protein,
      fatG: fat,
      carbsG: carbs,
      waterL: p.weightKg * 35 / 1000,
      floorApplied: floorApplied,
      deficitBlocked: deficitBlocked,
      bmi: bmi,
    );
  }

  static TrainingStyle trainingStyle(Goal g) {
    switch (g.nutritionGoal) {
      case Goal.cutting:
        return const TrainingStyle('3-4 sets', '12-15 reps', '45 s rest');
      case Goal.bulking:
        return const TrainingStyle('4 sets', '6-10 reps', '90-120 s rest');
      default:
        return const TrainingStyle('3 sets', '10-12 reps', '60-90 s rest');
    }
  }

  /// 5 meals (cutting / normal) or 6 (bulking), timed around the workout.
  static List<Meal> mealPlan(UserProfile p) {
    final plan = Nutrition.plan(p);
    final w = p.slotMinutes;
    final bulking = p.goal.nutritionGoal == Goal.bulking;
    final cutting = p.goal.nutritionGoal == Goal.cutting;
    int t(int m) => ((m % 1440) + 1440) % 1440;
    final kcal = plan.target;
    final meals = <Meal>[
      Meal('Breakfast', t(7 * 60 + 30),
          cutting ? '2 eggs + 2 egg whites, 1 whole-wheat roti, green tea' : '3 eggs, 2 whole-wheat roti, glass of milk',
          (kcal * 0.22).round()),
      Meal('Lunch', t(13 * 60),
          cutting ? 'Grilled chicken 150 g, 1 cup daal, salad, 1 roti' : 'Chicken curry 150 g, 1 cup rice, daal, salad',
          (kcal * 0.27).round()),
      Meal('Pre-workout', t(w - 90), 'Banana and a bowl of yogurt (dahi) with oats', (kcal * 0.13).round()),
      Meal('Post-workout', t(w + 60),
          cutting ? 'Chicken 150 g with vegetables, 1 roti' : 'Chicken or beef 150 g, rice or 2 roti, milk',
          (kcal * 0.25).round()),
      Meal('Snack', t(w + 210), cutting ? 'Greek yogurt with guava' : 'Peanut butter on brown bread, a fruit',
          (kcal * (bulking ? 0.07 : 0.13)).round()),
    ];
    if (bulking) {
      meals.add(Meal('Before bed', t(w + 300), 'Milk with a handful of almonds and dates', (kcal * 0.06).round()));
    }
    meals.sort((a, b) => a.minutes.compareTo(b.minutes));
    return meals;
  }

  /// Sex- and age-specific daily needs (US NIH Dietary Reference Intakes).
  static List<VitaminNeed> vitamins(Sex sex, int age) {
    final m = sex == Sex.male;
    return [
      VitaminNeed('Vitamin A', m ? '900 mcg' : '700 mcg', 'Carrots, spinach, eggs, mango'),
      VitaminNeed('Vitamin C', m ? '90 mg' : '75 mg', 'Guava, oranges, lemon, tomatoes'),
      VitaminNeed('Vitamin D', age > 70 ? '20 mcg (800 IU)' : '15 mcg (600 IU)', 'Sunlight, eggs, fortified milk, fish'),
      VitaminNeed('Vitamin E', '15 mg', 'Almonds, sunflower seeds, spinach'),
      VitaminNeed('Vitamin K', m ? '120 mcg' : '90 mcg', 'Spinach, cabbage, broccoli'),
      VitaminNeed('Vitamin B12', '2.4 mcg', 'Eggs, milk, yogurt, chicken, beef'),
      VitaminNeed('Folate', '400 mcg', 'Daal, chickpeas, spinach'),
      VitaminNeed('Calcium', (!m && age > 50) || age > 70 ? '1200 mg' : '1000 mg', 'Milk, yogurt, paneer'),
      VitaminNeed('Iron', !m && age <= 50 ? '18 mg' : '8 mg', 'Daal, chickpeas, spinach, beef, liver'),
      VitaminNeed('Magnesium', m ? (age <= 30 ? '400 mg' : '420 mg') : (age <= 30 ? '310 mg' : '320 mg'),
          'Nuts, whole-wheat roti, bananas'),
      VitaminNeed('Zinc', m ? '11 mg' : '8 mg', 'Beef, chickpeas, pumpkin seeds'),
      VitaminNeed('Potassium', m ? '3400 mg' : '2600 mg', 'Bananas, potatoes, daal'),
    ];
  }

  static const disclaimer =
      'General guidance for healthy adults, not medical advice. Food comes first; talk to a doctor before taking supplements.';
}
