/// A lightweight success/failure wrapper mirroring Kotlin's `Result`, used so
/// network calls can surface friendly messages instead of throwing.
class Result<T> {
  const Result._(this._value, this.errorMessage, {this.isOffline = false});

  static const String offlineMessage = 'No internet connection';

  factory Result.success(T value) => Result<T>._(value, null);

  factory Result.failure(String message, {bool isOffline = false}) =>
      Result<T>._(null, message, isOffline: isOffline);

  factory Result.offline([String message = offlineMessage]) =>
      Result<T>._(null, message, isOffline: true);

  final T? _value;
  final String? errorMessage;
  final bool isOffline;

  bool get isSuccess => errorMessage == null;

  bool get isFailure => errorMessage != null;

  /// The value of a successful result. Only call after checking [isSuccess].
  T get value => _value as T;

  T? get valueOrNull => _value;
}
