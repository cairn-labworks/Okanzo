import 'dart:io';

import 'package:integration_test/integration_test_driver_extended.dart';

Future<void> main() => integrationDriver(
  onScreenshot:
      (String name, List<int> bytes, [Map<String, Object?>? args]) async {
        final String? directory = Platform.environment['APP_LOCK_EVIDENCE'];
        if (directory == null) {
          throw StateError(
            'APP_LOCK_EVIDENCE must name the screenshot directory',
          );
        }
        await Directory(directory).create(recursive: true);
        await File('$directory${Platform.pathSeparator}$name.png')
            .writeAsBytes(bytes);
        return true;
      },
);
