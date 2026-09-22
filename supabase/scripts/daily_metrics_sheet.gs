/**
 * The receiving end of the daily marketing push.
 *
 * Lives in the marketing spreadsheet, not in this repo's deploy: paste it into
 * Extensions > Apps Script on the sheet itself. It is kept here so the two halves of the
 * integration can be read together — the other half is
 * supabase/migrations/20260922000001_daily_metrics.sql, which POSTs
 *
 *   { "report_date": "2026-09-21", "signups": 42, "trials": 9, "renewals": 5, "secret": "..." }
 *
 * once a morning at 09:00 IST.
 *
 * ---------------------------------------------------------------- setup
 *
 * 1. Extensions > Apps Script, paste this in, save.
 * 2. Project Settings > Script Properties: add METRICS_SECRET with a long random value.
 * 3. On a sheet with no header row yet, run `installHeaders` once to write them. It refuses a
 *    row that already has anything on it, so it is safe to run against a sheet someone has
 *    already laid out — that case wants the headers added by hand.
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
 */

// Which sheet to write. Empty string means the first tab.
var SHEET_NAME = '';

// The row the headers are on. Data is assumed to start directly below it.
var HEADER_ROW = 1;

// Payload field -> the exact header text above the column it belongs in. Matching on the header
// rather than on a column letter is what lets the layout be rearranged, or a column inserted in
// the middle, without touching this script. Case and surrounding spaces are ignored.
var COLUMNS = {
  report_date: 'Date',
  signups: 'Signups',
  trials: 'Trials',
  renewals: 'Subscription Renewed',
  renewals_499: 'Renewed 499',
  renewals_299: 'Renewed 299'
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

  if (!body.report_date) return reply_({ ok: false, error: 'no report_date' });

  // Two deliveries for the same date must not become two rows, so the whole read-then-write is
  // taken under a lock. Without it a retry arriving while the first is still searching finds no
  // matching date either, and both append.
  var lock = LockService.getScriptLock();
  if (!lock.tryLock(30000)) return reply_({ ok: false, error: 'busy' });

  try {
    return reply_(writeRow_(body));
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

/** Upserts one day. Returns what happened, which is echoed back to pg_net. */
function writeRow_(body) {
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
  // payload holding a string compare equal.
  var existing = [];
  if (lastRow >= firstDataRow) {
    existing = sheet.getRange(firstDataRow, dateCol, lastRow - firstDataRow + 1, 1)
      .getValues()
      .map(function (row) { return dateKey_(row[0], tz); });
  }

  var target = existing.indexOf(String(body.report_date).trim());
  var row = target >= 0 ? firstDataRow + target : Math.max(lastRow + 1, firstDataRow);

  // Written cell by cell rather than as one range, because the columns need not be adjacent and
  // anything between them belongs to whoever designed the sheet. Driven off COLUMNS rather than
  // named one by one, so adding a count is a line in COLUMNS and a header in the sheet.
  writeDate_(sheet.getRange(row, dateCol), body.report_date);
  Object.keys(COLUMNS).forEach(function (field) {
    if (field !== 'report_date') {
      sheet.getRange(row, index[field]).setValue(numberOr_(body[field]));
    }
  });

  return { ok: true, row: row, action: target >= 0 ? 'updated' : 'appended', date: body.report_date };
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
 * Run once, before `setup`, on a sheet whose header row is still blank — it writes the four
 * headers COLUMNS expects. A row with anything already on it is left alone and reported instead,
 * so this cannot overwrite a layout somebody has already built; rearranging or renaming columns
 * afterwards is the sheet owner's business, and COLUMNS is what to keep in step with it.
 */
function installHeaders() {
  var sheet = targetSheet_();
  var width = sheet.getLastColumn();
  var occupied = width
    ? sheet.getRange(HEADER_ROW, 1, 1, width).getDisplayValues()[0]
        .filter(function (v) { return normalise_(v) !== ''; })
    : [];

  if (occupied.length) {
    Logger.log(
      'Row ' + HEADER_ROW + ' already holds: ' + occupied.join(', ') +
      '. Nothing written — add the missing headers by hand, or clear the row and re-run.'
    );
    return;
  }

  var headers = Object.keys(COLUMNS).map(function (field) { return COLUMNS[field]; });
  sheet.getRange(HEADER_ROW, 1, 1, headers.length).setValues([headers]);
  Logger.log('Wrote ' + headers.join(' | ') + ' to row ' + HEADER_ROW + ' of "' + sheet.getName() + '".');
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
