import 'dart:async';
import 'dart:io';

import 'package:http/http.dart' as http;

/// Returns true when [error] indicates missing network connectivity rather
/// than an HTTP status or payload error from a reachable server.
bool isOfflineError(Object error) {
  if (error is SocketException || error is TimeoutException) return true;
  if (error is http.ClientException) {
    return !error.message.trim().startsWith('HTTP ');
  }
  return false;
}

/// Shared HTTP client: adds the app's identifying headers and a hard call
/// timeout, matching the OkHttp configuration used by the Android app.
class ApiClient extends http.BaseClient {
  ApiClient({http.Client? inner, this.timeout = const Duration(seconds: 15)})
    : _inner = inner ?? http.Client();

  final http.Client _inner;
  final Duration timeout;

  static String get userAgent {
    final String platform = Platform.isIOS
        ? 'iOS'
        : Platform.isAndroid
        ? 'Android'
        : Platform.operatingSystem;
    return 'Okanzo/1.0 ($platform)';
  }

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    request.headers.putIfAbsent('User-Agent', () => userAgent);
    request.headers.putIfAbsent('Accept', () => 'application/json');
    return _inner.send(request).timeout(timeout);
  }

  @override
  void close() {
    _inner.close();
    super.close();
  }
}
