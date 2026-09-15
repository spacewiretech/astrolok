/**
 * Which monthly price an account pays: the ₹499 plan, or the ₹299 plan new signups are split
 * against.
 *
 * The split itself is decided once, at signup, by `assign_plan_variant` in
 * `20260915000004_pricing_plans.sql`. This module turns the stored variant into a plan, and
 * [planFor] is the one resolution both the paywall payload and `subscription-start` use — so the
 * price on screen, the UPI Autopay consent line and the mandate that gets opened cannot disagree.
 *
 * A user only ever sees their own plan. The ₹299 rows are private, and what reaches the device is
 * [planPayload] of that user's plan alone: never a plan id, never the other price.
 *
 * Reads no Cashfree credentials, for the same reason `graceHoursFrom` doesn't: `me` must keep
 * working when payments are misconfigured.
 */

import { SupabaseClient } from "jsr:@supabase/supabase-js@2";

import { AppConfig, configFlag, configSetting } from "./config.ts";

export type PlanVariant = "plan_499" | "plan_299";

/** Every account that predates the split, and anyone the split does not apply to. */
export const DEFAULT_VARIANT: PlanVariant = "plan_499";

export interface PricingPlan {
  variant: PlanVariant;
  /** The pre-created Cashfree PERIODIC plan a mandate is opened against. */
  planId: string;
  /** Cashfree's name for the plan. Tracking only. */
  planName: string;
  recurringAmount: number;
  /** Paywall copy, e.g. `₹299`. */
  priceLabel: string;
}

export interface PricingPlans {
  standard: PricingPlan;
  /** Null until its Cashfree plan id is filled in, which is what keeps the split off. */
  alternate: PricingPlan | null;
}

/**
 * Same parse `cashfreeSettings` has always used, so the ₹499 amount reads identically here and
 * there. A blank cell reads as 0, which `subscription-start` refuses rather than authorising.
 */
function amountFrom(config: AppConfig, key: string, fallback: number): number {
  const parsed = Number(configSetting(config, key));
  return Number.isFinite(parsed) && parsed >= 0 ? parsed : fallback;
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

  const alternateId = configSetting(config, "cashfree_plan_id_299");
  const alternateAmount = amountFrom(config, "cashfree_recurring_amount_299", 299);
  const alternate: PricingPlan | null = alternateId && alternateAmount > 0
    ? {
      variant: "plan_299",
      planId: alternateId,
      planName: configSetting(config, "cashfree_plan_name_299"),
      recurringAmount: alternateAmount,
      priceLabel: configSetting(config, "plan_price_label_299") || `₹${alternateAmount}`,
    }
    : null;

  return { standard, alternate };
}

/**
 * The plan an account with [variant] pays.
 *
 * A `plan_299` account falls back to ₹499 if the ₹299 plan is ever unconfigured. That is a worse
 * price for them, but it is still the same answer on screen and at Cashfree, which is the property
 * that matters — a mandate opened against a blank plan id would fail at checkout instead.
 */
export function planFor(config: AppConfig, variant: string | null | undefined): PricingPlan {
  const { standard, alternate } = pricingPlans(config);
  return variant === "plan_299" && alternate ? alternate : standard;
}

/** Whether new signups alternate. Needs the switch *and* a ₹299 plan to alternate onto. */
export function splitEnabled(config: AppConfig): boolean {
  return configFlag(config, "pricing_split_enabled") && pricingPlans(config).alternate !== null;
}

/** The part of a plan the device is given: its own price, never the plan id or the other plan. */
export function planPayload(plan: PricingPlan): Record<string, unknown> {
  return {
    variant: plan.variant,
    price_label: plan.priceLabel,
    amount: plan.recurringAmount,
  };
}

/**
 * Puts a new account on a plan, and returns it.
 *
 * Never throws: this sits on sign-in, and a failed assignment must cost the account its place in
 * the split, never its login. The row stays null on failure, so the next sign-in tries again.
 */
export async function assignPlanVariant(
  db: SupabaseClient,
  userId: string,
  split: boolean,
): Promise<PlanVariant> {
  try {
    const { data, error } = await db.rpc("assign_plan_variant", {
      p_user_id: userId,
      p_split: split,
    });
    if (!error && (data === "plan_499" || data === "plan_299")) return data;
    console.error(`could not assign a plan to ${userId}`, error ?? data);
  } catch (error) {
    console.error(`could not assign a plan to ${userId}`, error);
  }
  return DEFAULT_VARIANT;
}
