import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import '../test/app_lock_test.dart' as scenarios;

void main() {
  final IntegrationTestWidgetsFlutterBinding binding =
      IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  final List<Map<String, Object>> screenshots = <Map<String, Object>>[];
  binding.reportData = <String, Object>{'screenshots': screenshots};
  scenarios.main(
    deviceViewport: true,
    capture: (WidgetTester tester, String name) async {
      final RenderRepaintBoundary boundary = tester.renderObject(
        find.byKey(const ValueKey<String>('app-lock-evidence')),
      );
      final ui.Image image = await boundary.toImage(
        pixelRatio: tester.view.devicePixelRatio,
      );
      try {
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        if (bytes == null) throw StateError('App screenshot encoding failed');
        screenshots.add(<String, Object>{
          'screenshotName': name,
          'bytes': bytes.buffer.asUint8List(),
        });
      } finally {
        image.dispose();
      }
    },
  );
}
