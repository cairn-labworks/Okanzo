import 'dart:io';

import 'package:integration_test/integration_test_driver_extended.dart';

Future<void> main() async {
  const Set<String> expected = <String>{
    'original-light',
    'original-dark',
    'sculpted-light-home',
    'sculpted-dark-home',
    'liquid-glass-light-home',
    'liquid-glass-dark-home',
    'liquid-glass-light-settings',
    'liquid-glass-dark-settings',
    'liquid-glass-light-form',
    'liquid-glass-dark-form',
    'liquid-glass-light-details',
    'liquid-glass-dark-details',
  };
  final Set<String> captured = <String>{};
  final Directory output = Directory(
    Platform.environment['THEME_SCREENSHOT_DIR'] ?? 'build/theme-screenshots',
  );
  await output.create(recursive: true);
  await integrationDriver(
    onScreenshot:
        (String name, List<int> image, [Map<String, Object?>? args]) async {
          if (!expected.contains(name) || captured.contains(name)) {
            throw StateError('Unexpected or duplicate screenshot: $name');
          }
          const List<int> header = <int>[137, 80, 78, 71, 13, 10, 26, 10];
          if (image.length < header.length) {
            throw StateError('Screenshot is not a PNG: $name');
          }
          for (int index = 0; index < header.length; index++) {
            if (image[index] != header[index]) {
              throw StateError('Screenshot is not a PNG: $name');
            }
          }
          await File('${output.path}/$name.png')
              .writeAsBytes(image, flush: true);
          captured.add(name);
          return true;
        },
    responseDataCallback: (_) {
      if (captured.length != expected.length) {
        throw StateError(
          'Missing theme screenshots: ${expected.difference(captured)}',
        );
      }
    },
  );
}
