import { paymentFrom, WebhookPayment } from "./cashfree.ts";

/**
 * The decisions behind `payment-sync`, the every-minute worker that processes queued Cashfree
 * webhooks. Pure, so they can be tested without a database or a Cashfree account.
 *
 * The worker exists because the webhook ran the whole money path once per delivery, and Cashfree
 * sends three or four deliveries per checkout within seconds, every one re-syncing the same
 * mandate. Queued, they collapse: each subscription syncs once per run, and a charge the ledger
 * already holds at that status is not recorded again.
 */

/** A delivery as `claim_payment_events` hands it over. */
export interface PendingEvent {
  id: number;
  event_type: string | null;
  subscription_id: string | null;
  cf_subscription_id: string | null;
  payload: Record<string, unknown> | null;
  received_at: string;
  attempts: number;
}

/**
 * Whether a delivery names another product's mandate, not ours.
 *
 * The Cashfree merchant account is shared, and every notification it sends lands on this project's
 * webhook. Ours are all `alk_…` (`subscription-start` makes them; every plan, the legacy account's
 * included). The rest, `c360_…`, `ca_…` and `mt_…`, are signed with another product's secret. So
 * they fail verification, were answered 401, and Cashfree retried each several times: about 6,600
 * a day, 2026-09-28, none with a local row.
 *
 * No id at all is not foreign. A refund or a dispute names only a payment, and could be ours.
 */
export function isForeignSubscription(subscriptionId: string | null | undefined): boolean {
  return typeof subscriptionId === "string" && subscriptionId.length > 0 &&
    !subscriptionId.startsWith("alk_");
}

export interface EventGroups {
  /** Our subscription id → its deliveries, oldest first. */
  bySubscription: Map<string, PendingEvent[]>;
  /** Deliveries that name no subscription we could resolve. */
  unresolved: PendingEvent[];
}

/**
 * Groups deliveries by the subscription they are about, oldest first within each group, so the
 * worker syncs each mandate once however many deliveries named it.
 *
 * A delivery that carries only Cashfree's id resolves through [localByCfId]. One that resolves to
 * nothing is `unresolved`, and the worker acknowledges it the way the webhook always has.
 */
export function groupPendingEvents(
  events: PendingEvent[],
  localByCfId: ReadonlyMap<string, string>,
): EventGroups {
  const bySubscription = new Map<string, PendingEvent[]>();
  const unresolved: PendingEvent[] = [];

  const ordered = [...events].sort((a, b) =>
    new Date(a.received_at).getTime() - new Date(b.received_at).getTime() || a.id - b.id
  );

  for (const event of ordered) {
    const subscriptionId = event.subscription_id ??
      (event.cf_subscription_id ? localByCfId.get(event.cf_subscription_id) ?? null : null);
    if (!subscriptionId) {
      unresolved.push(event);
      continue;
    }
    const group = bySubscription.get(subscriptionId);
    if (group) group.push(event);
    else bySubscription.set(subscriptionId, [event]);
  }

  return { bySubscription, unresolved };
}

export interface ChargeToRecord {
  event: PendingEvent;
  payment: WebhookPayment;
}

/**
 * The charges in [events] worth recording, in the order they arrived.
 *
 * A charge the ledger already holds at the same status is dropped: `recordPayment` on it would
 * rewrite six rows to the values they already hold, and 38% of payment deliveries were exactly
 * that. `SUBSCRIPTION_AUTH_STATUS` and `SUBSCRIPTION_PAYMENT_*` both announce the same charge.
 *
 * [ledger] maps `cf_payment_id` to the status recorded at the start of the run, and is updated as
 * charges are taken, so two deliveries of the same charge and status in one run record it once. A
 * change of status (PENDING, then SUCCESS) is always recorded.
 */
export function chargesToRecord(events: PendingEvent[], ledger: Map<string, string>): ChargeToRecord[] {
  const charges: ChargeToRecord[] = [];
  for (const event of events) {
    const payment = event.payload ? paymentFrom(event.payload) : null;
    if (!payment) continue;
    if (ledger.get(payment.cfPaymentId) === payment.status) continue;
    ledger.set(payment.cfPaymentId, payment.status);
    charges.push({ event, payment });
  }
  return charges;
}

/** Every `cf_payment_id` the deliveries carry, for one ledger read per run. */
export function paymentIdsOf(events: PendingEvent[]): string[] {
  const ids = new Set<string>();
  for (const event of events) {
    const payment = event.payload ? paymentFrom(event.payload) : null;
    if (payment) ids.add(payment.cfPaymentId);
  }
  return [...ids];
}

/** [items] in slices of [size], so an `in (...)` filter keeps its URL short. */
export function chunked<T>(items: T[], size: number): T[][] {
  const chunks: T[][] = [];
  for (let i = 0; i < items.length; i += size) chunks.push(items.slice(i, i + size));
  return chunks;
}
