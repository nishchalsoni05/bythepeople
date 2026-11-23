import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

import 'package:by_the_people/core/logging/app_logger.dart';

/// Runtime configuration.
///
/// Precedence (highest first): `--dart-define` → bundled `.env` → built-in default.
/// Anything shipped inside the app, `.env` included, can be read from the build,
/// so only put non-secret settings here. Secrets belong on the server.
abstract final class Env {
  static const _defineApiUrl = String.fromEnvironment('API_URL');
  static const _defaultApiUrl = 'http://localhost:3000';

  /// Reads a `.env` value. Returns null before [load] has run (or when the file is absent) instead of throwing.
  static String? _fromDotenv(String key) {
    try {
      return dotenv.maybeGet(key);
    } on Object {
      return null;
    }
  }

  /// Loads `.env` from the bundled assets. A missing file is fine; defaults apply.
  static Future<void> load() async {
    try {
      await dotenv.load(fileName: '.env', isOptional: true);
    } catch (e, s) {
      appLogger.w('Could not read .env, falling back to defaults', error: e, stackTrace: s);
    }
  }

  /// Backend base URL without a trailing slash. Throws if it is not a valid http(s) URL.
  static String get apiBaseUrl {
    final raw = (_defineApiUrl.isNotEmpty ? _defineApiUrl : (_fromDotenv('API_URL') ?? _defaultApiUrl)).trim();
    final uri = Uri.tryParse(raw);
    final valid = uri != null && (uri.scheme == 'http' || uri.scheme == 'https') && uri.host.isNotEmpty;
    if (!valid) throw StateError('API_URL must be an absolute http or https URL, got "$raw"');
    return raw.endsWith('/') ? raw.substring(0, raw.length - 1) : raw;
  }

  /// Request/response logging. Never on in release builds.
  static bool get httpLogging => !kReleaseMode && (_fromDotenv('HTTP_LOG') ?? 'true') == 'true';
}
