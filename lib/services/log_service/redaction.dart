part of '../log_service.dart';

/// Central redaction for log messages.
///
/// Absolute device paths and URIs may reveal a user's folder names, account
/// fragments, or listening files. Feature code should still avoid putting
/// private values into messages; this is the last line of defence for values
/// that arrive from platform channels or exception text.
abstract final class LogRedaction {
  static final RegExp _uriPattern = RegExp(
    r'''(?:content|file|https?|rtsp|ftp)://[^\s<>"')\]}]+''',
    caseSensitive: false,
  );

  static final RegExp _absolutePathPattern = RegExp(
    r'''(?<![\w])(?:/(?:storage|sdcard|data|mnt|proc|system|vendor|odm|product|run|tmp|var|opt|home|root|android|apex|dev|sys|etc|usr|local)(?:/[^\s<>"'|,;)\]}]*)?)(?![\w])''',
    caseSensitive: false,
  );

  static String apply(String input) => input
      .replaceAll(_uriPattern, '<uri>')
      .replaceAll(_absolutePathPattern, '<path>');
}
