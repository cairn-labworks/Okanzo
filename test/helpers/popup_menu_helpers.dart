import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

List<String> popupMenuLabels<T>(WidgetTester tester) {
  final Finder finder = find.byType(PopupMenuButton<T>);
  final PopupMenuButton<T> menu = tester.widget<PopupMenuButton<T>>(finder);
  return menu
      .itemBuilder(tester.element(finder))
      .whereType<PopupMenuItem<T>>()
      .map((PopupMenuItem<T> item) {
        final Widget? child = item.child;
        if (child is Text && child.data != null) return child.data!;
        if (child is Row) {
          final Widget title = child.children
              .whereType<Expanded>()
              .single
              .child;
          if (title is Text && title.data != null) return title.data!;
        }
        throw StateError('Unexpected popup-menu label widget');
      })
      .toList();
}
