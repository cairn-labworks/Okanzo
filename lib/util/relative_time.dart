import 'package:intl/intl.dart';

import '../l10n/app_localizations.dart';

/// Human-friendly "time ago" label for the exchange-rate timestamp.
///
/// Mirrors Android's `DateUtils.getRelativeTimeSpanString` closely enough for
/// the settings row: minute resolution, "Yesterday" for one day, then a short
/// date once the timestamp is more than a week old.
String relativeTimeSpan(
  int epochMillis, {
  AppLocalizations? localizations,
  DateTime? now,
}) {
  final DateTime moment = DateTime.fromMillisecondsSinceEpoch(epochMillis);
  final DateTime reference = now ?? DateTime.now();
  final int deltaMillis = reference.millisecondsSinceEpoch - epochMillis;
  final AppLocalizations strings =
      localizations ?? AppLocalizations.fromLocaleName(Intl.getCurrentLocale());
  String date() => DateFormat.yMMMd(strings.locale.toString()).format(moment);
  if (deltaMillis < 0) return date();

  const int minute = 60 * 1000;
  const int hour = 60 * minute;
  const int day = 24 * hour;

  if (deltaMillis < minute) return strings.text('0 minutes ago');
  if (deltaMillis < hour) {
    final int minutes = deltaMillis ~/ minute;
    return minutes == 1
        ? strings.text('1 minute ago')
        : strings.text('{count} minutes ago').replaceAll('{count}', '$minutes');
  }
  if (deltaMillis < day) {
    final int hours = deltaMillis ~/ hour;
    return hours == 1
        ? strings.text('1 hour ago')
        : strings.text('{count} hours ago').replaceAll('{count}', '$hours');
  }
  final int days = deltaMillis ~/ day;
  if (days == 1) return strings.text('Yesterday');
  if (days < 7) {
    return strings.text('{count} days ago').replaceAll('{count}', '$days');
  }
  return date();
}
