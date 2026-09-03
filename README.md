# Astrolok

Astrology, palm reading and astro talk. Flutter app on Riverpod + go_router, with a Supabase
Edge Functions backend, Fast2SMS OTP sign-in and Cashfree UPI Autopay billing.

**1-day trial, then ₹249/month.**

## Running it

```
flutter pub get
flutter run
```

With no `assets/env/app.env` the app boots on the **fake tier**: any 6-digit code signs you in
and the paywall charges nothing. That is deliberate — the whole flow stays walkable on a fresh
checkout. To talk to a real backend, copy the template and fill it in:

```
cp assets/env/app.env.example assets/env/app.env
```

There are three rungs, chosen in `lib/data/providers.dart` and picked automatically:

1. **Supabase** — OTP proxied through Edge Functions, users persisted, every credential
   off-device. The only path where the paywall actually charges.
2. **Fast2SMS direct** — real SMS, but nothing is stored and the API key ships in the app.
3. **Fake** — in-memory, any 6-digit code.

## Layout

```
lib/
  app/          env, router, entitlement gate, theme
  data/
    repositories/   interfaces only
    supabase/       the real implementations
    fast2sms/       direct-SMS fallback
    cashfree/       UPI checkout wrapper
    fake/           in-memory tier
    models/
  features/     <name>/{_view, _viewmodel, _state}.dart
  widgets/      shared design-system widgets
supabase/       migrations + Edge Functions (see supabase/README.md)
design/         Figma PNG exports, gitignored
```

Views never call repositories; ViewModels never call the router. A ViewModel that finishes a
step returns a `SplashDestination` and the view routes on it, so the splash and every
onboarding step agree about where a given user belongs.

## The onboarding gate

One function decides, in `lib/features/splash/splash_viewmodel.dart`:

```
!signedIn      -> onboarding
!hasName       -> onboarding (name step)
!hasBirthDate  -> birth
!entitled      -> subscribe
                  home
```

Everything past the paywall is wrapped in `EntitlementGate`, which re-checks on mount, on
resume, and on a timer armed for the entitlement expiry — a one-day trial will routinely run
out while the app is open in someone's pocket, and the cold-start check alone would miss it.

## Payments

The client sends no amount and no plan id, only its session token; the server resolves
everything billable from `app_config`. The Cashfree SDK callback is **never** treated as proof
of payment — it says the UPI app handed control back, not that money moved — so every outcome
ends by polling `subscription-status`, which reconciles against Cashfree.

Outcomes are three-valued, not two: `pending` exists so a real payment whose webhook is late is
never reported as a failure.

See [supabase/README.md](supabase/README.md) for the backend, the security model and setup.

## Tests

```
flutter analyze && flutter test      # 43 tests
cd supabase && deno test functions/tests/payments_test.ts   # 38 tests
```

## Status

Onboarding, birth date, paywall and payment flow are wired end to end against the backend. The
screens carry **placeholder styling** — structure and behaviour are final, visuals land once the
Figma exports are in `design/`. Palm reading and astro talk screens come after that.
