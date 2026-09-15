/**
 * The price split: which plan an account pays, and when new signups alternate at all.
 *
 * The failures worth guarding are quiet ones. A ₹299 account resolved to a blank Cashfree plan id
 * opens a mandate that fails at checkout, and a split switched on without a ₹299 plan would hand
 * people a price nothing can charge.
 */

import { assert, assertEquals, assertFalse } from "jsr:@std/assert@1";

import { AppConfig } from "../_shared/config.ts";
import { planFor, planPayload, pricingPlans, splitEnabled } from "../_shared/pricing.ts";

function config(rows: Record<string, string>): AppConfig {
  return new Map(Object.entries(rows));
}

const BOTH = {
  cashfree_plan_id: "astrolok_499",
  cashfree_plan_name: "Astrolok Monthly",
  cashfree_recurring_amount: "499",
  plan_price_label: "₹499",
  cashfree_plan_id_299: "astrolok_299",
  cashfree_plan_name_299: "Astrolok Monthly 299",
  cashfree_recurring_amount_299: "299",
  plan_price_label_299: "₹299",
};

Deno.test("a ₹299 account is priced on the ₹299 plan", () => {
  const plan = planFor(config(BOTH), "plan_299");

  assertEquals(plan.variant, "plan_299");
  assertEquals(plan.planId, "astrolok_299");
  assertEquals(plan.planName, "Astrolok Monthly 299");
  assertEquals(plan.recurringAmount, 299);
  assertEquals(plan.priceLabel, "₹299");
});

Deno.test("everyone else is on ₹499, including an account with no plan yet", () => {
  for (const variant of ["plan_499", null, undefined, "plan_1"]) {
    const plan = planFor(config(BOTH), variant);
    assertEquals(plan.variant, "plan_499", `variant ${variant}`);
    assertEquals(plan.planId, "astrolok_499");
    assertEquals(plan.recurringAmount, 499);
  }
});

Deno.test("a ₹299 account falls back to ₹499 while the ₹299 plan cannot be charged", () => {
  // Falling back keeps the paywall and the mandate on one price; a mandate opened against a blank
  // plan id would instead fail at checkout.
  for (const id of ["", "-", "TBD"]) {
    const plan = planFor(config({ ...BOTH, cashfree_plan_id_299: id }), "plan_299");
    assertEquals(plan.variant, "plan_499", `plan id ${JSON.stringify(id)}`);
  }

  assertEquals(
    pricingPlans(config({ ...BOTH, cashfree_recurring_amount_299: "0" })).alternate,
    null,
    "a zero amount is not a plan",
  );
});

Deno.test("the split needs both the switch and a ₹299 plan to alternate onto", () => {
  assert(splitEnabled(config({ ...BOTH, pricing_split_enabled: "true" })));
  assertFalse(splitEnabled(config({ ...BOTH, pricing_split_enabled: "false" })));
  assertFalse(splitEnabled(config(BOTH)), "absent is off");
  assertFalse(
    splitEnabled(config({ ...BOTH, pricing_split_enabled: "true", cashfree_plan_id_299: "" })),
    "switched on with nothing to charge",
  );
});

Deno.test("a blank label is written from the amount rather than left blank", () => {
  const { standard, alternate } = pricingPlans(
    config({ ...BOTH, plan_price_label: "", plan_price_label_299: "" }),
  );

  assertEquals(standard.priceLabel, "₹499");
  assertEquals(alternate?.priceLabel, "₹299");
});

Deno.test("the device is told its own price and nothing that names a Cashfree plan", () => {
  assertEquals(planPayload(planFor(config(BOTH), "plan_299")), {
    variant: "plan_299",
    price_label: "₹299",
    amount: 299,
  });
});
