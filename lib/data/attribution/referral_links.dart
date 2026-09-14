/// Referral codes, and reading one back out of what the Play Store hands over.
///
/// The rules here are duplicated, on purpose, in three places: this file, the CHECK constraint on
/// `referral_codes.code`, and `normaliseReferralCode` in `supabase/functions/_shared/referral.ts`.
/// Each of the three is the only one available where it runs — the database cannot validate a code
/// the app never sends, and the app cannot enforce a constraint on a table it cannot reach. They
/// must agree, and a disagreement shows up as a code the backend issues and the app refuses to
/// accept, so any change to the alphabet is a change to all three.
library;

/// Crockford base32: the digits and A–Z without I, L, O and U.
///
/// Those four are dropped because a code is read down a phone line and typed off a screenshot.
/// I/1, O/0 and L/1 are the classic misreads, and dropping U means eight random characters can
/// never spell something unfortunate.
const referralCodeAlphabet = '0123456789ABCDEFGHJKMNPQRSTVWXYZ';

final _codePattern = RegExp(r'^[0-9ABCDEFGHJKMNPQRSTVWXYZ]{8}$');
final _notCodeCharacter = RegExp('[^0-9A-Z]');

/// Cleans up a code the way whoever typed it meant it.
///
/// Case and punctuation carry no meaning, so they are stripped. The four ambiguous letters are
/// folded onto the characters they are almost certainly a misreading of rather than rejected:
/// someone who types `ILOU` off a screenshot meant `110V`, and refusing them would be technically
/// correct and useless to the person holding the phone.
///
/// Returns null for anything that is not a code after that, so a caller can treat "no code" and
/// "bad code" identically — which every caller here does.
String? normaliseReferralCode(String? raw) {
  if (raw == null) return null;

  final cleaned = raw
      .trim()
      .toUpperCase()
      .replaceAll(_notCodeCharacter, '')
      .replaceAll(RegExp('[IL]'), '1')
      .replaceAll('O', '0')
      .replaceAll('U', 'V');

  return _codePattern.hasMatch(cleaned) ? cleaned : null;
}

/// Pulls a code out of an incoming URI, if it carries one.
///
/// The shape that actually matters is the **query** form — `?ref_code=ABCD2345` — because that is
/// how a code survives the Play Store: an invite links to the store listing with
/// `referrer=ref_code=<CODE>`, and Google hands that string back through the Install Referrer API
/// on first launch. There is no `/r/<CODE>` path form and no App Link: claiming an https path
/// would mean domain verification, an `assetlinks.json` listing the Play App Signing certificate,
/// and a hosting rule that must not swallow `/.well-known` — all so the app could open for a user
/// who by definition does not have it installed yet.
///
/// Still accepts a URI rather than a bare query string because the `astrolok://` scheme exists and
/// could carry one, and because the install referrer is parsed as a query elsewhere
/// ([paramsFromReferrerString]) and both end up here.
String? referralCodeFromUri(Uri uri) => normaliseReferralCode(
      uri.queryParameters['ref_code'] ?? uri.queryParameters['ref'],
    );
