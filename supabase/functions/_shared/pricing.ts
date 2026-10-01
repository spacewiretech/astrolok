/**
 * Which monthly price an account pays: the ₹499 plan, the ₹699 plan new signups are split against,
 * or the ₹299 plan the split used to run against.
 *
 * The split itself is decided once, at signup, by `assign_plan_variant` in
 * `20260929000003_plan_699.sql`. This module turns the stored variant into a plan, and [planFor]
 * is the one resolution both the paywall payload and `subscription-start` use — so the price on
 * screen, the UPI Autopay consent line and the mandate that gets opened cannot disagree.
 *
 * ₹299 is closed to new signups, not withdrawn. Every account already on it keeps it — the live
 * mandates debit ₹299 at Cashfree whatever this says, and a lapsed ₹299 subscriber who comes back
 * opens a ₹299 mandate again — so its config rows stay filled in for as long as anyone is on it.
 *
 * A user only ever sees their own plan. The ₹699 and ₹299 rows are private, and what reaches the
 * device is [planPayload] of that user's plan alone: never a plan id, never another price.
 *
 * Reads no Cashfree credentials, for the same reason `graceHoursFrom` doesn't: `me` must keep
 * working when payments are misconfigured.
 */

import { SupabaseClient } from "jsr:@supabase/supabase-js@2";

import { AppConfig, configFlag, configSetting } from "./config.ts";

export type PlanVariant = "plan_499" | "plan_699" | "plan_299";

const VARIANTS: ReadonlySet<string> = new Set(["plan_499", "plan_699", "plan_299"]);

/** Every account that predates the split, and anyone the split does not apply to. */
export const DEFAULT_VARIANT: PlanVariant = "plan_499";

/** The variant new signups are split against today. */
export const ALTERNATE_VARIANT: PlanVariant = "plan_699";

export interface PricingPlan {
  variant: PlanVariant;
  /** The pre-created Cashfree PERIODIC plan a mandate is opened against. */
  planId: string;
  /** Cashfree's name for the plan. Tracking only. */
  planName: string;
  recurringAmount: number;
  /** Paywall copy, e.g. `₹699`. */
  priceLabel: string;
}

export interface PricingPlans {
  standard: PricingPlan;
  /** ₹699. Null until its Cashfree plan id is filled in, which is what keeps the split off. */
  alternate: PricingPlan | null;
  /** ₹299. No new signups, but still what every account already on it pays. */
  grandfathered: PricingPlan | null;
}

/**
 * Same parse `cashfreeSettings` has always used, so the ₹499 amount reads identically here and
 * there. A blank cell reads as 0, which `subscription-start` refuses rather than authorising.
 */
function amountFrom(config: AppConfig, key: string, fallback: number): number {
  const parsed = Number(configSetting(config, key));
  return Number.isFinite(parsed) && parsed >= 0 ? parsed : fallback;
}

/** A plan from its `_<suffix>` config rows, or null while it has no id or no amount to charge. */
function suffixedPlan(
  config: AppConfig,
  variant: PlanVariant,
  suffix: string,
  fallbackAmount: number,
): PricingPlan | null {
  const planId = configSetting(config, `cashfree_plan_id_${suffix}`);
  const amount = amountFrom(config, `cashfree_recurring_amount_${suffix}`, fallbackAmount);
  if (!planId || amount <= 0) return null;
  return {
    variant,
    planId,
    planName: configSetting(config, `cashfree_plan_name_${suffix}`),
    recurringAmount: amount,
    priceLabel: configSetting(config, `plan_price_label_${suffix}`) || `₹${amount}`,
  };
}

export function pricingPlans(config: AppConfig): PricingPlans {
  const standardAmount = amountFrom(config, "cashfree_recurring_amount", 249);
  const standard: PricingPlan = {
    variant: "plan_499",
    planId: configSetting(config, "cashfree_plan_id"),
    planName: configSetting(config, "cashfree_plan_name"),
    recurringAmount: standardAmount,
    priceLabel: configSetting(config, "plan_price_label") || `₹${standardAmount}`,
  };

  return {
    standard,
    alternate: suffixedPlan(config, "plan_699", "699", 699),
    grandfathered: suffixedPlan(config, "plan_299", "299", 299),
  };
}

/** Every plan a mandate can be on right now, ₹499 first. */
export function configuredPlans(config: AppConfig): PricingPlan[] {
  const { standard, alternate, grandfathered } = pricingPlans(config);
  return [standard, alternate, grandfathered].filter((plan): plan is PricingPlan => plan !== null);
}

/**
 * The plan an account with [variant] pays.
 *
 * A `plan_699` or `plan_299` account falls back to ₹499 if its plan is ever unconfigured. That is a
 * different price for them, but it is still the same answer on screen and at Cashfree, which is the
 * property that matters — a mandate opened against a blank plan id would fail at checkout instead.
 */
export function planFor(config: AppConfig, variant: string | null | undefined): PricingPlan {
  const { standard, alternate, grandfathered } = pricingPlans(config);
  if (variant === "plan_699" && alternate) return alternate;
  if (variant === "plan_299" && grandfathered) return grandfathered;
  return standard;
}

/** Whether new signups are split at all. Needs the switch *and* a ₹699 plan to split onto. */
export function splitEnabled(config: AppConfig): boolean {
  return configFlag(config, "pricing_split_enabled") && pricingPlans(config).alternate !== null;
}

/**
 * The share of new signups, 0–100, put on ₹699 while the split is on. The rest get ₹499.
 *
 * Unreadable reads as 0 — everyone on ₹499 — because that is the price every existing account and
 * every old build already shows. Whole percents only; a fraction is rounded.
 */
export function alternatePercent(config: AppConfig): number {
  const raw = configSetting(config, "pricing_split_699_percent");
  const parsed = Number(raw);
  if (!raw || !Number.isFinite(parsed)) return 0;
  return Math.min(100, Math.max(0, Math.round(parsed)));
}

/** The part of a plan the device is given: its own price, never the plan id or another plan. */
export function planPayload(plan: PricingPlan): Record<string, unknown> {
  return {
    variant: plan.variant,
    price_label: plan.priceLabel,
    amount: plan.recurringAmount,
  };
}

/**
 * Puts a new account on a plan, and returns it. With [split] off, that is always ₹499.
 *
 * Never throws: this sits on sign-in, and a failed assignment must cost the account its place in
 * the split, never its login. The row stays null on failure, so the next sign-in tries again.
 */
export async function assignPlanVariant(
  db: SupabaseClient,
  userId: string,
  split: boolean,
  percent: number,
): Promise<PlanVariant> {
  try {
    const { data, error } = await db.rpc("assign_plan_variant", {
      p_user_id: userId,
      p_split: split,
      p_alternate: ALTERNATE_VARIANT,
      p_alternate_percent: percent,
    });
    if (!error && typeof data === "string" && VARIANTS.has(data)) return data as PlanVariant;
    console.error(`could not assign a plan to ${userId}`, error ?? data);
  } catch (error) {
    console.error(`could not assign a plan to ${userId}`, error);
  }
  return DEFAULT_VARIANT;
}
