import 'package:flutter_test/flutter_test.dart';
import 'package:formflow/domain/insights.dart';
import 'package:formflow/domain/nutrition.dart';
import 'package:formflow/domain/profile.dart';

void main() {
  group('TC-29: man, 21, 70 kg, 175 cm, activity 1.55, Cutting', () {
    const p = UserProfile(sex: Sex.male, age: 21, weightKg: 70, heightCm: 175, activityFactor: 1.55, goal: Goal.cutting);
    final plan = Nutrition.plan(p);
    test('BMR 1,694 kcal (Mifflin-St Jeor)', () => expect(plan.bmr.round(), 1694));
    test('maintenance 2,625 kcal', () => expect(plan.maintenance.round(), 2625));
    test('cutting about 2,232 kcal', () => expect(plan.target.round(), closeTo(2232, 1)));
    test('protein 154 g', () => expect(plan.proteinG.round(), 154));
    test('fat 56 g', () => expect(plan.fatG.round(), 56));
    test('carbohydrate about 278 g', () => expect(plan.carbsG.round(), closeTo(278, 1)));
    test('water 2.45 L', () => expect(plan.waterL, closeTo(2.45, 1e-9)));
  });

  test('women use -161 in the BMR formula', () {
    const p = UserProfile(sex: Sex.female, age: 30, weightKg: 60, heightCm: 165);
    expect(Nutrition.bmr(p), closeTo(10 * 60 + 6.25 * 165 - 5 * 30 - 161, 1e-9));
  });

  test('bulking is 10% above maintenance with 2.0 g/kg protein', () {
    const p = UserProfile(weightKg: 80, goal: Goal.bulking);
    final plan = Nutrition.plan(p);
    expect(plan.target, closeTo(plan.maintenance * 1.10, 1e-6));
    expect(plan.proteinG, closeTo(160, 1e-9));
    expect(plan.fatG, closeTo(80, 1e-9));
  });

  test('calorie floor is applied (FR-NU-04)', () {
    const p = UserProfile(sex: Sex.female, age: 60, weightKg: 45, heightCm: 150, activityFactor: 1.2, goal: Goal.cutting);
    final plan = Nutrition.plan(p);
    expect(plan.target, greaterThanOrEqualTo(1200));
  });

  test('no deficit for a low BMI (FR-NU-04)', () {
    const p = UserProfile(weightKg: 50, heightCm: 180, goal: Goal.cutting);
    final plan = Nutrition.plan(p);
    expect(plan.bmi, lessThan(18.5));
    expect(plan.deficitBlocked, isTrue);
    expect(plan.target, closeTo(plan.maintenance, 1e-6));
  });

  test('meal plan: 5 meals normal/cutting, 6 bulking (FR-NU-05)', () {
    expect(Nutrition.mealPlan(const UserProfile(goal: Goal.cutting)), hasLength(5));
    expect(Nutrition.mealPlan(const UserProfile(goal: Goal.normal)), hasLength(5));
    expect(Nutrition.mealPlan(const UserProfile(goal: Goal.bulking)), hasLength(6));
  });

  test('pre-workout meal is 90 minutes before the workout', () {
    final meals = Nutrition.mealPlan(const UserProfile(slotMinutes: 18 * 60));
    expect(meals.firstWhere((m) => m.name == 'Pre-workout').minutes, 16 * 60 + 30);
  });

  test('training style per goal (FR-NU-06)', () {
    expect(Nutrition.trainingStyle(Goal.cutting).reps, '12-15 reps');
    expect(Nutrition.trainingStyle(Goal.normal).rest, '60-90 s rest');
    expect(Nutrition.trainingStyle(Goal.bulking).sets, '4 sets');
  });

  test('vitamins are sex- and age-specific (FR-VT-01)', () {
    String iron(Sex s, int age) => Nutrition.vitamins(s, age).firstWhere((v) => v.name == 'Iron').amount;
    expect(iron(Sex.female, 30), '18 mg');
    expect(iron(Sex.female, 55), '8 mg');
    expect(iron(Sex.male, 30), '8 mg');
    expect(Nutrition.disclaimer, contains('doctor'));
  });

  test('daily timeline offsets (FR-TP-01)', () {
    final t = DayPlan.timeline(18 * 60);
    expect(t.map((e) => e.minutes - 18 * 60).toList(), [-90, -15, 0, 45, 60]);
    expect(DayPlan.clock(18 * 60), '6:00 PM');
    expect(DayPlan.clock(6 * 60), '6:00 AM');
    expect(DayPlan.clock(0), '12:00 AM');
  });
}
