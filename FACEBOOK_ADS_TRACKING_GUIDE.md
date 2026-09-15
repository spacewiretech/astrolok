# Facebook Ads → Mixpanel: Tracking Every Ad from Download to ₹499

**For:** Marketing team
**App:** Astrolok (Android): `com.spacewire.astrolok`
**Last updated:** 14 September 2026

This guide covers how to run any number of Facebook/Instagram ads and see, **for each ad**, in Mixpanel:

```
Download  →  Signup  →  ₹3 trial started  →  ₹499 deducted after the trial
```

---

## 1. TL;DR

1. Build a **Play Store link per ad** that has the campaign, ad set and ad names inside `referrer=` (§3).
2. Run the ad as a **Traffic campaign with a Website destination** and paste that link in. App Promotion campaigns can't carry it (§2).
3. **Name the ad in Ads Manager exactly as in the link**, and give every ad its own link (§4).
4. **Test one install** before spending (§5).
5. In Mixpanel, open the **Ad → ₹499 funnel** and break it down by `campaign` → `adset` → `ad` (§6).

> **Why this matters:** Ads Manager still can't break ₹499 payers out per ad. The app sends Facebook the ₹3 trial as a "Purchase", and the server now also sends the ₹499 monthly deduction as a "Purchase" (see §10) — but Ads Manager adds the two together under one "Purchase" number, so it can't tell you which ads produced *paying* subscribers rather than cheap trials. **Mixpanel is still the only place you can see that.**

---

## 2. Pick the right campaign type first

This is the most important decision. Get it wrong and Mixpanel won't show per-ad results.

| | **Traffic campaign → Play Store link** (this guide) | **App Promotion (App installs) campaign** |
|---|---|---|
| Can you set the Play Store link? | ✅ Yes | ❌ No. Meta builds the store link itself |
| Campaign / ad set / ad names in Mixpanel | ✅ Yes | ❌ No. You only see `acquisition_source = meta`, and `campaign` shows Meta's own code (something like `fb4a`) |
| Download → ₹499 per ad in Mixpanel | ✅ Yes | ❌ Only a total for all of Meta |
| What Meta optimises for | Link clicks / landing page views | Installs or in-app events (the app sends Purchase / StartTrial for the ₹3 trial, and the server adds a Purchase for each ₹499 renewal — §10) |

**Recommended approach**

- **Testing creatives and audiences** (you need to know which ad makes ₹499 payers): use **Traffic campaigns with tracked links**.
- **Scaling winners**: App Promotion campaigns can get cheaper installs. Judge them in Ads Manager, and in Mixpanel only as the `meta` total.

---

## 3. Build the tracked Play Store link

### 3.1 The format

```
https://play.google.com/store/apps/details?id=com.spacewire.astrolok&referrer=<ENCODED TRACKING VALUES>
```

Everything after `referrer=` is handed to the app by Google Play on first open. **It must be URL-encoded**: `=` becomes `%3D` and `&` becomes `%26`. If it isn't, Google Play treats your values as separate link parameters and drops them.

### 3.2 The values

| Link parameter | Put in | Shows in Mixpanel as | Example |
|---|---|---|---|
| `utm_source` | Always `facebook` (or `instagram`) | `acquisition_source = meta` | `facebook` |
| `utm_medium` | Always `paid` | (used only to mark it paid) | `paid` |
| `utm_campaign` | Campaign name | `campaign` | `palm_diwali_oct26` |
| `utm_term` | Ad set name | `adset` | `hindi_25_45` |
| `utm_content` | Ad name | `ad` | `palm_reel_v1` |
| `utm_id` *(optional)* | Campaign ID from Ads Manager | `campaign_id` | `120210000000001` |

### 3.3 Example: one ad

**Before encoding** (readable, **don't paste this into Facebook**):

```
utm_source=facebook&utm_medium=paid&utm_campaign=palm_diwali_oct26&utm_term=hindi_25_45&utm_content=palm_reel_v1
```

**Final link** (paste this):

```
https://play.google.com/store/apps/details?id=com.spacewire.astrolok&referrer=utm_source%3Dfacebook%26utm_medium%3Dpaid%26utm_campaign%3Dpalm_diwali_oct26%26utm_term%3Dhindi_25_45%26utm_content%3Dpalm_reel_v1
```

### 3.4 Naming rules (break these and your reports split or break)

- **Only lowercase letters, numbers and `_`.** No spaces, and none of `& = # % ? +`.
- **Case matters.** `Palm_Reel_V1` and `palm_reel_v1` show up as two separate rows in Mixpanel.
- **Never reuse a name for a different creative.** Changed the video? Call it `palm_reel_v2`.
- **Don't rename mid-campaign.** Old installs keep the old name.
- A good pattern: `<feature>_<theme>_<month><yy>` for campaigns, `<language>_<agefrom>_<ageto>` for ad sets, `<feature>_<format>_v<n>` for ads.

### 3.5 Running N ads: generate links in Google Sheets

Keep one row per ad. Column D creates the link automatically:

| | A: campaign | B: ad set | C: ad | D: link |
|---|---|---|---|---|
| 1 | campaign | adset | ad | link |
| 2 | palm_diwali_oct26 | hindi_25_45 | palm_reel_v1 | *(formula)* |
| 3 | palm_diwali_oct26 | hindi_25_45 | face_static_v1 | *(formula)* |
| 4 | palm_diwali_oct26 | english_25_45 | palm_reel_v1 | *(formula)* |
| … | … | … | … | … |

Formula for **D2** (drag it down for every row):

```
="https://play.google.com/store/apps/details?id=com.spacewire.astrolok&referrer="&ENCODEURL("utm_source=facebook&utm_medium=paid&utm_campaign="&A2&"&utm_term="&B2&"&utm_content="&C2)
```

**Check:** after `referrer=`, the link should contain `%3D` and `%26`, with **no plain `=` or `&`**.

**Example grid: 1 campaign × 3 ad sets × 3 ads = 9 links**

| Ad set ↓ / Ad → | `palm_reel_v1` | `face_static_v1` | `chat_carousel_v1` |
|---|---|---|---|
| `hindi_25_45` | link 1 | link 2 | link 3 |
| `english_25_45` | link 4 | link 5 | link 6 |
| `women_18_35` | link 7 | link 8 | link 9 |

Each cell is a different link. For example, link 8 (`women_18_35` + `face_static_v1`):

```
https://play.google.com/store/apps/details?id=com.spacewire.astrolok&referrer=utm_source%3Dfacebook%26utm_medium%3Dpaid%26utm_campaign%3Dpalm_diwali_oct26%26utm_term%3Dwomen_18_35%26utm_content%3Dface_static_v1
```

---

## 4. Set up the ads in Ads Manager

1. **Create campaign → Objective: Traffic.** Campaign name = your `utm_campaign` value.
2. **Ad set → Conversion location: Website.** Don't pick "App", because then Meta controls the store link. Ad set name = your `utm_term` value. Set audience, placements and budget as usual.
3. **Ad → Destination: Website URL →** paste **that ad's** link from the sheet. Ad name = your `utm_content` value.
4. **Leave the "URL parameters" box empty.** Meta adds those after the link, *outside* `referrer=`, where the app never sees them.
5. **Call to action:** `Download` (or `Install Now` if offered).
6. **Don't rely on `{{campaign.name}}`-style dynamic macros** for this. Type the real names into the link.

> ⚠️ **The #1 mistake: duplicating an ad and forgetting to change the link.** A duplicated ad keeps the original link, so all its installs get credited to the original ad. Every time you duplicate, paste the new row's link.

> ✅ **Keep Ads Manager names identical to the link values.** In §7 you'll match spend (from Ads Manager) to results (from Mixpanel) by name.

---

## 5. Test before you spend (5 minutes, once per campaign)

Use a real Android phone.

1. **Uninstall Astrolok** from the phone. The tracking only runs on a fresh install.
2. Send yourself one ad's link (for example on WhatsApp), or tap the ad from the Ads Manager preview.
3. Tap it. Google Play opens. Tap **Install**, then **Open**.
4. In **Mixpanel → Events**, search for the event **`Attribution Resolved`** from the last few minutes.
5. Check its properties:

| Property | Should be |
|---|---|
| `acquisition_source` | `meta` |
| `acquisition_channel` | `install_referrer` |
| `campaign` | your campaign name |
| `adset` | your ad set name |
| `ad` | your ad name |

**If something's wrong:**

| You see | Cause | Fix |
|---|---|---|
| `acquisition_source = organic`, no `campaign` | Link values weren't inside `referrer=`, or weren't encoded | Rebuild the link with the sheet formula, and empty the "URL parameters" box |
| `campaign = fb4a` (or similar) and no `adset` / `ad` | It's an App Promotion campaign | Use a Traffic campaign (§2) |
| No `Attribution Resolved` at all | The app was already installed, or the phone had no internet on first open | Uninstall, reinstall **from the link**, and open with internet on |
| Names look cut off or wrong | A space, `&` or `=` in a name | Follow the naming rules (§3.4) |

---

## 6. Mixpanel reports to build

### How the stages map to Mixpanel events

| Funnel stage | Mixpanel event | Filter | Sent from |
|---|---|---|---|
| **Download** (first app open) | `Attribution Resolved` | `acquisition_source = meta` | App |
| **Signed up** | `Signup Completed` | — | App |
| *(optional)* Tapped subscribe | `Subscribe Tapped` | `offer_type = trial` | App |
| **₹3 trial started** | `Mandate Authorised` | `amount = 3` | Server (confirmed by Cashfree) |
| **₹499 deducted after trial** | `Subscription Renewed` | `amount = 499` | Server (confirmed by Cashfree) |
| Trial cancelled | `Subscription Cancelled` | `was_in_trial = true` | Server |
| ₹499 deduction failed | `Subscription Payment Failed` | `kind = RECURRING` | Server |

> **Why "Server" matters:** payment events come from our server when Cashfree confirms the money moved, not from the phone. That makes them the real numbers, but **they don't carry the ad name themselves**. Mixpanel fills it in either from step 1 of a funnel or from the user's profile (`initial_campaign`, `initial_adset`, `initial_ad`). The reports below are set up for that.

> **Don't filter `amount = 499` on `Mandate Authorised`.** That is a *returning* subscriber paying full price upfront with no trial, not a new ad-driven trial.

---

### Report A: Downloads per ad (Insights)

| Setting | Value |
|---|---|
| Event | `Attribution Resolved` |
| Measure | **Unique users** |
| Filter | `acquisition_source` = `meta` · `build_mode` = `release` |
| Breakdown | `campaign` → `adset` → `ad` |
| Date range | Campaign dates |

---

### Report B: Ad → ₹499 funnel (Funnels) ⭐ the main one

| Setting | Value |
|---|---|
| Step 1 | `Attribution Resolved`, where `acquisition_source = meta` and `build_mode = release` |
| Step 2 | `Signup Completed` |
| Step 3 | `Mandate Authorised`, where `amount = 3` |
| Step 4 | `Subscription Renewed`, where `amount = 499` |
| Conversion window | **14 days** |
| Counting | **Uniques** |
| Breakdown | `campaign` → `adset` → `ad` (Mixpanel takes these from step 1, so the server steps are covered) |

What you'll read off it, per ad: downloads, signup %, trial %, and **trial → ₹499 %**.

> **Timing:** the ₹499 deduction happens after the trial ends, and a failed deduction can be retried. **Don't judge an ad on step 4 until its installs are at least 14 days old.** For an early read, use step 3 (₹3 trials), which shows up the same day.

> **If step 2 shows almost 0% for every ad:** someone who downloads is anonymous until they sign up, and joining the two needs Mixpanel's **Simplified ID Merge**. Ask the analytics owner to check *Project Settings → Identity Merge*. Until it's on, start the funnel at **`Signup Completed`** with the same breakdown. That still works, because every app event after signup carries `campaign` / `adset` / `ad`.

---

### Report C: ₹499 revenue per ad (Insights)

| Setting | Value |
|---|---|
| Event | `Subscription Renewed` |
| Measure | **Sum of property `amount`** (and a second metric: **Unique users**) |
| Breakdown | **User profile** → `initial_campaign` → `initial_adset` → `initial_ad` |
| Date range | From campaign start to today |

This includes month 2, month 3 and later, so it grows into **lifetime revenue per ad**. For *first* ₹499 deductions only, use Report B.

> Use the `initial_*` profile properties for revenue. They record the **first** ad that brought the user and never change, so a later retargeting ad can't take credit for a user you already paid to acquire.

---

### Report D: Where trials are lost (Insights)

| Metric | Event & filter | Breakdown |
|---|---|---|
| Cancelled during trial | `Subscription Cancelled`, where `was_in_trial = true` | User profile → `initial_ad` |
| ₹499 deduction failed | `Subscription Payment Failed`, where `kind = RECURRING` | User profile → `initial_ad`, then `failure_reason` |

If an ad has many trials but a high trial-cancel rate, the creative probably over-promises. If many deductions fail (`failure_reason` such as insufficient balance), the audience may not be able to afford ₹499.

**Tip:** save A–D on one Mixpanel dashboard called **"Facebook Ads: Download to ₹499"**.

---

## 7. Worked example: reading the numbers

Three ads from the `palm_diwali_oct26` campaign, each with ₹10,000 spend. Spend comes from Ads Manager; everything else comes from Mixpanel Report B (installs at least 14 days old).

*The numbers below are illustrative.*

| Ad (ad set) | Spend | Downloads | Signups | ₹3 trials | ₹499 paid | Cost / download | Cost / trial | **Cost / ₹499 payer** | **Trial → ₹499** | First-month ₹499 revenue ÷ spend |
|---|---|---|---|---|---|---|---|---|---|---|
| `palm_reel_v1` (hindi_25_45) | ₹10,000 | 800 | 560 | 120 | 30 | ₹12.5 | ₹83 | **₹333** | **25%** | 1.50× |
| `face_static_v1` (english_25_45) | ₹10,000 | 1,250 | 700 | 150 | 15 | ₹8.0 | ₹67 | **₹667** | **10%** | 0.75× |
| `chat_carousel_v1` (women_18_35) | ₹10,000 | 600 | 450 | 90 | 36 | ₹16.7 | ₹111 | **₹278** | **40%** | 1.80× |

**What this tells you:**

- By Ads Manager's view (cheapest installs, cheapest "Purchases" = ₹3 trials), `face_static_v1` looks like the winner.
- By actual ₹499 payers it's the **worst**: it brings cheap trials who don't stay.
- `chat_carousel_v1` has the most expensive downloads but the **cheapest paying subscriber**. **Scale this one.**

**Formulas** (sheet with Ads Manager spend + Mixpanel counts, matched on ad name):

```
Cost / download     = Spend ÷ Downloads
Cost / trial        = Spend ÷ ₹3 trials
Cost / ₹499 payer   = Spend ÷ ₹499 paid
Trial → ₹499 %      = ₹499 paid ÷ ₹3 trials
Revenue ÷ spend     = (₹499 paid × 499) ÷ Spend
```

---

## 8. Why Mixpanel and Ads Manager won't match

This is expected. Don't try to make the numbers equal.

| Reason | Effect |
|---|---|
| Mixpanel counts a download only once the app is **opened** (with internet) | Mixpanel downloads < Ads Manager installs |
| Someone sees the ad, doesn't tap, and later searches the Play Store | Meta may credit the ad, but Mixpanel sees it as `organic` |
| Meta counts view-through and 1-day / 7-day attribution windows | Ads Manager shows more conversions |
| Meta's "Purchase" is the ₹3 trial **and** the ₹499 renewal, added together | Ads Manager can't separate them. Use Mixpanel to see ₹499 payers per ad |
| The ₹499 reaches Meta from our server, matched on phone and account id only | Meta matches some of those to a person, not all — so its ₹499 count runs **below** Mixpanel's |
| Someone joins with a friend's **invite code** | Referral outranks the ad, so they show as `referral` |
| Someone reinstalls from a second ad | They count as a new download for the second ad, but their profile's `initial_ad` stays the first ad |
| iPhone users | This link method is Android-only |

**Rule of thumb:** use **Ads Manager for spend**, and **Mixpanel for everything after the download**, especially ₹499.

---

## 9. Quick reference

**Link parameter → Mixpanel property**

| Put in the link | Becomes | The app also accepts |
|---|---|---|
| `utm_source=facebook` / `instagram` | `acquisition_source = meta` | `meta`, `ig` |
| `utm_campaign` | `campaign` | `campaign` |
| `utm_id` | `campaign_id` | `campaign_id` |
| `utm_term` | `adset` | `adset`, `utm_adset` |
| `utm_content` | `ad` | `ad`, `utm_ad` |

**Where the ad names show up in Mixpanel**

| Where | Properties | Use for |
|---|---|---|
| Every app event after download (screens, readings, chat, payments) | `campaign`, `adset`, `ad`, `acquisition_source` | Breaking down **any** app behaviour by ad, e.g. "which ad's users do the most palm readings?" |
| User profile | `initial_campaign`, `initial_adset`, `initial_ad`, `initial_acquisition_source` | Revenue and CAC. **The first ad, never overwritten** |
| User profile | `campaign`, `adset`, `ad` | The most recent ad (can change) |

**Pre-launch checklist**

- [ ] Campaign objective is **Traffic**, conversion location **Website**
- [ ] Each ad has **its own link** from the sheet (check duplicated ads)
- [ ] Link has `%3D` / `%26` after `referrer=`
- [ ] "URL parameters" box is **empty**
- [ ] Ads Manager names **match** the link values exactly
- [ ] Names are lowercase, with `_` only
- [ ] One **test install** shows the right `campaign` / `adset` / `ad` on `Attribution Resolved`

---

## 10. Limits of the current setup (for the product/dev team)

- **App Promotion campaigns aren't readable per-ad in Mixpanel.** Meta hides the campaign details in an encrypted store referrer. Decoding it needs development work that isn't built yet.
- **The ₹499 now goes to Meta, but it ships switched off.** The server reports every recurring debit to Meta's Conversions API as a `Purchase` (`supabase/functions/_shared/facebook_capi.ts`). Before it does anything, someone has to: create a **Dataset** in Events Manager and **link it to the app**, generate an **access token** against that dataset, paste both into `app_config` (`facebook_dataset_id`, `facebook_capi_access_token`), and set `facebook_capi_enabled = true`. Validate with `facebook_capi_test_event_code` against Events Manager → Test Events first, **then clear that row** — left set, real conversions stay in test mode and optimise nothing. This is *not* the Facebook app secret, which is a different credential and must never go in `app_config`.
- **Only the renewal is sent from the server.** The ₹3 trial and a returning subscriber's full-price first month are both reported by the app itself, so the server deliberately sends nothing for them — reporting either twice would inflate ROAS and teach the optimiser to overpay.
- **Match quality is the weak link.** The server matches a renewal to a person on the hashed phone number and account id alone. It has no device advertising id, and no table stores a device model, OS version or locale, so Meta's device fields go out as placeholders. Expect Meta to credit *some* of the renewals, not all. Check the real Event Match Quality score in Events Manager; raising it means sending the SDK's `anon_id` from the app at checkout, which needs an app release.
- **`fbclid` is still being thrown away.** The Play Store referrer already carries Meta's click id to our backend, and `attribution-report` discards it. Storing it would give Meta its strongest matching signal and needs **no app release** — the cheapest remaining improvement.
- **Prices come from `app_config`.** If the trial or plan price changes, update the `amount = 3` / `amount = 499` filters in the reports.

See [MIXPANEL_TRACKING_PLAN.md](MIXPANEL_TRACKING_PLAN.md) for the full event list.
