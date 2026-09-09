-- The reconcile sweep had a blind spot the width of a billing cycle.
--
-- It only ever looked at mandates whose `next_schedule_date` was already overdue, plus trials past
-- their grace. Both are about a debit that should have happened and did not. Nothing looked at a
-- mandate that simply *stopped being live* — a user cancelling UPI Autopay in their PSP app lands
-- the subscription in `CUSTOMER_CANCELLED` at Cashfree, and if that webhook is dropped, missed or
-- pointed at the wrong project, nothing here notices until the next debit date comes and goes.
--
-- Until then the account keeps `payment_type = 'active'` and full access, and the churn event
-- never fires. On a monthly plan that is up to a month of free service and a month of analytics
-- saying the user is still subscribed.
--
-- This is the window for the third sweep: any live mandate not checked against Cashfree in this
-- many hours gets asked about, oldest first. Small enough that a lost cancellation surfaces the
-- same day; large enough that the hourly job re-checks each mandate a handful of times a day
-- rather than on every run.
insert into public.app_config (key, value, is_public, description) values
  ('reconcile_stale_hours', '6', false,
   'How long a live mandate may go unchecked before subscription-reconcile asks Cashfree about '
   'it, independent of any due debit. This is the ceiling on how long a dropped cancellation '
   'webhook can leave an account entitled. 0 disables the sweep.')
on conflict (key) do nothing;
