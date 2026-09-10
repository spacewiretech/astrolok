# lib/data/fake

## Purpose

The bottom rung of the backend ladder: in-memory implementations of every repository, so a
fresh checkout with no `assets/env/app.env` is walkable end to end. Any 6-digit code signs you
in and the paywall charges nothing.

## Files

- `fake_session.dart` — the in-memory stand-in for the Supabase tables, shared by every fake
  below so the screens stay consistent with one another for the length of a run. Declares:
  `FakeSession`.
- `fake_auth_repository.dart` — accepts any 6-digit code. Declares: `FakeAuthRepository`.
- `fake_palm_reading.dart` — a canned palm reading. Declares: `FakePalmRepository`.
- `fake_face_reading.dart` — a canned face reading. Declares: `FakeFaceRepository`.
- `fake_astro_chat.dart` — a scripted sage. Declares: `FakeChatRepository`.
- `fake_subscription_repository.dart` — a paywall that grants entitlement without charging.
  Declares: `FakeSubscriptionRepository`, `FakeCashfreeCheckout`.

## Notes

- Selected automatically in [../providers.dart](../providers.dart) when `Env.hasSupabase` is
  false. This is deliberate, not a test seam that leaked — see the root README's "three rungs".
- Every fake implements the interface in [../repositories/](../repositories/) and nothing more,
  which is what keeps the swap a one-line edit.
- Each fake has two jobs: keep the flow walkable, **and** be able to produce the failure states
  (rejection, limit reached) so those screens can be reached without a backend.
- `backendMode` stamps `fake` onto every analytics event fired on this tier, so it never
  pollutes production funnels.
