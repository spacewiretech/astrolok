-- The reconciliation safety net.
--
-- Without this the only path from "Cashfree charged ₹249" to "this user is still entitled" is
-- the webhook, with nothing behind it. A single dropped delivery would then lock out a paying
-- customer until they contacted support.
--
-- BEFORE APPLYING: replace <PROJECT_REF> below with the new project's ref (the subdomain of
-- its Supabase URL). The cron job posts to an absolute URL and there is no variable to read it
-- from inside a migration.

create extension if not exists pg_cron;
create extension if not exists pg_net;

-- ---------------------------------------------------------------- secret

-- Generated in the database so the value never passes through a migration file, a shell history
-- or a code review. Only filled when still empty, so re-running this cannot rotate a secret out
-- from under a scheduled job that is already using it.
--
-- Schema-qualified: pgcrypto lives in `extensions` on Supabase and is not on the search_path a
-- migration runs with, so the bare name resolves to nothing.
update public.app_config
   set value = encode(extensions.gen_random_bytes(32), 'hex')
 where key = 'reconcile_secret'
   and (value is null or value = '');

-- ---------------------------------------------------------------- schedule

-- Unscheduled first so re-running the migration replaces the job rather than erroring on the
-- duplicate name.
do $$
begin
  if exists (select 1 from cron.job where jobname = 'subscription-reconcile-hourly') then
    perform cron.unschedule('subscription-reconcile-hourly');
  end if;
  if exists (select 1 from cron.job where jobname = 'purge-expired-daily') then
    perform cron.unschedule('purge-expired-daily');
  end if;
end
$$;

-- Hourly, at seven minutes past. Off the hour on purpose: Cashfree's own batches fire on it,
-- and a sweep that runs in the same minute as the debit finds nothing and then waits an hour.
--
-- The secret is read from app_config at run time rather than baked in, so rotating the row is
-- enough and the job never has to be rewritten.
select cron.schedule(
  'subscription-reconcile-hourly',
  '7 * * * *',
  $job$
  select net.http_post(
    url := 'https://<PROJECT_REF>.supabase.co/functions/v1/subscription-reconcile',
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'x-reconcile-secret', (select value from public.app_config where key = 'reconcile_secret')
    ),
    body := '{}'::jsonb,
    timeout_milliseconds := 55000
  );
  $job$
);

select cron.schedule('purge-expired-daily', '20 3 * * *', $job$select public.purge_expired();$job$);

-- ---------------------------------------------------------------- retention

-- `payment_events` is written before the signature is checked, which is deliberate — a forged
-- call is worth being able to see — but it means anyone who can reach the endpoint can grow the
-- table. Unverified deliveries are noise after a month; verified ones are the audit trail for a
-- disputed charge and are kept far longer.
create or replace function public.purge_expired()
returns void
language sql
security definer
set search_path = public
as $$
  delete from public.user_sessions where expires_at < now();
  delete from public.otp_throttle  where last_send_at < now() - interval '7 days';
  delete from public.payment_events
   where signature_ok = false and received_at < now() - interval '30 days';
  delete from public.payment_events
   where signature_ok and received_at < now() - interval '180 days';
$$;

revoke all on function public.purge_expired() from public, anon, authenticated;

comment on function public.purge_expired is
  'Daily sweep: expired sessions, stale OTP throttle rows, and aged webhook deliveries.';
