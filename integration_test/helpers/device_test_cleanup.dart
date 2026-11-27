import 'package:shared_preferences/shared_preferences.dart';

typedef DeviceTestCleanupStep = (String, Future<void> Function());

Future<void> runDeviceTestCleanup(Iterable<DeviceTestCleanupStep> steps) async {
  final List<(String, Object, StackTrace)> failures =
      <(String, Object, StackTrace)>[];
  for (final (String label, Future<void> Function() action) in steps) {
    try {
      await action();
    } on Object catch (error, stackTrace) {
      failures.add((label, error, stackTrace));
    }
  }
  if (failures.isNotEmpty) {
    Error.throwWithStackTrace(
      StateError(
        'Device-test cleanup failed:\n'
        '${failures.map((failure) => '${failure.$1}: ${failure.$2}').join('\n')}',
      ),
      failures.first.$3,
    );
  }
}

Future<void> restoreDeviceTestPreference(
  SharedPreferences preferences,
  String key,
  Object? value,
) async {
  final bool restored = switch (value) {
    null => await preferences.remove(key),
    final String text => await preferences.setString(key, text),
    final bool flag => await preferences.setBool(key, flag),
    final int number => await preferences.setInt(key, number),
    final double number => await preferences.setDouble(key, number),
    final List<String> values => await preferences.setStringList(key, values),
    _ => throw StateError('Unsupported preference type for $key'),
  };
  if (!restored) throw StateError('Could not restore preference $key');
}
