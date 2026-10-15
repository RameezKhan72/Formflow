// Entry kept so `flutter create` does not generate a default counter test.
import 'package:flutter_test/flutter_test.dart';
import 'package:formflow/domain/geometry.dart';

void main() {
  test('sanity', () => expect(angleAt(const Vec2(0, 1), const Vec2(0, 0), const Vec2(1, 0)), closeTo(90, 1e-9)));
}
