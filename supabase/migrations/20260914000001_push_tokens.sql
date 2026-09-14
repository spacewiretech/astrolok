-- Push notification tokens.
--
-- One row per device that can receive a push, bound to the account *and the session* that
-- registered it. Registration only: nothing in this project sends a push yet. A sender — FCM HTTP
-- v1, with a service-account credential held as a function secret — is the next step, and should
-- target only rows whose session is still live (see the note on the window below).
--
-- ## Why the session, and not just the user
--
-- `session_token_hash` references `user_sessions` with `on delete cascade`, and that one foreign
-- key is the whole of the cleanup story:
--
--  * **Sign-out.** `me` DELETE removes the session row and the token goes with it. A phone that
--    has signed out stops receiving that account's notifications without the app having to make a
--    second call on the way out — a call it frequently cannot make, offline or killed mid-sign-out.
--  * **Expiry.** `purge_expired` already deletes expired sessions daily, so tokens age out on the
--    same 90-day schedule with no sweep of their own. `purge_expired` is deliberately not touched.
--
-- Between a session expiring and the next sweep, its token row survives. A sender should join
-- `user_sessions` on `expires_at > now()` rather than trusting the row alone.
--
-- ## Why the token is the primary key
--
-- An FCM token identifies an app install, not a person. When a second account signs in on the
-- same phone, registration upserts on `token` and the row *moves* to the new account and session,
-- so the previous account can never be notified on a device it no longer holds.
--
-- ## RLS posture
--
-- Enabled with zero policies, exactly like `users`: only the Edge Functions, on service_role, can
-- read or write it. A readable table would map devices to accounts.

create table public.push_tokens (
  -- Opaque, and around 160 characters today. The bound is generous so an upstream format change
  -- is not an outage, and finite so the column cannot be used as storage.
  token              text primary key
                     check (length(token) between 1 and 4096),

  user_id            uuid not null references public.users(user_id) on delete cascade,

  session_token_hash text not null
                     references public.user_sessions(token_hash) on delete cascade,

  platform           text not null
                     check (platform in ('android', 'ios')),

  created_at         timestamptz not null default now(),
  updated_at         timestamptz not null default now()
);

create index push_tokens_user_id_idx on public.push_tokens (user_id);

-- The cascade from `user_sessions` finds its rows through this rather than a sequential scan,
-- which matters on the daily sweep that deletes every expired session at once.
create index push_tokens_session_token_hash_idx on public.push_tokens (session_token_hash);

create trigger push_tokens_touch_updated_at
  before update on public.push_tokens
  for each row execute function public.touch_updated_at();

alter table public.push_tokens enable row level security;

comment on table public.push_tokens is
  'FCM registration tokens, one per device, bound to the session that registered them so sign-out '
  'and session expiry remove them by cascade. RLS on, zero policies: Edge Functions only.';
