-- One Mixpanel event per notification, not per delivery attempt.
--
-- `Webhook Received` was keyed on `dedupe_key`, which hashes the `x-webhook-timestamp` header.
-- Cashfree stamps that per delivery *attempt* and retries anything that answers non-2xx, so a
-- notification the handler could not process emitted a brand-new, un-dedupable event on every
-- retry — roughly one a minute, indefinitely, drowning out every other event in the project.
--
-- `dedupe_key` itself is deliberately left alone: it guards the money path, where a retry after
-- a failed attempt is *supposed* to run again. These columns give the analytics its own, coarser
-- identity to suppress against.

alter table public.payment_events
  -- Identity of the notification rather than of the delivery, stable across redeliveries. See
  -- `notificationKey` in functions/_shared/cashfree.ts. Nullable: rows predating this have none.
  add column if not exists notification_key text,

  -- Set the first time a delivery of this notification is reported to Mixpanel under
  -- `reported_outcome`. Later deliveries reaching the same outcome find it and send nothing.
  add column if not exists reported_at timestamptz,

  -- Which outcome was reported. Part of the key rather than a bare flag so that a retry storm
  -- (the same outcome forever) is silenced while a notification that finally *succeeds* still
  -- reports its `handled` — otherwise the recovery would be invisible.
  add column if not exists reported_outcome text;

-- Serves both questions asked of these columns: "has this notification already been reported
-- under this outcome" on both columns, and "how many times has it been delivered" on the first.
create index if not exists payment_events_notification_idx
  on public.payment_events (notification_key, reported_outcome);

comment on column public.payment_events.notification_key is
  'Identity of the notification, stable across Cashfree redeliveries. Analytics dedupe only — '
  'dedupe_key remains the money-path guard, and stays per-delivery on purpose.';
