import { loadConfig } from "../_shared/config.ts";
import { fail, json, preflight } from "../_shared/cors.ts";
import { serviceClient, userIdForBearer } from "../_shared/db.ts";
import { asUserRow, graceHoursFrom, isEntitled, USER_COLUMNS } from "../_shared/entitlement.ts";
import {
  asKundaliRow,
  KUNDALI_COLUMNS,
  kundaliPayload,
  KundaliRow,
  kundaliSettings,
  kundaliState,
  parseKundaliRequest,
  sameBirthInputs,
} from "../_shared/kundali.ts";
import { computeKundaliChart, kundaliChartToJson } from "../_shared/kundali_chart.ts";

/**
 * The kundali: ask for one, check on it, and read it once it is revealed.
 *
 *   POST {action: "status", surface?: "home" | "waiting"}  → {kundali: null | <summary>}
 *   POST {action: "report"}                                 → {kundali: <summary + chart + report>}
 *        409 not_ready until `unlock_at` has passed and the reading is written
 *   POST {action: "request", dob, birth_time, place: {place_id?, label, lat, lng, time_zone_id}}
 *                                                           → {kundali: <summary>}
 *        429 limit_reached when the regenerations are spent
 *
 * All three go through `kundaliPayload`, the only serializer, so the lock on the report cannot be
 * forgotten by a fourth action added later.
 *
 * The chart is cast here, at request time — it is arithmetic and takes milliseconds. The reading
 * is not: `kundali-worker` writes it a few minutes later, and it is revealed at `unlock_at`.
 *
 * Open to every entitled account, trial included, and deliberately outside the palm/face trial
 * reading allowance: there is one live kundali per account, and the reveal a day later is the
 * point of the feature.
 */

Deno.serve(async (req) => {
  const cors = preflight(req);
  if (cors) return cors;

  const db = serviceClient();
  const userId = await userIdForBearer(db, req.headers.get("Authorization"));
  if (!userId) return fail("unauthorized", "Please sign in again.", 401);

  let body: Record<string, unknown> = {};
  try {
    body = await req.json();
  } catch {
    // An empty body is a status check.
  }

  const config = await loadConfig(db);
  const settings = kundaliSettings(config);
  const now = new Date();

  const { data: userRow, error: userError } = await db
    .from("users")
    .select(USER_COLUMNS)
    .eq("user_id", userId)
    .single();
  if (userError || !userRow) {
    console.error("kundali: user lookup failed", userError);
    return fail("server_error", "Something went wrong. Please try again.", 500);
  }
  const user = asUserRow(userRow);
  const entitled = isEntitled(user, graceHoursFrom(config), now);
  if (!entitled) {
    return fail("not_entitled", "Your subscription has ended. Renew to see your Kundali.", 402);
  }

  const [liveResult, usedResult] = await Promise.all([
    db.from("kundalis").select(KUNDALI_COLUMNS).eq("user_id", userId).is("superseded_at", null).maybeSingle(),
    db.from("kundalis").select("id", { count: "exact", head: true }).eq("user_id", userId)
      .not("superseded_at", "is", null),
  ]);
  if (liveResult.error || usedResult.error) {
    console.error("kundali: lookup failed", liveResult.error ?? usedResult.error);
    return fail("server_error", "Something went wrong. Please try again.", 500);
  }

  const live = liveResult.data ? asKundaliRow(liveResult.data) : null;
  const regenerationsLeft = settings.maxRegenerations - (usedResult.count ?? 0);

  const summary = (row: KundaliRow, left = regenerationsLeft, includeReport = false) =>
    kundaliPayload(row, {
      now,
      entitled,
      includeReport,
      regenerationsLeft: left,
      unlockHours: settings.unlockHours,
      stageFractions: settings.stageFractions,
    });

  switch (body.action ?? "status") {
    // ------------------------------------------------------------ status
    case "status": {
      if (!live) return json({ kundali: null });

      // The halfway reminder is skipped for anyone who has come back to look at the wait already.
      if (body.surface === "waiting") {
        const { error } = await db.from("kundalis")
          .update({ waiting_last_viewed_at: now.toISOString() })
          .eq("id", live.id);
        if (error) console.error(`kundali ${live.id}: could not stamp waiting view`, error);
      }
      return json({ kundali: summary(live) });
    }

    // ------------------------------------------------------------ report
    case "report": {
      if (!live) return fail("not_found", "You haven't asked for your Kundali yet.", 404);
      if (kundaliState(live, now) !== "ready" || !live.report) {
        return fail("not_ready", "Your Kundali isn't ready to be revealed yet.", 409);
      }

      let row = live;
      if (!live.first_viewed_at) {
        const { error } = await db.from("kundalis")
          .update({ first_viewed_at: now.toISOString() })
          .eq("id", live.id)
          .is("first_viewed_at", null);
        if (error) console.error(`kundali ${live.id}: could not stamp first view`, error);
        row = { ...live, first_viewed_at: now.toISOString() };
      }
      return json({ kundali: summary(row, regenerationsLeft, true) });
    }

    // ------------------------------------------------------------ request
    case "request": {
      const parsed = parseKundaliRequest(body, now);
      if (!parsed.ok) return fail("invalid_request", parsed.message, 400);
      const request = parsed.value;

      if (live && sameBirthInputs(live, request)) {
        if (live.status !== "failed") return json({ kundali: summary(live) });

        // A generation that ran out of attempts, asked for again with the same details. Not a
        // regeneration — the user changed nothing — so it costs them nothing, and the reveal keeps
        // its original time unless that has already passed.
        const floor = now.getTime() + (settings.generateDelayMinutes + 30) * 60_000;
        const unlockAt = new Date(Math.max(Date.parse(live.unlock_at), floor)).toISOString();
        const { data, error } = await db.from("kundalis")
          .update({
            status: "queued",
            attempts: 0,
            last_error: null,
            locked_at: null,
            next_attempt_at: new Date(now.getTime() + settings.generateDelayMinutes * 60_000).toISOString(),
            unlock_at: unlockAt,
          })
          .eq("id", live.id)
          .select(KUNDALI_COLUMNS)
          .single();
        if (error || !data) {
          console.error(`kundali ${live.id}: could not requeue`, error);
          return fail("server_error", "Something went wrong. Please try again.", 500);
        }
        return json({ kundali: summary(asKundaliRow(data)) });
      }

      if (live && regenerationsLeft <= 0) {
        return fail(
          "limit_reached",
          "Your Kundali has already been re-cast the most times allowed. Contact support if your birth details were wrong.",
          429,
        );
      }

      const chart = computeKundaliChart({
        dob: request.dob,
        birthTime: request.birthTime,
        utcOffsetSeconds: request.utcOffsetSeconds,
        latitude: request.place.latitude,
        longitude: request.place.longitude,
        asOf: now,
      });
      if (!chart) return fail("invalid_request", "Please check your birth details and try again.", 400);

      const { data: inserted, error: insertError } = await db.rpc("replace_live_kundali", {
        p_user_id: userId,
        p_row: {
          dob: request.dob,
          birth_time: request.birthTime,
          birth_place: request.place.label,
          birth_place_id: request.place.placeId,
          birth_lat: request.place.latitude,
          birth_lng: request.place.longitude,
          birth_tz: request.place.timeZoneId,
          utc_offset_seconds: request.utcOffsetSeconds,
          chart: kundaliChartToJson(chart),
          unlock_at: new Date(now.getTime() + settings.unlockHours * 3600_000).toISOString(),
          next_attempt_at: new Date(now.getTime() + settings.generateDelayMinutes * 60_000).toISOString(),
        },
      });

      const row = Array.isArray(inserted) ? inserted[0] : inserted;
      if (insertError || !row) {
        console.error("kundali: could not create", insertError);
        return fail("server_error", "Something went wrong. Please try again.", 500);
      }

      // The form's details become the account's: the chat and Profile read the same birth date and
      // time. The chat still treats `birth_time` as IST — see the note on `users.birth_tz`.
      const { error: profileError } = await db.from("users").update({
        dob: request.dob,
        birth_time: request.birthTime,
        birth_place: request.place.label,
        birth_place_id: request.place.placeId,
        birth_lat: request.place.latitude,
        birth_lng: request.place.longitude,
        birth_tz: request.place.timeZoneId,
        birth_coords_at: now.toISOString(),
      }).eq("user_id", userId);
      if (profileError) console.error("kundali: could not save birth details to the profile", profileError);

      return json({ kundali: summary(asKundaliRow(row), live ? regenerationsLeft - 1 : regenerationsLeft) });
    }

    default:
      return fail("invalid_request", "Malformed request.", 400);
  }
});
