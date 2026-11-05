import 'dart:io';

import 'package:integration_test/integration_test_driver_extended.dart';

Future<void> main() async {
  const Set<String> expected = <String>{
    'exchange-picker',
    'bse-quote',
    'global-portfolio',
    'preferred-exchanges',
    'empty-exchanges',
  };
  const List<int> pngHeader = <int>[137, 80, 78, 71, 13, 10, 26, 10];
  final Set<String> captured = <String>{};

  await integrationDriver(
    onScreenshot:
        (String name, List<int> image, [Map<String, Object?>? args]) async {
          if (!expected.contains(name) || captured.contains(name)) {
            throw StateError('Unexpected or duplicate screenshot: $name');
          }
          if (image.length < pngHeader.length) {
            throw StateError('Empty screenshot: $name');
          }
          for (int index = 0; index < pngHeader.length; index++) {
            if (image[index] != pngHeader[index]) {
              throw StateError('Screenshot is not a PNG: $name');
            }
          }
          final File file = File('marketing/screenshots/exchanges/$name.png');
          await file.parent.create(recursive: true);
          await file.writeAsBytes(image, flush: true);
          captured.add(name);
          return true;
        },
    responseDataCallback: (_) {
      if (captured.length != expected.length) {
        throw StateError(
          'Expected ${expected.length} screenshots; got $captured',
        );
      }
    },
  );
}
