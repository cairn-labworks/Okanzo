import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';

enum HoldingSort {
  custom,
  nameAscending,
  nameDescending,
  valueDescending,
  valueAscending,
}

extension HoldingSortLabel on HoldingSort {
  String get label => switch (this) {
    HoldingSort.custom => 'My arrangement',
    HoldingSort.nameAscending => 'Name / A to Z',
    HoldingSort.nameDescending => 'Name / Z to A',
    HoldingSort.valueDescending => 'Value / high to low',
    HoldingSort.valueAscending => 'Value / low to high',
  };
}

class HoldingGroupList<T> extends StatelessWidget {
  const HoldingGroupList({
    required this.items,
    required this.name,
    required this.value,
    required this.priced,
    required this.sort,
    required this.onSort,
    required this.onReordered,
    required this.itemBuilder,
    super.key,
  });

  final List<T> items;
  final String Function(T) name;
  final double Function(T) value;
  final bool Function(T) priced;
  final HoldingSort sort;
  final ValueChanged<HoldingSort> onSort;
  final Future<void> Function(List<T>) onReordered;
  final Widget Function(T) itemBuilder;

  List<T> get sorted {
    final List<T> result = List<T>.of(items);
    if (sort == HoldingSort.custom) return result;
    result.sort((T a, T b) {
      if (sort == HoldingSort.nameAscending ||
          sort == HoldingSort.nameDescending) {
        final int comparison = name(a)
            .toLowerCase()
            .compareTo(name(b).toLowerCase());
        return sort == HoldingSort.nameAscending ? comparison : -comparison;
      }
      if (priced(a) != priced(b)) return priced(a) ? -1 : 1;
      final int comparison = value(a).compareTo(value(b));
      if (comparison == 0) return name(a).compareTo(name(b));
      return sort == HoldingSort.valueAscending ? comparison : -comparison;
    });
    return result;
  }

  Future<void> _arrange(BuildContext context) async {
    final List<T> order = List<T>.of(items);
    bool saving = false;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (BuildContext sheetContext) => StatefulBuilder(
        builder: (BuildContext context, StateSetter setState) {
          Future<void> move(int from, int to) async {
            final List<T> next = List<T>.of(order);
            final T holding = next.removeAt(from);
            next.insert(to, holding);
            setState(() => saving = true);
            try {
              await onReordered(next);
              if (!context.mounted) return;
              setState(() {
                order
                  ..clear()
                  ..addAll(next);
                saving = false;
              });
              onSort(HoldingSort.custom);
            } on Object {
              if (!context.mounted) return;
              setState(() => saving = false);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('Could not save arrangement.'.tr(context)),
                ),
              );
            }
          }

          return SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Text(
                    'Arrange manually'.tr(context),
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 12),
                  ConstrainedBox(
                    constraints: BoxConstraints(
                      maxHeight: MediaQuery.sizeOf(context).height * .55,
                    ),
                    child: ListView(
                      shrinkWrap: true,
                      children: <Widget>[
                        for (int i = 0; i < order.length; i++)
                          ListTile(
                            contentPadding: EdgeInsets.zero,
                            title: Text(name(order[i])),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: <Widget>[
                                IconButton(
                                  tooltip: 'Move up'.tr(context),
                                  onPressed: saving || i == 0
                                      ? null
                                      : () => move(i, i - 1),
                                  icon: const Icon(Icons.keyboard_arrow_up),
                                ),
                                IconButton(
                                  tooltip: 'Move down'.tr(context),
                                  onPressed: saving || i == order.length - 1
                                      ? null
                                      : () => move(i, i + 1),
                                  icon: const Icon(Icons.keyboard_arrow_down),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ),
                  TextButton(
                    onPressed: saving
                        ? null
                        : () => Navigator.of(context).pop(),
                    child: Text('Done'.tr(context)),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsetsDirectional.only(start: 19, bottom: 12),
    padding: const EdgeInsetsDirectional.only(start: 12),
    decoration: BoxDecoration(
      border: BorderDirectional(
        start: BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
      ),
    ),
    child: Column(
      children: <Widget>[
        Row(
          children: <Widget>[
            Expanded(
              child: Text(
                'Your holdings'.tr(context),
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  fontSize: 10,
                  letterSpacing: .7,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ),
            PopupMenuButton<Object>(
              tooltip: 'Sort or arrange'.tr(context),
              icon: const Icon(Icons.more_horiz, size: 20),
              onSelected: (Object selected) {
                if (selected is HoldingSort) {
                  onSort(selected);
                } else {
                  _arrange(context);
                }
              },
              itemBuilder: (BuildContext context) => <PopupMenuEntry<Object>>[
                for (final HoldingSort option in HoldingSort.values)
                  CheckedPopupMenuItem<Object>(
                    value: option,
                    checked: option == sort,
                    child: Text(option.label.tr(context)),
                  ),
                const PopupMenuDivider(),
                PopupMenuItem<Object>(
                  value: 'arrange',
                  child: Text('Arrange manually'.tr(context)),
                ),
              ],
            ),
          ],
        ),
        for (final T item in sorted) itemBuilder(item),
      ],
    ),
  );
}
