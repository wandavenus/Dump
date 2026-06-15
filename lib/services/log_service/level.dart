part of '../log_service.dart';

enum LogLevel {
  verbose,
  debug,
  info,
  warning,
  error;

  String get prefix => switch (this) {
    verbose => 'VRB',
    debug   => 'DBG',
    info    => 'INF',
    warning => 'WRN',
    error   => 'ERR',
  };
}
