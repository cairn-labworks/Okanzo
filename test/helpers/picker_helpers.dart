import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Future<List<String>> pickerLabels(WidgetTester tester, Finder picker) async {
  await tester.ensureVisible(picker);
  await tester.pumpAndSettle();
  await tester.tap(picker);
  await tester.pumpAndSettle();
  final List<String> labels = tester
      .widgetList<ListTile>(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.byType(ListTile),
        ),
      )
      .map((ListTile tile) {
        final Widget? title = tile.title;
        if (title is Text && title.data != null) return title.data!;
        throw StateError('Unexpected picker label widget');
      })
      .toList();
  await tester.tap(
    find.descendant(
      of: find.byType(AlertDialog),
      matching: find.widgetWithText(TextButton, 'Close'),
    ),
  );
  await tester.pumpAndSettle();
  return labels;
}
