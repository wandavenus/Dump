import 'dart:async';

import 'package:http/http.dart' as http;

import '../../../services/log_service.dart';
import '../cancellation.dart';
import '../rate_limiter.dart';

/// Helper HTTP dengan:
/// - Connect timeout: 5 detik
/// - Read timeout: 15 detik
/// - Retry maksimal 2 kali (exponential backoff)
/// - Retry hanya untuk timeout / 5xx / connection error
/// - Tidak retry untuk 4xx
class ProviderHttp {
  static const _readTimeout = Duration(seconds: 15);
  static const int _maxRetries = 2;

  static final http.Client _client = http.Client();

  /// GET dengan timeout, retry, dan cancellation.
  static Future<http.Response?> get(
    Uri uri,
    String providerName,
    CancellationToken cancelToken, {
    Map<String, String>? headers,
  }) async {
    for (int attempt = 0; attempt <= _maxRetries; attempt++) {
      if (cancelToken.isCancelled) return null;
      if (ProviderRateLimiter.instance.isLimited(providerName)) return null;

      // Exponential backoff untuk retry
      if (attempt > 0) {
        final delay = Duration(milliseconds: 1000 * attempt);
        LogService.verbose(
          providerName,
          'Retry $attempt/$_maxRetries setelah ${delay.inMilliseconds}ms',
        );
        await Future.delayed(delay);
        if (cancelToken.isCancelled) return null;
      }

      try {
        final sw = Stopwatch()..start();
        final response = await cancelToken.guardFuture(
          _client.get(uri, headers: headers).timeout(_readTimeout),
        );
        LogService.verbose(
          providerName,
          'HTTP ${response.statusCode} ${uri.host} ${sw.elapsedMilliseconds}ms',
        );

        // Jangan retry 4xx
        if (response.statusCode >= 400 && response.statusCode < 500) {
          return response;
        }

        // Jangan retry 2xx/3xx
        if (response.statusCode < 400) return response;

        // 5xx → retry
        LogService.verbose(
          providerName,
          'HTTP ${response.statusCode} — akan retry',
        );
      } on CancelledException {
        return null;
      } on TimeoutException {
        LogService.verbose(providerName, 'Timeout attempt $attempt');
      } catch (e) {
        if (cancelToken.isCancelled) return null;
        LogService.verbose(
          providerName,
          'Connection error attempt $attempt: $e',
        );
      }
    }
    return null;
  }

  /// POST dengan timeout, retry, dan cancellation.
  static Future<http.Response?> post(
    Uri uri,
    String providerName,
    CancellationToken cancelToken, {
    Map<String, String>? headers,
    Object? body,
  }) async {
    for (int attempt = 0; attempt <= _maxRetries; attempt++) {
      if (cancelToken.isCancelled) return null;

      if (attempt > 0) {
        await Future.delayed(Duration(milliseconds: 1000 * attempt));
        if (cancelToken.isCancelled) return null;
      }

      try {
        final response = await cancelToken.guardFuture(
          _client.post(uri, headers: headers, body: body).timeout(_readTimeout),
        );
        if (response.statusCode >= 400 && response.statusCode < 500) {
          return response;
        }
        if (response.statusCode < 400) return response;
      } on CancelledException {
        return null;
      } on TimeoutException {
        LogService.verbose(providerName, 'POST Timeout attempt $attempt');
      } catch (e) {
        if (cancelToken.isCancelled) return null;
      }
    }
    return null;
  }
}
