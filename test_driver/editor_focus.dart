import 'dart:io';

import 'package:integration_test/integration_test_driver_extended.dart';

Future<void> main() => integrationDriver(
  onScreenshot:
      (String name, List<int> bytes, [Map<String, Object?>? args]) async {
        final Directory directory = Directory(
          Platform.environment['EDITOR_FOCUS_EVIDENCE'] ??
              'build/editor-focus-evidence',
        );
        await directory.create(recursive: true);
        await File('${directory.path}${Platform.pathSeparator}$name.png')
            .writeAsBytes(bytes);
        return true;
      },
);
