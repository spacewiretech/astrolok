/**
 * The price split: which plan an account pays, and when new signups are split at all.
 *
 * The failures worth guarding are quiet ones. A ₹699 account resolved to a blank Cashfree plan id
 * opens a mandate that fails at checkout, a split switched on without a ₹699 plan would hand
 * people a price nothing can charge, and a ₹299 account re-priced to anything else would be shown
 * one number while its live mandate debits another.
 */

import { assert, assertEquals, assertFalse } from "jsr:@std/assert@1";

import { AppConfig } from "../_shared/config.ts";
import {
  alternatePercent,
  configuredPlans,
  planFor,
  planPayload,
  pricingPlans,
  splitEnabled,
} from "../_shared/pricing.ts";

function config(rows: Record<string, string>): AppConfig {
  return new Map(Object.entries(rows));
}

const ALL = {
  cashfree_plan_id: "astrolok_499",
  cashfree_plan_name: "Astrolok Monthly",
  cashfree_recurring_amount: "499",
  plan_price_label: "₹499",
  cashfree_plan_id_699: "astrolok_699",
  cashfree_plan_name_699: "Astrolok Monthly 699",
  cashfree_recurring_amount_699: "699",
  plan_price_label_699: "₹699",
  cashfree_plan_id_299: "astrolok_299",
  cashfree_plan_name_299: "Astrolok Monthly 299",
  cashfree_recurring_amount_299: "299",
  plan_price_label_299: "₹299",
};

Deno.test("a ₹699 account is priced on the ₹699 plan", () => {
  const plan = planFor(config(ALL), "plan_699");

  assertEquals(plan.variant, "plan_699");
  assertEquals(plan.planId, "astrolok_699");
  assertEquals(plan.planName, "Astrolok Monthly 699");
  assertEquals(plan.recurringAmount, 699);
  assertEquals(plan.priceLabel, "₹699");
});

Deno.test("a ₹299 account keeps ₹299 after ₹699 replaced it in the split", () => {
  // Its live mandate debits ₹299 at Cashfree whatever this says, so anything else on screen would
  // be a price the account is not paying.
  const plan = planFor(config(ALL), "plan_299");

  assertEquals(plan.variant, "plan_299");
  assertEquals(plan.planId, "astrolok_299");
  assertEquals(plan.planName, "Astrolok Monthly 299");
  assertEquals(plan.recurringAmount, 299);
  assertEquals(plan.priceLabel, "₹299");
});

Deno.test("everyone else is on ₹499, including an account with no plan yet", () => {
  for (const variant of ["plan_499", null, undefined, "plan_1"]) {
    const plan = planFor(config(ALL), variant);
    assertEquals(plan.variant, "plan_499", `variant ${variant}`);
    assertEquals(plan.planId, "astrolok_499");
    assertEquals(plan.recurringAmount, 499);
  }
});

Deno.test("an account falls back to ₹499 while its own plan cannot be charged", () => {
  // Falling back keeps the paywall and the mandate on one price; a mandate opened against a blank
  // plan id would instead fail at checkout.
  for (const suffix of ["699", "299"]) {
    for (const id of ["", "-", "TBD"]) {
      const plan = planFor(
        config({ ...ALL, [`cashfree_plan_id_${suffix}`]: id }),
        `plan_${suffix}`,
      );
      assertEquals(plan.variant, "plan_499", `plan_${suffix} with plan id ${JSON.stringify(id)}`);
    }
  }

  assertEquals(
    pricingPlans(config({ ...ALL, cashfree_recurring_amount_699: "0" })).alternate,
    null,
    "a zero amount is not a plan",
  );
});

Deno.test("the split needs both the switch and a ₹699 plan to split onto", () => {
  assert(splitEnabled(config({ ...ALL, pricing_split_enabled: "true" })));
  assertFalse(splitEnabled(config({ ...ALL, pricing_split_enabled: "false" })));
  assertFalse(splitEnabled(config(ALL)), "absent is off");
  assertFalse(
    splitEnabled(config({ ...ALL, pricing_split_enabled: "true", cashfree_plan_id_699: "" })),
    "switched on with nothing to charge — a ₹299 plan alone no longer counts",
  );
});

Deno.test("the ₹699 share is a whole percent, and unreadable means nobody", () => {
  assertEquals(alternatePercent(config({ pricing_split_699_percent: "25" })), 25);
  assertEquals(alternatePercent(config({ pricing_split_699_percent: " 40 " })), 40);
  assertEquals(alternatePercent(config({ pricing_split_699_percent: "12.6" })), 13);
  assertEquals(alternatePercent(config({ pricing_split_699_percent: "150" })), 100);
  assertEquals(alternatePercent(config({ pricing_split_699_percent: "-5" })), 0);
  for (const raw of ["", "-", "TBD", "abc"]) {
    assertEquals(alternatePercent(config({ pricing_split_699_percent: raw })), 0, JSON.stringify(raw));
  }
  assertEquals(alternatePercent(config({})), 0, "absent");
});

Deno.test("every plan a mandate can be on is known, so none of their charges go unrecognised", () => {
  assertEquals(
    configuredPlans(config(ALL)).map((plan) => plan.variant),
    ["plan_499", "plan_699", "plan_299"],
  );
  assertEquals(
    configuredPlans(config({ ...ALL, cashfree_plan_id_699: "" })).map((plan) => plan.variant),
    ["plan_499", "plan_299"],
  );
});

Deno.test("a blank label is written from the amount rather than left blank", () => {
  const { standard, alternate, grandfathered } = pricingPlans(
    config({ ...ALL, plan_price_label: "", plan_price_label_699: "", plan_price_label_299: "" }),
  );

  assertEquals(standard.priceLabel, "₹499");
  assertEquals(alternate?.priceLabel, "₹699");
  assertEquals(grandfathered?.priceLabel, "₹299");
});

Deno.test("the device is told its own price and nothing that names a Cashfree plan", () => {
  assertEquals(planPayload(planFor(config(ALL), "plan_699")), {
    variant: "plan_699",
    price_label: "₹699",
    amount: 699,
  });
});
