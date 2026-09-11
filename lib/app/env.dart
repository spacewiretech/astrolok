import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

/// Values read from `assets/env/app.env` at startup.
///
/// Every getter tolerates a missing file: [load] swallows the failure and the getters fall back
/// to empty strings, which flips [isConfigured] to false and puts onboarding on the fake
/// repository. A misconfigured checkout must never crash the app on launch.
///
/// The file carries two kinds of row. The four UPPERCASE names in [_reservedKeys] are this
/// class's own, read through the getters below. Everything else is a mirror of the `app_config`
/// table, surfaced as [appConfigFallback] and merged under the disk cache and the server — see
/// `shippedAppConfig` in `app_config_repository.dart`.
abstract final class Env {
  static bool _loaded = false;

  /// Real config, gitignored.
  static const _file = 'assets/env/app.env';

  /// Committed template. Loading it as a fallback means a checkout that never ran the copy
  /// step still boots — every value is blank, so the app lands on the fake repositories.
  static const _templateFile = 'assets/env/app.env.example';

  /// Keys this class owns. Everything else in the file is an `app_config` fallback row, which
  /// is what lets a row added to the table later need nothing here but a line in the file.
  static const _reservedKeys = {
    'SUPABASE_URL',
    'SUPABASE_ANON_KEY',
    'FAST2SMS_API_KEY',
    'FAST2SMS_OTP_ID',
  };

  /// Memoised because it is rebuilt on every config read, including the disk-cache path that
  /// runs on the splash.
  static Map<String, String>? _fallback;

  static Future<void> load() async {
    _fallback = null;
    for (final file in [_file, _templateFile]) {
      try {
        await dotenv.load(fileName: file);
        _loaded = true;
        if (file == _templateFile) {
          debugPrint(
            'Env: $_file is missing, fell back to the template. '
            'Copy $_templateFile to $_file and fill it in to send real OTPs.',
          );
        }
        return;
      } catch (_) {
        continue;
      }
    }

    _loaded = false;
    debugPrint('Env: no env file could be read. Falling back to the in-memory repositories.');
  }

  /// Loads from a literal file body rather than an asset.
  ///
  /// `dotenv.load` needs an asset bundle, which a plain unit test does not have, and [_loaded]
  /// has no other way in — so without this seam every test sees an unloaded [Env] and the
  /// fallback map can only ever be asserted empty.
  @visibleForTesting
  static void loadForTest(String contents) {
    dotenv.loadFromString(envString: contents, isOptional: true);
    _loaded = true;
    _fallback = null;
  }

  @visibleForTesting
  static void reset() {
    dotenv.clean();
    _loaded = false;
    _fallback = null;
  }

  static String _get(String key) => _loaded ? (dotenv.env[key] ?? '') : '';

  /// The `app_config` rows shipped with this build.
  ///
  /// Sits above `defaultAppConfig` and below the disk cache: the cache holds the last known
  /// *server* state, which is fresher truth than a snapshot taken when the build was cut. This
  /// is a better set of defaults, not a better cache.
  ///
  /// Blank values are dropped. A bare `key=` in the file means "not set here, use the compiled
  /// default", never "force this key empty" — nothing in the table needs env to force a blank,
  /// and a line someone half-filled must not shadow a good default.
  static Map<String, String> get appConfigFallback => _fallback ??= _loaded
      ? {
          for (final entry in dotenv.env.entries)
            if (!_reservedKeys.contains(entry.key) && entry.value.trim().isNotEmpty)
              entry.key: entry.value,
        }
      : const {};

  /// Falls through to the `app_config` spelling, so the table mirror can be pasted in whole and
  /// the legacy direct-to-Fast2SMS tier still finds its credentials under the other name.
  static String get fast2smsApiKey => _firstNonEmpty('FAST2SMS_API_KEY', 'fast2sms_api_key');

  /// The OTP Template ID from the Fast2SMS dashboard, required by `/dev/otp/send`.
  static String get fast2smsOtpId => _firstNonEmpty('FAST2SMS_OTP_ID', 'fast2sms_otp_id');

  static String _firstNonEmpty(String first, String second) {
    final value = _get(first);
    return value.isNotEmpty ? value : _get(second);
  }

  static String get supabaseUrl => _get('SUPABASE_URL');

  /// Public by design — it ships in every client. Row-level security, not secrecy, is what
  /// protects the data behind it.
  static String get supabaseAnonKey => _get('SUPABASE_ANON_KEY');

  /// When true the app talks to Supabase, which proxies OTP through Edge Functions and keeps
  /// the Fast2SMS and Cashfree credentials off the device entirely.
  static bool get hasSupabase => supabaseUrl.isNotEmpty && supabaseAnonKey.isNotEmpty;

  /// Both halves are needed: a key with no template ID cannot send.
  static bool get isConfigured => fast2smsApiKey.isNotEmpty && fast2smsOtpId.isNotEmpty;

  /// Explains, for the debug log, which half is missing.
  static String get configurationSummary {
    if (isConfigured) return 'Fast2SMS configured.';
    if (fast2smsApiKey.isEmpty && fast2smsOtpId.isEmpty) {
      return 'FAST2SMS_API_KEY and FAST2SMS_OTP_ID are both unset.';
    }
    if (fast2smsApiKey.isEmpty) return 'FAST2SMS_API_KEY is unset.';
    return 'FAST2SMS_OTP_ID is unset — create an OTP Template in the Fast2SMS dashboard.';
  }
}
