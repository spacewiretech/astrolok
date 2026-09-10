/// Which language Astro writes in, for this user, right now.
///
/// The choice lives on `users.language` and the list of possibilities in `app_config`, so the
/// answer is a function of both — and resolving it has to agree exactly with `resolveLanguage`
/// in `_shared/chat_language.ts`, or the app labels a reading with a language the server did not
/// write it in.
///
/// The `chat_` prefix on the config keys is historical: the setting arrived with the chat and now
/// governs palm and face readings too. Renaming the rows would break a live dashboard for nothing.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'entitlement.dart';
import 'providers.dart';
import 'repositories/app_config_repository.dart';

/// The user's language, or the configured default when they have never chosen.
///
/// [stored] is `AppUser.chatLanguage`, which is null for anyone who has not picked. A value that
/// has since been removed from `chat_languages` falls back to the default rather than being
/// honoured — the same rule the Edge Functions apply, so a retired language cannot leave the app
/// and the server disagreeing about what a reading is written in.
///
/// Returns an empty string only when config offers no languages at all, which is the documented
/// off switch for the whole feature.
String resolveLanguage(String? stored, Map<String, String> config) {
  final languages = config.configList(chatLanguagesKey);
  if (languages.isEmpty) return '';

  String? match(String? name) {
    final wanted = name?.trim().toLowerCase();
    if (wanted == null || wanted.isEmpty) return null;
    for (final entry in languages) {
      if (entry.toLowerCase() == wanted) return entry;
    }
    return null;
  }

  return match(stored) ??
      match(config.configString(chatLanguageDefaultKey)) ??
      languages.first;
}

/// [resolveLanguage] over the live user and config.
///
/// Watched rather than read wherever it is used, so picking a new language in Profile updates
/// the speech control on every screen without any of them knowing where the value came from.
final languageProvider = Provider<String>((ref) {
  final user = ref.watch(entitlementProvider);
  final config = ref.watch(appConfigProvider).valueOrNull ?? shippedAppConfig;
  return resolveLanguage(user?.chatLanguage, config);
});
