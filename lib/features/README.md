# lib/features

## Purpose

One folder per screen or flow. Container only — every file lives in a subfolder.

## Subfolders

- `splash/` — resolves the stored session and decides where the user belongs. **The onboarding
  gate.**
- `onboarding/` — phone, OTP and name, as one screen with a swapping bottom sheet.
- `birth/` — date of birth, between onboarding and the paywall.
- `subscription/` — the paywall, the Cashfree UPI mandate, and the entitlement polling.
- `payment_status/` — where checkout lands; three-valued, `pending` included.
- `home/` — the signed-in home screen. View only.
- `palm/` — palm reading: capture → scan → reading → line detail.
- `face/` — face reading, a file-for-file mirror of `palm/`.
- `chat/` — the Astro conversation: one route, many threads.
- `profile/` — account menu, saved readings, Astro's memory.

## Notes

- **The convention is `<name>_view.dart` / `_viewmodel.dart` / `_state.dart` / `_copy.dart`,
  but only `palm` and `face` use all four.** The deviations are real and intentional; each
  folder's README records its own. In short: `home` is view-only; `profile` and
  `payment_status` have views without a matching viewmodel; `birth` and `subscription` keep
  their state class inside the viewmodel file; `splash_viewmodel.dart` contains no ViewModel
  class at all; `chat` adds three widget files and a second viewmodel. Copy files exist for
  exactly three features — `chat`, `face`, `palm`.
- **Views never call repositories; ViewModels never call the router.** A ViewModel that finishes
  a step returns a destination and the view routes on it.
- Everything reaches the data layer through
  [../data/providers.dart](../data/providers.dart) — no view or viewmodel imports a concrete
  repository.
- **Gating is per-route, not global.** There is no redirect in `appRouter`; paid screens are
  individually wrapped in `EntitlementGate`. `/birth`, `/subscribe` and
  `/payment-status/:outcome` are deliberately left ungated.
- A few providers are declared outside `providers.dart` and outside the viewmodels — notably
  `palmRejectionProvider`/`palmLimitProvider` and the face pair, which live in the *capture view*
  files, and `selectedThreadProvider` in `chat_viewmodel.dart`.
