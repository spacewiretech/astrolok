-- The Cashfree account that mandates opened before 2026-09-14 still live in.
--
-- On 2026-09-14 the Cashfree credentials and `cashfree_plan_id` were switched to a new dashboard.
-- The mandates already open did not move with them: they are still live in the old account, still
-- debiting ₹499 a month, and the new credentials answer `subscription_not_found` for every one.
--
-- Three things broke as a result, all of them silent:
--
--   * `syncSubscription` threw for each one, so `subscriptions.updated_at` never advanced and they
--     sat permanently at the head of `subscription-reconcile`'s queue, starving every mandate
--     behind them.
--   * Their webhooks are signed with the old account's client secret, so every delivery failed
--     verification and was answered 401.
--   * `subscription-cancel` could not cancel them at all, so a user asking to stop paying kept
--     being billed.
--
-- With these rows filled in, `settingsForPlan` routes any call about a mandate on one of these
-- plans to the old credentials, and `webhookSecrets` accepts deliveries signed by either account.
--
-- Blank by default: `legacyAccount` requires all three, so an unconfigured deployment behaves
-- exactly as it did before.
--
-- TO RETIRE: once no mandate on these plans is still live — check with
--   select count(*) from public.subscriptions
--    where plan_id = any (string_to_array(
--            (select value from public.app_config where key = 'cashfree_legacy_plan_ids'), ','))
--      and status in ('ACTIVE','ON_HOLD','PAUSED','PENDING_AUTHORIZATION','INITIALIZED');
-- blank `cashfree_legacy_plan_ids` and the routing switches itself off.

insert into public.app_config (key, value, is_public, description) values
  ('cashfree_legacy_app_id', '', false,
   'x-client-id of the Cashfree account holding pre-2026-09-14 mandates. Blank disables legacy routing.'),
  ('cashfree_legacy_secret_key', '', false,
   'x-client-secret of that account. Also accepted as a webhook signing secret, since it still '
   'delivers subscription events for those mandates.'),
  ('cashfree_legacy_plan_ids', '', false,
   'Comma-separated Cashfree plan ids whose mandates live in the legacy account, e.g. '
   'id_circle360_499,plan_1788962992020_1qt81t. Blank disables legacy routing.')
on conflict (key) do nothing;
