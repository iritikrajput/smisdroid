import 'dart:developer' as developer;
import 'package:flutter/foundation.dart';

enum LogLevel { debug, info, warning, error }

class AppLogger {
  static const String _tag = 'SMISDroid';
  static bool _enabled = kDebugMode;

  static void enable() => _enabled = true;
  static void disable() => _enabled = false;

  static void debug(String message, {String? tag}) {
    _log(LogLevel.debug, message, tag: tag);
  }

  static void info(String message, {String? tag}) {
    _log(LogLevel.info, message, tag: tag);
  }

  static void warning(String message, {String? tag}) {
    _log(LogLevel.warning, message, tag: tag);
  }

  static void error(String message, {String? tag, Object? error, StackTrace? stackTrace}) {
    _log(LogLevel.error, message, tag: tag, error: error, stackTrace: stackTrace);
  }

  static void _log(
    LogLevel level,
    String message, {
    String? tag,
    Object? error,
    StackTrace? stackTrace,
  }) {
    if (!_enabled) return;

    final prefix = _getPrefix(level);
    final tagStr = tag != null ? '[$tag]' : '[$_tag]';
    final fullMessage = '$prefix $tagStr $message';

    if (kDebugMode) {
      developer.log(
        fullMessage,
        name: _tag,
        error: error,
        stackTrace: stackTrace,
        level: _getLevelInt(level),
      );
    }

    // Also print to console in debug mode
    if (kDebugMode) {
      final timestamp = DateTime.now().toIso8601String().substring(11, 23);
      print('$timestamp $fullMessage');
      if (error != null) {
        print('Error: $error');
      }
      if (stackTrace != null) {
        print('StackTrace: $stackTrace');
      }
    }
  }

  static String _getPrefix(LogLevel level) {
    switch (level) {
      case LogLevel.debug:
        return '[DEBUG]';
      case LogLevel.info:
        return '[INFO]';
      case LogLevel.warning:
        return '[WARN]';
      case LogLevel.error:
        return '[ERROR]';
    }
  }

  static int _getLevelInt(LogLevel level) {
    switch (level) {
      case LogLevel.debug:
        return 500;
      case LogLevel.info:
        return 800;
      case LogLevel.warning:
        return 900;
      case LogLevel.error:
        return 1000;
    }
  }

  // Specialized loggers for different modules
  static void sms(String message) => debug(message, tag: 'SMS');
  static void nlp(String message) => debug(message, tag: 'NLP');
  static void domain(String message) => debug(message, tag: 'Domain');
  static void rule(String message) => debug(message, tag: 'Rule');
  static void risk(String message) => debug(message, tag: 'Risk');
  static void db(String message) => debug(message, tag: 'Database');
  static void ui(String message) => debug(message, tag: 'UI');
}
