import 'dart:io';

import 'package:integration_test/integration_test_driver_extended.dart';

/// Saves screenshots taken by integration_test/screenshots_test.dart.
Future<void> main() async {
  await integrationDriver(
    onScreenshot: (String name, List<int> bytes, [Map<String, Object?>? args]) async {
      final file = await File('screenshots_out/$name.png').create(recursive: true);
      await file.writeAsBytes(bytes);
      return true;
    },
  );
}
