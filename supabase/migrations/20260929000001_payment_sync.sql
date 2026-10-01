-- Cashfree webhooks, processed every minute instead of on arrival.
--
-- Until now every verified delivery ran the whole money path inline: read the subscription, record
-- the payment (about seven requests), then ask Cashfree for the mandate and write it back to
-- `subscriptions` and `users` (about five more). A checkout sends three or four of these within
-- seconds, each re-syncing the same mandate. On 2026-09-29 the path was 37% of the project's
-- PostgREST requests (about 15 a second) behind its high-CPU warning, with ~220 verified deliveries
-- per five minutes naming only ~115 subscriptions.
--
-- Every minute rather than every five: the duplicates arrive seconds apart, so a minute collapses
-- nearly as many (5,590 deliveries in two hours needed 3,001 syncs, against 2,828 in five-minute
-- batches) and caps the extra wait at a minute. That wait matters only when a bank confirms after
-- the app has stopped polling (about 15% of paid checkouts took over two minutes, 2026-09-28) and
-- the user reopens the app before the webhook is processed.
--
-- With `cashfree_webhook_batch` on, the webhook verifies and records the delivery and returns, and
-- `payment-sync` (scheduled below) claims what is queued, records each charge the ledger does not
-- already hold at that status, and syncs each subscription once. Nothing waits on it: the app's own
-- `subscription-status` poll still syncs a checkout the moment the UPI sheet closes, and on every
-- resume.
--
-- Ships with the switch OFF. Until it is flipped the webhook behaves as before and `payment-sync`
-- only picks up a verified delivery that has sat unprocessed for five minutes, which today is none.
-- Flipping it back off is the rollback: the webhook resumes inline processing, and the worker still
-- drains anything left queued.

alter table public.payment_events
  add column if not exists attempts integer not null default 0,
  add column if not exists locked_at timestamptz;

comment on column public.payment_events.attempts is
  'How many times payment-sync has claimed this delivery. It stops claiming at the worker''s limit.';
comment on column public.payment_events.locked_at is
  'When payment-sync last claimed this delivery. A claim older than the stale window is taken again.';

-- The queue. `payment_events_unprocessed_idx` also holds every delivery that failed its signature
-- check, and those are never processed, so that index grows by thousands a day. This one holds
-- only what the worker can act on.
create index if not exists payment_events_pending_idx
  on public.payment_events (received_at)
  where processed_at is null and signature_ok;

-- Claims up to [p_limit] verified, unprocessed deliveries, oldest first. The claim stamps
-- `locked_at` and counts an attempt. `skip locked` lets two overlapping runs never take the same
-- row, and a claim older than [p_stale_minutes] (a run that died) is taken again.
-- [p_min_age_seconds] keeps the worker off deliveries the webhook may still be processing inline
-- while the switch is off.
create or replace function public.claim_payment_events(
  p_limit integer,
  p_stale_minutes integer,
  p_max_attempts integer,
  p_min_age_seconds integer
)
returns table (
  id bigint,
  event_type text,
  subscription_id text,
  cf_subscription_id text,
  payload jsonb,
  received_at timestamptz,
  attempts integer
)
language sql
volatile
set search_path = public
as $$
  with picked as (
    select e.id
      from public.payment_events e
     where e.processed_at is null
       and e.signature_ok
       and e.attempts < p_max_attempts
       and e.received_at <= now() - make_interval(secs => greatest(p_min_age_seconds, 0))
       and (e.locked_at is null or e.locked_at < now() - make_interval(mins => p_stale_minutes))
     order by e.received_at
     limit p_limit
       for update skip locked
  )
  update public.payment_events e
     set locked_at = now(),
         attempts = e.attempts + 1
    from picked
   where e.id = picked.id
  returning e.id, e.event_type, e.subscription_id, e.cf_subscription_id, e.payload, e.received_at,
            e.attempts;
$$;

revoke all on function public.claim_payment_events(integer, integer, integer, integer)
  from public, anon, authenticated;
grant execute on function public.claim_payment_events(integer, integer, integer, integer)
  to service_role;

insert into public.app_config (key, value, is_public, description) values
  ('cashfree_webhook_batch', 'false', false,
   'When true, cashfree-webhook only verifies and records each delivery, and payment-sync processes '
   'the queue every minute: one Cashfree sync per subscription and no rewrite of a charge '
   'already recorded. False processes every delivery inline, as before. Takes effect within the 60s '
   'config TTL.')
on conflict (key) do nothing;

select cron.schedule(
  'payment-sync-1min',
  '* * * * *',
  $job$
  select net.http_post(
    url := 'https://qktgingrvecpetrofimy.supabase.co/functions/v1/payment-sync',
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'x-cron-secret', (select value from public.app_config where key = 'reconcile_secret')
    ),
    body := '{}'::jsonb,
    timeout_milliseconds := 10000
  );
  $job$
);
