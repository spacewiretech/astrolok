import {
  cashfreeSettings,
  dedupeKey,
  disputeFrom,
  notificationKey,
  paymentFrom,
  refundFrom,
  skewSeconds,
  subscriptionIdsFrom,
  verifyWebhook,
} from "../_shared/cashfree.ts";
import { loadConfig } from "../_shared/config.ts";
import { corsHeaders, json } from "../_shared/cors.ts";
import { serviceClient } from "../_shared/db.ts";
import { configureMixpanel, trackServer } from "../_shared/mixpanel.ts";
import {
  asSubscriptionRow,
  recordDispute,
  recordPayment,
  recordRefund,
  SUBSCRIPTION_COLUMNS,
  syncSubscription,
} from "../_shared/subscription_sync.ts";

/**
 * Cashfree's server-to-server notifications. This is the only path by which an account becomes
 * paid, so it is also the only path worth attacking.
 *
 * Three rules hold it together:
 *
 *  1. Nothing is *acted on* until the HMAC over the raw bytes verifies. The body is parsed
 *     before that — an unverifiable delivery still has to be recorded and counted, and an unset
 *     secret still fails closed with a 503 — but what comes out of it is only ever used to name
 *     a subscription, never as the state to write. See rule 3.
 *  2. Every delivery is recorded before it is acted on, under a unique dedupe key, so a
 *     redelivery is a no-op — unless the first attempt never finished, in which case it is
 *     deliberately retried.
 *  3. The payload is treated as a hint, never as data. Its only job is to name a subscription;
 *     the state that gets written comes from asking Cashfree what that subscription looks like
 *     now. That is what makes duplicate and out-of-order deliveries harmless.
 */

/** Bounded so a flood of forged calls cannot be used to fill the audit table. */
const MAX_RECORDED_BODY = 64 * 1024;

const UNIQUE_VIOLATION = "23505";

/**
 * Deliveries of one notification before it is called a storm.
 *
 * Cashfree's early retries are about a minute apart, so this is roughly ten minutes of a webhook
 * that will not go through — comfortably past any transient failure, and long before a day of
 * retries has gone by with nobody told.
 */
const RETRY_STORM_THRESHOLD = 10;

function ok(body: Record<string, unknown>): Response {
  return json(body, 200);
}

/**
 * The user behind a charge, for the events that name a payment but no subscription.
 *
 * A refund or a chargeback arrives months after the mandate it belongs to, and carries only a
 * `cf_payment_id`. The ledger is the only thing that can turn that back into a person.
 */
async function userForPayment(
  db: ReturnType<typeof serviceClient>,
  cfPaymentId: string | null,
): Promise<string | null> {
  if (!cfPaymentId) return null;
  const { data } = await db
    .from("subscription_payments")
    .select("user_id")
    .eq("cf_payment_id", cfPaymentId)
    .maybeSingle();
  return (data?.user_id as string | undefined) ?? null;
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }
  if (req.method !== "POST") {
    return new Response("method not allowed", { status: 405, headers: corsHeaders });
  }

  // Must be the exact bytes Cashfree signed. Parsing first and re-serialising reorders keys
  // and the signature silently stops matching.
  const raw = await req.text();
  const signature = req.headers.get("x-webhook-signature");
  const timestamp = req.headers.get("x-webhook-timestamp");

  const db = serviceClient();
  const config = await loadConfig(db);
  configureMixpanel(config, "cashfree-webhook");

  // Parsed before the secret is looked up, so that a delivery arriving at a misconfigured
  // deployment can still be identified and counted. This reads the body without having verified
  // it, which is safe only because nothing below *acts* on it until `verified` is checked — the
  // payload is a hint about which subscription to go and ask Cashfree about, never data.
  let payload: Record<string, unknown> = {};
  try {
    payload = raw ? JSON.parse(raw) : {};
  } catch {
    payload = {};
  }

  const eventType = typeof payload.type === "string"
    ? payload.type
    : typeof payload.event === "string"
    ? payload.event
    : "UNKNOWN";

  const stamp = timestamp ?? "";
  const key = await dedupeKey(eventType, stamp, raw);

  // The analytics identity, which is emphatically *not* `key`. See `notificationKey`: `key`
  // changes on every delivery attempt, which is right for the money path and ruinous for the
  // event stream hanging off it.
  const notification = await notificationKey(eventType, payload, raw);

  // Assigned once the secret is in hand. `reportDelivery` closes over it and reads it at call
  // time, so the one outcome reported before verification is possible still reports honestly.
  let verified = false;

  // Recorded whether or not it verified: a forged call is worth being able to see. See
  // `skewSeconds` — computing this wrong is what took the webhook path down.
  const skew = skewSeconds(timestamp);
  const ids = subscriptionIdsFrom(payload);

  // Everything known about *why* this delivery arrived, attached to whichever outcome it reaches.
  // The cause — Cashfree's own event type — is the property the whole webhook funnel breaks down
  // by: a renewal, an authorisation and a mandate going on hold all land on this one endpoint and
  // are otherwise indistinguishable once processed.
  let deliveryUserId: string | null = null;
  let reported = false;

  // Declared up here rather than beside the insert below because `reportDelivery` closes over it
  // and the `not_configured` exit calls it before the insert has run — reading a `let` from its
  // temporal dead zone would throw inside the one handler that must never throw.
  let eventId: number | undefined;

  const reportDelivery = async (
    outcome: string,
    extra: Record<string, unknown> = {},
  ): Promise<void> => {
    // Exactly one per delivery. Several exit paths below can be reached in sequence, and a
    // webhook counted twice would double every denominator built on this event.
    if (reported) return;
    reported = true;

    // ------------------------------------------------------------------ DISABLED 2026-09-09
    //
    // `Webhook Received` is switched off at the source, not merely deduplicated.
    //
    // The per-notification suppression below works, but it cannot help here: this endpoint
    // receives the whole Cashfree merchant account's traffic, and most of it belongs to other
    // products — subscription ids arriving as `ca_*` and `mt_*` against our own `alk_*`. Each of
    // those is a genuinely distinct notification, so every one earns its own event and no
    // dedupe is entitled to collapse them. The volume is real, it is simply not ours.
    //
    // Everything else still records: `payment_events` keeps the full audit row for every
    // delivery, so nothing is lost that this event was carrying — it can be reconstructed from
    // the table whenever it is wanted.
    //
    // TO RESTORE: delete this `return` and uncomment the block beneath it. Worth doing only once
    // the foreign traffic is dealt with — either separate Cashfree accounts per product, or an
    // early exit for `unknown_subscription` before it reaches here.
    return;

    /*
    // And exactly one per *notification*, which is the stronger guarantee and the one that
    // matters. Cashfree retries a non-2xx answer roughly once a minute for as long as it keeps
    // getting one; without this, a single webhook the handler cannot process produces an
    // unbounded stream of events that buries every other event in the project.
    //
    // Keyed on the outcome as well, so only the *repetition* is silenced: a delivery that fails
    // ten times and then succeeds still reports its `handled`, which is exactly the transition
    // someone reading this funnel needs to see.
    const { data: alreadyReported } = await db
      .from("payment_events")
      .select("id")
      .eq("notification_key", notification)
      .eq("reported_outcome", outcome)
      .limit(1)
      .maybeSingle();

    if (alreadyReported) return;

    await trackServer({
      event: "Webhook Received",
      distinctId: deliveryUserId,
      // The notification key, never the delivery key: a redelivery of the same notification has
      // to resolve to the same id or Mixpanel counts it again. The outcome is part of the id
      // because the same notification legitimately reports twice when a retry finally succeeds.
      insertId: `wh:${notification}:${outcome}`,
      properties: {
        outcome,
        // The cause.
        cf_event_type: eventType,
        signature_ok: verified,
        skew_seconds: Number.isFinite(skew) ? skew : null,
        cf_subscription_id: ids.cfSubscriptionId,
        subscription_id: ids.subscriptionId,
        header_timestamp: timestamp,
        body_bytes: raw.length,
        ...extra,
      },
    });

    // Claimed after the send, so a failure to record leaves the notification reportable rather
    // than silently swallowing it. The worst case is one duplicate event, which `$insert_id`
    // collapses anyway.
    if (eventId !== undefined) {
      await db
        .from("payment_events")
        .update({ reported_at: new Date().toISOString(), reported_outcome: outcome })
        .eq("id", eventId);
    }
    */
  };

  /**
   * The one event that survives the suppression above, and the reason it can be trusted.
   *
   * Reporting a notification once means a webhook Cashfree can never deliver successfully goes
   * quiet after its first event — which is precisely the blindness that let this run at a
   * delivery a minute unnoticed. So when the deliveries of one notification cross a threshold,
   * say so, exactly once: the `$insert_id` is fixed per notification, so repeated crossings and
   * concurrent deliveries both collapse onto the same event.
   *
   * Counted as rows sharing `notification_key` rather than as a column on one row, because a
   * retry carrying a fresh `x-webhook-timestamp` gets a fresh `dedupe_key` and therefore a whole
   * new row — a per-row counter would sit at 1 through the loudest storm.
   */
  const reportRetryStorm = async (): Promise<void> => {
    const { count } = await db
      .from("payment_events")
      .select("id", { count: "exact", head: true })
      .eq("notification_key", notification);

    // Exactly equal, not "at least": the count climbs by one per delivery, so equality fires on
    // one delivery and no other. `>=` would send a request a minute for as long as the storm ran
    // — collapsed into one event by `$insert_id`, but still spending the ingestion this whole
    // change exists to stop spending.
    if (count !== RETRY_STORM_THRESHOLD) return;

    await trackServer({
      event: "Webhook Retrying",
      distinctId: deliveryUserId,
      insertId: `wh:${notification}:retry_storm`,
      properties: {
        cf_event_type: eventType,
        deliveries: count,
        signature_ok: verified,
        cf_subscription_id: ids.cfSubscriptionId,
        subscription_id: ids.subscriptionId,
      },
    });
  };

  let settings;
  try {
    settings = cashfreeSettings(config);
  } catch (error) {
    console.error("cashfree webhook cannot verify: settings unavailable", error);
    // A rotated-away or unset secret stops the only path by which an account becomes paid, and
    // would otherwise do it in total silence — nothing recorded, nothing counted, only a log
    // line nobody reads until a user complains they paid and got nothing.
    await reportDelivery("not_configured");
    return new Response("payments not configured", { status: 503, headers: corsHeaders });
  }

  verified = await verifyWebhook(settings.secret, timestamp, signature, raw);

  const eventRow = {
    event_type: eventType,
    dedupe_key: key,
    notification_key: notification,
    signature_ok: verified,
    header_timestamp: timestamp,
    skew_seconds: Number.isFinite(skew) ? skew : null,
    cf_subscription_id: ids.cfSubscriptionId,
    subscription_id: ids.subscriptionId,
    payload: raw.length <= MAX_RECORDED_BODY ? payload : { truncated: raw.length },
  };

  const { data: inserted, error: insertError } = await db
    .from("payment_events")
    .insert(eventRow)
    .select("id, processed_at")
    .single();

  eventId = inserted?.id as number | undefined;

  if (insertError) {
    if (insertError.code !== UNIQUE_VIOLATION) {
      console.error("payment_events insert failed", insertError);
      // The only exit that would otherwise skip reporting entirely. A database that cannot take
      // the audit row is the one failure where the webhook funnel goes quiet with no trace.
      await reportDelivery("record_failed", { error: insertError.message.slice(0, 300) });
      return new Response("could not record event", { status: 500, headers: corsHeaders });
    }

    // Seen before. Only skip if the first attempt actually finished — otherwise a transient
    // failure would be swallowed permanently by its own audit row.
    const { data: prior } = await db
      .from("payment_events")
      .select("id, processed_at")
      .eq("dedupe_key", key)
      .maybeSingle();

    if (prior?.processed_at) {
      await reportDelivery("duplicate");
      return ok({ duplicate: true });
    }

    // Seen before but never finished, and we cannot even find the row to mark. Processing now
    // would run the money path with no way to record that it ran, so every retry would run it
    // again. Fail instead and let Cashfree redeliver into a state that can be recorded.
    if (prior?.id == null) {
      console.error(`payment_events conflict on ${key} but no row to resume`);
      await reportDelivery("unrecoverable");
      return new Response("could not record event", { status: 500, headers: corsHeaders });
    }
    eventId = prior.id as number;
  }

  await reportRetryStorm();

  if (!verified) {
    console.error(
      `cashfree webhook signature mismatch: type=${eventType} ` +
        `sub=${ids.subscriptionId ?? "?"} skew=${skew ?? "?"}s`,
    );
    // A forged or misconfigured caller. Worth an event rather than only a log line: a sudden run
    // of these is either an attack or the webhook secret having been rotated on one side only,
    // and both need noticing before the money path silently stops working.
    await reportDelivery("signature_rejected");
    return new Response("invalid signature", { status: 401, headers: corsHeaders });
  }

  const finish = async (error?: string) => {
    if (eventId === undefined) return;
    await db
      .from("payment_events")
      .update({ processed_at: new Date().toISOString(), process_error: error ?? null })
      .eq("id", eventId);
  };

  try {
    // Cashfree's own id is the fallback: a few event shapes carry it without ours.
    let subscriptionId = ids.subscriptionId;
    if (!subscriptionId && ids.cfSubscriptionId) {
      const { data } = await db
        .from("subscriptions")
        .select("subscription_id")
        .eq("cf_subscription_id", ids.cfSubscriptionId)
        .maybeSingle();
      subscriptionId = (data?.subscription_id as string | undefined) ?? null;
    }

    // Read once, here, rather than inside the subscription branch below. `reportDelivery` stamps
    // whatever `deliveryUserId` holds at the moment it is called, and every branch between here
    // and there — refund, dispute, ignored, unknown — reports before the branch that would
    // otherwise assign it. They would all go out as `unattributed:…` even when the user is
    // perfectly well known, which makes the whole `Webhook Received` funnel unjoinable to a
    // person.
    const { data: subscriptionRow } = subscriptionId
      ? await db
        .from("subscriptions")
        .select(SUBSCRIPTION_COLUMNS)
        .eq("subscription_id", subscriptionId)
        .maybeSingle()
      : { data: null };

    if (subscriptionRow) {
      deliveryUserId = asSubscriptionRow(subscriptionRow).user_id;
    }

    // Payment-scoped events — refunds and disputes — name no subscription, only a payment. The
    // ledger ties every charge to its mandate, so they resolve through that instead. Handled
    // before the subscription branch because they will never satisfy it.
    const refund = refundFrom(payload);
    if (refund) {
      await recordRefund(db, settings, refund);
      deliveryUserId ??= await userForPayment(db, refund.cfPaymentId);
      await finish();
      await reportDelivery("handled", {
        kind: "refund",
        cf_refund_id: refund.cfRefundId,
        cf_payment_id: refund.cfPaymentId,
        amount: refund.amount,
        currency: refund.currency,
        refund_status: refund.status,
        refund_reason: refund.reason,
      });
      return ok({ handled: true, event: eventType, kind: "refund" });
    }

    const dispute = disputeFrom(payload);
    if (dispute) {
      await recordDispute(db, settings, dispute);
      deliveryUserId ??= await userForPayment(db, dispute.cfPaymentId);
      await finish();
      await reportDelivery("handled", {
        kind: "dispute",
        cf_dispute_id: dispute.cfDisputeId,
        cf_payment_id: dispute.cfPaymentId,
        dispute_status: dispute.status,
      });
      return ok({ handled: true, event: eventType, kind: "dispute" });
    }

    if (!subscriptionId) {
      // Everything else that names nothing we own: one-time PG order events (this app opens no
      // orders), settlement notices, pre-debit reminders. Recorded in payment_events and
      // acknowledged, because a 200 is what stops Cashfree retrying an event we will never act
      // on — and marking it processed is what stops it being retried forever.
      await finish();
      await reportDelivery("ignored", { reason: "no subscription, refund or dispute" });
      return ok({ ignored: true, event: eventType, reason: "no subscription, refund or dispute" });
    }

    if (!subscriptionRow) {
      // A mandate Cashfree knows about and we do not. Almost always a webhook from a different
      // environment pointed at this project; either way it must not be silently dropped.
      console.error(`webhook for unknown subscription ${subscriptionId}`);
      await finish("unknown subscription");
      // Counting them is how that gets noticed at all.
      await reportDelivery("unknown_subscription");
      return ok({ ignored: true, event: eventType });
    }

    const row = asSubscriptionRow(subscriptionRow);

    const payment = paymentFrom(payload);
    if (payment) {
      await recordPayment(db, settings, row, payment, eventType);
    }

    // The authoritative step: ask Cashfree what is true now and write that.
    const result = await syncSubscription(db, settings, subscriptionId);

    await finish();
    await reportDelivery("handled", {
      kind: payment ? "payment" : "status",
      subscription_status: result.snapshot.status,
      payment_type: result.user.payment_type,
      entitled_until: result.user.current_period_end,
      next_billing_at: result.snapshot.nextScheduleDate,
      cf_payment_id: payment?.cfPaymentId,
      payment_status: payment?.status,
      amount: payment?.amount,
    });
    return ok({ handled: true, event: eventType });
  } catch (error) {
    const detail = String(error);
    console.error(`cashfree webhook processing failed for ${eventType}: ${detail}`);
    await finish(detail.slice(0, 500));
    await reportDelivery("failed", { error: detail.slice(0, 300) });
    // 500 so Cashfree retries. The dedupe row is left unprocessed, so the retry runs for real.
    return new Response("processing failed", { status: 500, headers: corsHeaders });
  }
});
