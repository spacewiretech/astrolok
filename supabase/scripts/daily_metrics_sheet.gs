/**
 * The receiving end of the daily marketing push.
 *
 * Lives in the marketing spreadsheet, not in this repo's deploy: paste it into
 * Extensions > Apps Script on the sheet itself. It is kept here so the two halves of the
 * integration can be read together — the other half is
 * supabase/migrations/20260922000001_daily_metrics.sql (and the migrations after it), which POSTs
 *
 *   { "secret": "...", "rows": [ { "report_date": "2026-09-21", "signups": 42, "trials": 9, ... }, ... ] }
 *
 * once a morning at 09:00 IST: the last 30 days, not just yesterday, because the trial-outcome
 * columns describe each day's trials and keep changing for weeks after the day itself. Every row
 * is an upsert on its date. The older single-day body — the row's fields at the top level, beside
 * the secret — is still accepted.
 *
 * ---------------------------------------------------------------- setup
 *
 * 1. Extensions > Apps Script, paste this in, save.
 * 2. Project Settings > Script Properties: add METRICS_SECRET with a long random value.
 * 3. Run `installHeaders` from the editor. It adds whichever headers are missing and leaves the
 *    rest alone, so it lays out a blank sheet and also adds a column added to COLUMNS later — as a
 *    new column inserted straight after the one before it in COLUMNS, so nothing to its right is
 *    overwritten and formulas there shift along with their columns.
 *    It is run from the editor, not through the web app, so it needs no deployment.
 * 4. Run `setup` once from the editor. It grants the permissions and prints whether the
 *    headers below were all found — do this before deploying, so a typo in COLUMNS surfaces
 *    here rather than as a silently missing column at nine tomorrow morning.
 * 5. Deploy > New deployment > Web app.
 *      Execute as: Me.   Who has access: Anyone.
 *    "Anyone" is what lets a database with no Google account post at all; the secret in step 2
 *    is what stops anyone else. Never remove it.
 * 6. Copy the /exec URL into app_config.metrics_sheet_url, and the same secret into
 *    app_config.metrics_sheet_secret.
 *
 * Re-deploying after an edit needs Deploy > Manage deployments > edit > New version. A plain
 * save does not change what the /exec URL serves, which is the usual reason a fix appears to
 * have done nothing.
 *
 * ---------------------------------------------------------------- verifying a run
 *
 * The sheet is the only reliable record of whether a day was written. pg_net keeps the reply in
 * net._http_response, and a 200 carrying {"ok":true,...} is the script's own word and can be
 * trusted. But Apps Script serves that reply through a 302 to script.googleusercontent.com, and
 * that second hop intermittently answers 404 with a Google HTML page (it opens with
 * window['ppConfig']). By then the write has already happened: on 2026-09-23 two such 404s were
 * logged and both rows were correctly in the sheet. So a ppConfig 404 means "look at the sheet",
 * not "it failed" — and since the write is an upsert, re-posting the day is always safe.
 */

// Which sheet to write. Empty string means the first tab.
var SHEET_NAME = '';

// The row the headers are on. Data is assumed to start directly below it.
var HEADER_ROW = 1;

// Payload field -> the exact header text above the column it belongs in. Matching on the header
// rather than on a column letter is what lets the layout be rearranged, or a column inserted in
// the middle, without touching this script. Case and surrounding spaces are ignored.
//
// What it does NOT survive is the header itself being renamed: the day "Subscription Renewed"
// became "Subs Renewed" the script answered `no column headed "Subscription Renewed"` — with HTTP
// 200 — and wrote nothing. If a header is renamed on the sheet, rename it here, run `setup` to
// see every one found, and deploy a new version.
//
// Order matters only to `installHeaders`, which puts a missing column straight after the one
// listed before it. The six trial outcomes describe the trials that *started* on the row's date,
// wherever they have got to since; see supabase/migrations/20260928000002_trial_outcomes.sql.
var COLUMNS = {
  report_date: 'Date',
  signups: 'Signups',
  trials: 'Trials',
  renewals: 'Subs Renewed',
  renewals_499: 'Renewed 499',
  renewals_299: 'Renewed 299',
  cancelled_in_trial: 'Cancelled during the trial, before the debit',
  failed_then_cancelled: 'Debit failed (insufficient funds), then cancelled',
  failed_mandate_active: 'Debit failed (insufficient funds), mandate still active',
  paused_in_upi: 'Paused the mandate in their UPI app',
  debit_pending: 'Debit stuck in pending',
  outcome_other: 'Other'
};

function doPost(e) {
  var body;
  try {
    body = JSON.parse((e && e.postData && e.postData.contents) || '{}');
  } catch (err) {
    return reply_({ ok: false, error: 'body is not JSON' });
  }

  // Both sides are trimmed before comparing. The secret is pasted by hand into two different web
  // forms — Script Properties here, app_config on the Supabase dashboard — and a long random string
  // picks up a trailing newline on the way into one of them far more often than not. Untrimmed,
  // that answers 'bad secret' with nothing to suggest the two values look identical on screen.
  var expected = String(PropertiesService.getScriptProperties().getProperty('METRICS_SECRET') || '').trim();
  if (!expected) return reply_({ ok: false, error: 'METRICS_SECRET is not set on the script' });
  if (String(body.secret == null ? '' : body.secret).trim() !== expected) {
    return reply_({ ok: false, error: 'bad secret' });
  }

  // Many days as `rows`, or one day's fields at the top level as the first version sent them.
  var rows = Array.isArray(body.rows) ? body.rows : [body];
  if (!rows.length) return reply_({ ok: false, error: 'no rows' });
  for (var i = 0; i < rows.length; i++) {
    if (!rows[i] || !rows[i].report_date) return reply_({ ok: false, error: 'no report_date in row ' + i });
  }

  // Two deliveries for the same date must not become two rows, so the whole read-then-write is
  // taken under a lock. Without it a retry arriving while the first is still searching finds no
  // matching date either, and both append.
  var lock = LockService.getScriptLock();
  if (!lock.tryLock(30000)) return reply_({ ok: false, error: 'busy' });

  try {
    return reply_(writeRows_(rows));
  } catch (err) {
    return reply_({ ok: false, error: String(err) });
  } finally {
    lock.releaseLock();
  }
}

/**
 * Every reply is JSON, so a rejected post shows up as a readable reason in `net._http_response`
 * rather than as Apps Script's own HTML error page.
 */
function reply_(payload) {
  return ContentService
    .createTextOutput(JSON.stringify(payload))
    .setMimeType(ContentService.MimeType.JSON);
}

/** Upserts each day in `rows`. Returns what happened, which is echoed back to pg_net. */
function writeRows_(rows) {
  var sheet = targetSheet_();
  var tz = sheet.getParent().getSpreadsheetTimeZone();
  var index = headerIndex_(sheet);

  var missing = Object.keys(COLUMNS).filter(function (field) {
    return index[field] === undefined;
  });
  if (missing.length) {
    return {
      ok: false,
      error: 'no column headed ' + missing.map(function (f) { return '"' + COLUMNS[f] + '"'; }).join(', ')
    };
  }

  var dateCol = index.report_date;
  var firstDataRow = HEADER_ROW + 1;
  var lastRow = sheet.getLastRow();

  // The date column as it stands, normalised to yyyy-MM-dd so a cell holding a real Date and a
  // payload holding a string compare equal. Read once for the whole batch and kept up to date as
  // rows are appended, so two rows for the same date in one body still land on one row.
  var existing = [];
  var free = [];
  if (lastRow >= firstDataRow) {
    var block = sheet.getRange(firstDataRow, 1, lastRow - firstDataRow + 1, sheet.getLastColumn()).getValues();
    existing = block.map(function (row) { return dateKey_(row[dateCol - 1], tz); });

    // Rows laid out ahead of the data — formulas dragged down past the last day, with every
    // column this script writes still empty. A new day goes into the first of these rather than
    // below them, so it picks up the formulas instead of arriving without any and being sorted up
    // past them.
    free = block
      .map(function (row, i) {
        var empty = Object.keys(COLUMNS).every(function (field) {
          return String(row[index[field] - 1]).trim() === '';
        });
        return empty ? i : -1;
      })
      .filter(function (i) { return i >= 0; });
  }

  var updated = 0;
  var appended = 0;
  rows.forEach(function (body) {
    var date = String(body.report_date).trim();
    var target = existing.indexOf(date);
    var row;
    if (target >= 0) {
      row = firstDataRow + target;
      updated++;
    } else {
      var slot = free.length ? free.shift() : Math.max(existing.length, lastRow - firstDataRow + 1);
      row = firstDataRow + slot;
      existing[slot] = date;
      lastRow = Math.max(lastRow, row);
      appended++;
    }

    // Written cell by cell rather than as one range, because the columns need not be adjacent and
    // anything between them belongs to whoever designed the sheet. Driven off COLUMNS rather than
    // named one by one, so adding a count is a line in COLUMNS and a header in the sheet.
    //
    // A field the body does not carry is left alone rather than blanked, so a sender that predates
    // a column cannot wipe what a newer one wrote there.
    writeDate_(sheet.getRange(row, dateCol), date);
    Object.keys(COLUMNS).forEach(function (field) {
      if (field !== 'report_date' && Object.prototype.hasOwnProperty.call(body, field)) {
        sheet.getRange(row, index[field]).setValue(numberOr_(body[field]));
      }
    });
  });

  // Keep the sheet in date order. The ordinary daily write appends a day later than every row
  // already there, so it lands in order on its own — but a backfill over a range, or a re-post of
  // a day whose row was deleted, appends wherever it happens to arrive. That is how 2026-09-22
  // came to sit above 2026-09-21. Sorting once after the batch means the order cannot drift again,
  // whatever sequence the days turn up in.
  var dataRows = sheet.getLastRow() - firstDataRow + 1;
  if (dataRows > 1) {
    sheet.getRange(firstDataRow, 1, dataRows, sheet.getLastColumn())
         .sort({ column: dateCol, ascending: true });
  }

  return {
    ok: true,
    updated: updated,
    appended: appended,
    from: String(rows[0].report_date),
    to: String(rows[rows.length - 1].report_date)
  };
}

function targetSheet_() {
  var ss = SpreadsheetApp.getActiveSpreadsheet();
  var sheet = SHEET_NAME ? ss.getSheetByName(SHEET_NAME) : ss.getSheets()[0];
  if (!sheet) throw new Error('no sheet named "' + SHEET_NAME + '"');
  return sheet;
}

/** { payloadField: 1-based column } for every header this script recognises. */
function headerIndex_(sheet) {
  var width = sheet.getLastColumn();
  var headers = width
    ? sheet.getRange(HEADER_ROW, 1, 1, width).getDisplayValues()[0].map(normalise_)
    : [];

  var index = {};
  Object.keys(COLUMNS).forEach(function (field) {
    var at = headers.indexOf(normalise_(COLUMNS[field]));
    if (at >= 0) index[field] = at + 1;
  });
  return index;
}

function normalise_(v) {
  return String(v == null ? '' : v).trim().toLowerCase();
}

/** A date cell, however it is stored or formatted, as yyyy-MM-dd. */
function dateKey_(value, tz) {
  if (value instanceof Date) return Utilities.formatDate(value, tz, 'yyyy-MM-dd');
  return String(value == null ? '' : value).trim();
}

/**
 * The date is handed to the sheet as the plain ISO string and left to the sheet to interpret,
 * never as a Date built here.
 *
 * A Date constructed in Apps Script carries the *script project's* timezone, which is not
 * necessarily the spreadsheet's — the two are configured in different places and a new project
 * inherits neither from the other. When they differ, midnight on the 21st in one is still the
 * 20th in the other, and the row silently lands a day early. That is not hypothetical: it is
 * exactly how 2026-09-21 first arrived in this sheet labelled 2026-09-20.
 *
 * Passing the string sidesteps the question. `yyyy-mm-dd` is read the same way in every locale,
 * so the sheet stores the day that was actually sent. The number format is set first so that the
 * value still reads as a date to charts, pivots and sorting — which was the reason for building a
 * Date in the first place, and is kept.
 */
function writeDate_(cell, iso) {
  cell.setNumberFormat('yyyy-mm-dd');
  cell.setValue(String(iso).trim());
}

/** Zero is a real answer and must be written; a missing field must not become one. */
function numberOr_(v) {
  return v === null || v === undefined || v === '' ? '' : Number(v);
}

/**
 * Adds whichever headers COLUMNS expects and the sheet does not already have. Run it from the
 * editor on a blank sheet to lay the row out from nothing, and again after adding a count to
 * COLUMNS to add the new one.
 *
 * A missing column goes straight after the column of the field listed before it in COLUMNS — the
 * outcome columns land after "Renewed 299", not after whatever someone has put at the far right.
 * It is a whole new column, inserted, so nothing already on the sheet is overwritten: columns to
 * its right move over one, and formulas that point at them move with them. With nothing before it
 * to follow (a blank sheet) it takes the first empty header cell instead.
 *
 * A header already present is left exactly where it is, whatever order the sheet keeps its columns
 * in, so this is safe to re-run, and safe on a sheet somebody else has laid out.
 *
 * An earlier version refused outright if the header row had anything on it at all. That made it
 * useless for the case it is most needed in — adding a column to a sheet already carrying data —
 * and left typing the header by hand as the only route, which is where two attempts went astray.
 */
function installHeaders() {
  var sheet = targetSheet_();
  var added = [];
  var previousCol = null;

  Object.keys(COLUMNS).forEach(function (field) {
    // Re-read each time: an insertion moves every column to its right.
    var index = headerIndex_(sheet);
    if (index[field] !== undefined) {
      previousCol = index[field];
      return;
    }

    var col;
    if (previousCol !== null) {
      sheet.insertColumnAfter(previousCol);
      col = previousCol + 1;
    } else {
      var width = sheet.getLastColumn();
      var header = width ? sheet.getRange(HEADER_ROW, 1, 1, width).getDisplayValues()[0] : [];
      col = 1;
      while (col <= header.length && normalise_(header[col - 1]) !== '') col++;
    }

    var cell = sheet.getRange(HEADER_ROW, col);
    cell.setValue(COLUMNS[field]);
    // The outcome headers are sentences; wrapped, they stay readable without a column 50
    // characters wide.
    cell.setWrap(true);
    previousCol = col;
    added.push('"' + COLUMNS[field] + '" -> column ' + cell.getA1Notation().replace(/\d+/, ''));
  });

  Logger.log(
    added.length
      ? 'Added ' + added.join(', ') + ' on "' + sheet.getName() + '".'
      : 'Nothing to add — every header in COLUMNS is already on row ' + HEADER_ROW + '.'
  );
}

/**
 * Run once from the editor, before deploying. Grants the permissions the web app needs and
 * reports whether every header in COLUMNS was actually found.
 */
function setup() {
  var sheet = targetSheet_();
  var index = headerIndex_(sheet);

  Object.keys(COLUMNS).forEach(function (field) {
    var col = index[field];
    Logger.log(
      col
        ? '"' + COLUMNS[field] + '" -> column ' + sheet.getRange(1, col).getA1Notation().replace(/\d+/, '')
        : 'NOT FOUND: no column headed "' + COLUMNS[field] + '" on row ' + HEADER_ROW
    );
  });

  Logger.log(
    PropertiesService.getScriptProperties().getProperty('METRICS_SECRET')
      ? 'METRICS_SECRET is set.'
      : 'METRICS_SECRET is NOT set — add it under Project Settings > Script Properties.'
  );
}
