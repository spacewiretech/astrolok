# `lib/data/attribution/`

Where an install came from — a referral, a Meta or Google ad, or nothing at all — and the
plumbing that gets that answer from the Play Store into Supabase and Mixpanel.

## Files

| File | What it is |
|---|---|
| `referral_links.dart` | The code alphabet, normalising a typed code, reading one out of a URI |
| `attribution.dart` | The `Attribution` value type and `resolveAttribution`, the precedence rules |
| `attribution_store.dart` | `shared_preferences` persistence, under `astrolok.attribution_*` |
| `attribution_service.dart` | The state machine, and the global `attributionService` |

## Android, through the Play Store

An invite is a **Play Store link** carrying `referrer=utm_source=referral&utm_medium=invite&ref_code=<CODE>`.
Google hands that string back verbatim through the Install Referrer API on the first launch after
install, so a referral survives an install that had no app to open.

There is deliberately **no web landing page, no App Link and no `assetlinks.json`.** An earlier
version had all three, plus a click-recording endpoint and a salted IP-match window, because those
are what it takes to recover a referral on iOS where nothing survives the App Store. When the
launch scope became Android-only every one of them became a liability with no user: domain
verification that can fail silently, a hosting rule that must not swallow `/.well-known`, an
anonymous write endpoint, and a probabilistic guess standing next to a deterministic answer. They
were removed rather than left switched off.

The same applies to ads: put the campaign's UTMs straight in the store link's `referrer`.

```
https://play.google.com/store/apps/details?id=com.spacewire.astrolok
  &referrer=utm_source%3Dmeta%26utm_campaign%3Ddiwali%26utm_content%3Dad_a
```

⚠️ On Meta and Google **App Install** campaigns the network controls the store hand-off and sets
its own referrer, so custom UTMs do not survive. Source still resolves (`gclid` → `google_ads`,
Meta's own stamp → `meta`), but campaign-level breakdown comes from Ads Manager, not Mixpanel.

## The shape of the problem

Attribution arrives **early** — in the first milliseconds of a cold launch, from the Play Store —
and can only be *recorded* **late**, after the user has an account. Those two moments are minutes
apart, with an OTP and a paywall in between, and the app is routinely killed somewhere in the
middle by the UPI hand-off.

So this is two-phase, built the same way `MixpanelAnalytics` is:

1. **`start()`**, from `bootMobileApp` before `runApp`. Restores what an earlier launch resolved,
   reads the install referrer, resolves a source, registers super properties, and **writes what it
   found to disk before sending anything anywhere.**
2. **`attachBackend()`**, from `attributionBootstrapProvider` once the repositories exist. Drains
   whatever is pending. `onUserResolved()` drains again from the identity hook in
   `entitlement.dart`, which is the moment a session first exists.

Writing before sending is the whole reliability story. The worst case is a claim that gets
retried, and `referral-claim` is idempotent precisely so that retrying costs nothing.

The install referrer read is **not awaited** — it binds a Play Store service, and no part of
attribution justifies holding the first frame.

## Deep links are data, not destinations

`flutter_deeplinking_enabled` (Android) and `FlutterDeepLinkingEnabled` (iOS) are both `false` and
stay that way. Those flags let the engine route an incoming link straight to a screen, which would
walk a user past the splash — the one place that resolves the session and decides where they
belong.

`app_links` is still listened to by hand, because the `astrolok://` scheme exists. Note that
`_onLink` tests for *campaign* parameters rather than for any query at all: the Cashfree return is
`astrolok://payment?sub=...`, and an earlier `params.isEmpty` check let it through — attributing
every web-fallback payment to an organic deep link and firing a referral event for it.

## First touch vs last touch

Last touch lives in super properties and moves freely. **First touch is written once and never
again**, guarded in three independent places:

1. `recordFirstTouchIfAbsent` here, locally;
2. an insert that does nothing on conflict in `attribution-report`;
3. `setOnce` on the `initial_*` People properties.

A first touch silently overwritten by a later click re-attributes the acquisition to the campaign
that had the least to do with it, and it is invisible once it has happened — there is no record of
what the value used to be.

**The backend is the authority.** The client resolves a source locally so that events fired before
there is a session still carry one, but `attribution-report` re-resolves from the raw parameters
and its answer overwrites the local guess. That matters because the app has no `alias` call
anywhere: pre-signup events sit on an anonymous distinct id and only stitch to the account if the
Mixpanel project is on Simplified ID Merge. Keeping the durable record server-side, keyed on
`users.user_id`, makes it correct either way.

## One event name, one source

`Referral Attributed` is raised **only** by the server; `Attribution Resolved` **only** by the app.
Client SDK events carry no `$insert_id`, so Mixpanel cannot collapse a client event against a
server one however carefully the server keys its own — emitting both names from both sides would
have counted every referral twice.

## Related

- `supabase/functions/_shared/referral.ts` — the same precedence rules, server-side and
  authoritative, plus `shareLinkFor` and its two encoding traps. The two must agree.
- `supabase/migrations/20260911000001_referrals.sql` — the schema, and why
  `referrals.referred_user_id` is the primary key.
