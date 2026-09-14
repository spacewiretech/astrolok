-- Referral invites and acquisition attribution.
--
-- Two related things land together because they share a claim path and a conversion hook:
--
--  1. **Referrals** — one user invites another with an opaque code. The relationship is stored
--     here, and it only becomes *qualified* when the invitee authorises the ₹3 mandate. Credit
--     that requires a real bank mandate is the cheapest anti-abuse measure available: a fake
--     referral costs the attacker money and a real UPI authorisation.
--  2. **Attribution** — where a user actually came from, referral or Meta or Google Ads or
--     organic, split into a first touch that can never be overwritten and a last touch that is
--     freely updated.
--
-- ## Android, through the Play Store, and nothing else
--
-- An invite is a **Play Store link** carrying `referrer=ref_code=<CODE>`. Google hands that string
-- back verbatim through the Install Referrer API on first launch, so the code survives an install
-- with no app to open and no web page in the middle. That is deterministic, needs no domain
-- verification and no association files, and is the whole mechanism.
--
-- Deliberately *not* here, because iOS is not in this release: a `referral_clicks` table and an
-- IP-match window. Those exist only to recover a referral on iOS, where nothing survives the App
-- Store — and an earlier draft of this migration carried them along with a salted-hash scheme and
-- a click endpoint open to the internet. All of it was dead weight for an Android-only launch, so
-- it is gone rather than left switched off. The manual code field in onboarding is the fallback.
--
-- ## The one constraint this whole feature rests on
--
-- `referrals.referred_user_id` is the **primary key**, not merely a column. Every duplicate-claim
-- scenario in the spec — a retried network call, an app killed mid-attribution, two links clicked,
-- a reinstall, two concurrent requests racing — collapses into "the second insert conflicts".
-- Application code can then be written to be idempotent by *reading the winner back* rather than
-- by trying to guard the race itself, which is the only version of this that is actually safe.
--
-- ## RLS posture
--
-- Every table below is `enable row level security` with **zero policies**, exactly like `users`.
-- That denies anon and authenticated outright while service_role bypasses RLS, so only the Edge
-- Functions can read or write any of it. This matters more here than elsewhere: `referral_codes`
-- maps a code to a user, and a readable table would expose who invited whom.

-- ---------------------------------------------------------------- referral codes

-- The invite code, one per user.
--
-- Deliberately **not** derived from `user_id`. A code that encodes the account is an account
-- identifier printed on a shareable link — it leaks who invited you to anyone holding the link,
-- and it lets someone walk the user table by guessing. This is 40 bits of CSPRNG instead, which
-- is unguessable at any rate a rate-limited API will serve and says nothing about the owner.
create table public.referral_codes (
  -- Crockford base32: the digits plus A-Z without I, L, O and U. Those four are dropped because
  -- a code gets read down a phone line and typed off a screenshot — I/1, O/0 and L/1 are the
  -- classic misreads, and dropping U means the alphabet cannot spell an unfortunate word.
  code       text primary key
             check (code ~ '^[0-9ABCDEFGHJKMNPQRSTVWXYZ]{8}$'),

  -- One code per user, forever. The unique constraint is what makes issuing idempotent: the
  -- Edge Function inserts, and on conflict selects the row that already exists rather than
  -- minting a second code for someone who tapped Invite twice.
  user_id    uuid not null unique references public.users(user_id) on delete cascade,

  created_at timestamptz not null default now()
);

alter table public.referral_codes enable row level security;

comment on table public.referral_codes is
  'One opaque invite code per user. Never derived from user_id — the code ships inside a public '
  'link, so it must not identify the account.';

-- Mints a code, retrying on the astronomically unlikely collision.
--
-- Schema-qualified `extensions.gen_random_bytes`: pgcrypto lives in `extensions` on Supabase and
-- is not on the search_path a `security definer` function runs with. The same note is on the
-- token generator in 20260903000003.
--
-- The loop is not superstition — it is what makes the birthday collision a retry instead of a
-- failed signup. At 40 bits, a collision is not worth designing around but is worth surviving.
create or replace function public.issue_referral_code(p_user_id uuid)
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  v_alphabet constant text := '0123456789ABCDEFGHJKMNPQRSTVWXYZ';
  v_existing text;
  v_code     text;
  v_bytes    bytea;
  i          integer;
begin
  -- Idempotent by design: a user who already has a code always gets the same one back, so this
  -- is safe to call on every open of the invite screen.
  select code into v_existing from public.referral_codes where user_id = p_user_id;
  if v_existing is not null then
    return v_existing;
  end if;

  for _attempt in 1..8 loop
    v_code := '';
    v_bytes := extensions.gen_random_bytes(8);
    for i in 0..7 loop
      -- `& 31` maps a byte onto the 32-character alphabet without modulo bias, since 32 divides
      -- 256 exactly. A naive `% 32` would be fine here for the same reason, but the mask says so.
      v_code := v_code || substr(v_alphabet, (get_byte(v_bytes, i) & 31) + 1, 1);
    end loop;

    begin
      insert into public.referral_codes (code, user_id) values (v_code, p_user_id);
      return v_code;
    exception
      when unique_violation then
        -- Either the code collided, or this user acquired one concurrently. Re-read: if the
        -- second, we are done and must return *their* code rather than looping to mint another.
        select code into v_existing from public.referral_codes where user_id = p_user_id;
        if v_existing is not null then
          return v_existing;
        end if;
        -- Otherwise it was a genuine code collision. Go round again.
    end;
  end loop;

  raise exception 'could not issue a referral code after 8 attempts';
end;
$$;

revoke all on function public.issue_referral_code(uuid) from public, anon, authenticated;

-- ---------------------------------------------------------------- the relationship

create table public.referrals (
  -- THE constraint. One referral per referred user, for the lifetime of the account. See the
  -- header — every duplicate and race case in this feature is handled by this line.
  referred_user_id uuid primary key references public.users(user_id) on delete cascade,

  referrer_user_id uuid not null references public.users(user_id) on delete cascade,

  code             text not null,

  -- How the attribution was resolved, which is the honesty column. `install_referrer` is
  -- deterministic — Google handed us the code — and `manual_code` is the user typing it, which is
  -- the fallback for a link opened on a device that never completed the store round trip.
  -- `deep_link` is reserved: the `astrolok://` scheme exists, and leaving room here costs nothing
  -- while narrowing the constraint later would cost a migration.
  attribution_type text not null
                   check (attribution_type in
                          ('install_referrer', 'manual_code', 'deep_link')),

  attributed_at    timestamptz not null default now(),

  -- Set when the invitee authorises the ₹3 mandate. Null means attributed but not yet paid.
  --
  -- The reward question is deliberately left open — nothing grants anything yet — but a reward
  -- added later reads exactly this column, so it needs no migration and no backfill.
  qualified_at     timestamptz,

  -- Self-referral refused by the database rather than only by the function that writes here.
  -- The function checks it too and returns a proper error; this is what makes the guarantee hold
  -- even if some future code path forgets.
  constraint referrals_no_self_referral check (referrer_user_id <> referred_user_id)
);

-- "How many people did I invite, and how many of them paid" — the only question asked of this
-- table from the referrer's side.
create index referrals_referrer_idx on public.referrals (referrer_user_id, qualified_at);

alter table public.referrals enable row level security;

comment on table public.referrals is
  'Who invited whom. Primary key on referred_user_id, which is what makes a duplicate claim '
  'impossible under any race. qualified_at is set by the payment webhook, not by the client.';

-- ---------------------------------------------------------------- attribution

-- Where each user came from, first touch and last touch side by side.
--
-- Separate from `referrals` because most users have attribution and no referral: an install from
-- a Meta ad has a campaign and no referrer, and folding the two together would mean a nullable
-- referrer column on every row plus a join to answer either question.
create table public.user_attribution (
  user_id                uuid primary key references public.users(user_id) on delete cascade,

  -- **First touch. Written once, never updated.**
  --
  -- The Edge Function writes these with `on conflict do nothing`, so the first write wins at the
  -- database rather than by the application remembering to check. This is the single most
  -- damaging thing to get wrong in an attribution system — a first touch silently overwritten by
  -- a later retargeting click is invisible once it happens, and it re-attributes the acquisition
  -- to the campaign that had the least to do with it.
  first_source           text,
  first_channel          text,
  first_campaign         text,
  first_campaign_id      text,
  first_adset            text,
  first_ad               text,
  first_attribution_type text,
  first_referral_code    text,
  first_touch_at         timestamptz,

  -- Last touch. Freely overwritten; this is the half that is *supposed* to move.
  last_source            text,
  last_channel           text,
  last_campaign          text,
  last_campaign_id       text,
  last_adset             text,
  last_ad                text,
  last_attribution_type  text,
  last_referral_code     text,
  last_touch_at          timestamptz,

  updated_at             timestamptz not null default now()
);

create index user_attribution_first_source_idx on public.user_attribution (first_source);

alter table public.user_attribution enable row level security;

comment on table public.user_attribution is
  'First-touch and last-touch acquisition per user. The first_* columns are write-once by '
  'construction — the writer uses on-conflict-do-nothing, so they cannot be overwritten.';

comment on column public.user_attribution.first_source is
  'referral | meta | google_ads | paid_other | organic. Never overwritten once set.';

-- ---------------------------------------------------------------- config

insert into public.app_config (key, value, is_public, description) values
  ('referral_enabled', 'true', true,
   'Master switch for referral capture and the invite UI. False hides the invite screen and '
   'makes every claim a no-op, without requiring a release.'),

  -- The Play Store listing, which is what an invite actually links to.
  --
  -- Seeded blank because the app is not on the store yet, and a blank row is the honest state:
  -- `referral-code` refuses to hand out a share link it cannot build, so the invite screen says
  -- it is unavailable rather than sharing a URL that 404s. Paste the listing URL in to switch it
  -- on — no release needed.
  --
  -- The `?referrer=` parameter is appended by `shareLinkFor`; do not put one here.
  ('referral_store_url', '', true,
   'Play Store listing URL an invite links to, e.g. '
   'https://play.google.com/store/apps/details?id=com.spacewire.astrolok. Blank disables the '
   'invite screen. The referrer parameter is appended by the server — do not include one.'),

  ('referral_claim_window_days', '7', true,
   'How long after signing up an account can still be attributed to a referrer. Together with '
   '"has never had entitlement" this is what stops a months-old account that simply never paid '
   'being retro-attributed, which is indistinguishable from farming.')
on conflict (key) do nothing;
